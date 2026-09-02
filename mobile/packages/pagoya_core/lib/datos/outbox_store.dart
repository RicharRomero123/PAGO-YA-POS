// PagoYa Móvil — datos/outbox_store.dart
//
// PORT de `src/PagoYa.Data/Repositorios/OutboxStore.cs`.
//
// Lee/marca `outbox_sync`, guarda el cursor de bajada en `meta` y aplica los
// cambios remotos resolviendo conflictos.
//
// ESTRATEGIA DE MERGE POR ENTIDAD (heredada del escritorio):
//   * producto, venta (cabecera), caja  -> UPSERT con last-write-wins por
//     `updated_utc` (son mutables).
//   * detalle_ventas, movimientos_caja, inventario -> insert-if-absent
//     (inmutables, identidad UUID estable).
//   * producto DELETE / venta UPDATE (anulación) -> update con guarda LWW.
//
// ------------------------------------------------------------------
// EL STOCK NO SE RESUELVE POR LAST-WRITE-WINS
// ------------------------------------------------------------------
// Es la única regla de merge que NO es LWW, y hay que entender por qué antes
// de "simplificarla": resolver `stock_actual` por LWW PIERDE VENTAS cuando dos
// cajas venden a la vez.
//
//   stock 10. La PC vende 3 (stock 7, updated 10:00:01).
//   El móvil vende 2 (stock 8, updated 10:00:02).
//   LWW: gana el móvil -> stock 8. La venta de la PC desapareció del stock.
//
// `stock_actual` es CACHÉ DERIVADA; la verdad es el kardex `inventario`
// (append-only, UUID global). Por eso:
//
//   1. El upsert de `producto` actualiza todo MENOS `stock_actual` cuando la
//      fila ya existe (en un INSERT nuevo sí se toma, como valor de apertura).
//   2. Cada fila de `inventario` que se inserta de verdad (no un duplicado)
//      SUMA su `cantidad` al caché. Como el kardex es append-only y su UUID es
//      global, aplicar el mismo evento dos veces no suma dos veces: el
//      `ON CONFLICT DO NOTHING` devuelve 0 filas y no se toca el stock.
//      El resultado es un contador conmutativo: 10 − 3 − 2 = 5, sin importar
//      en qué orden lleguen los eventos.
//   3. Aplicar el delta NO toca `productos.updated_utc`: mover una caché no es
//      una edición, y sellarla con marca nueva le daría ventaja injusta en el
//      siguiente LWW sobre los campos que sí son editables (precio, nombre).
//   4. `recalcularStockDesdeKardex` reconstruye el valor exacto desde cero
//      cuando hace falta reparar (ver su documentación: exige la fila de
//      apertura "Stock inicial").
//
// AMBOS LADOS HACEN YA LO MISMO. `desktop-dev` replicó esta semántica en
// `src/PagoYa.Data/Repositorios/OutboxStore.cs` (quitó
// `stock_actual = excluded.stock_actual` del `DO UPDATE` y aplica deltas
// idempotentes desde el kardex), con un test extremo a extremo sobre SQLite
// que cubre el caso 10 − 2 − 3 = 5. Si algún día divergen, el que está mal es
// el que volvió al LWW.
//
// OJO con la distinción: una VENTA LOCAL sí toca `updated_utc` al descontar
// (igual que `VentaRepository.cs`), porque ahí la escritura de negocio es la
// venta. Lo que no lo toca es la aplicación de un delta REMOTO.

library;

import '../dominio/caja.dart';
import '../dominio/hotel.dart';
import '../dominio/inventario.dart';
import '../dominio/producto.dart';
import '../dominio/restaurante.dart';
import '../dominio/tiempo.dart';
import '../dominio/uuid.dart';
import '../dominio/venta.dart';
import '../nube/contratos_sync.dart';
import '../nube/puerto_outbox.dart';
import 'ejecutor_sql.dart';
import 'esquema.dart';
import 'notificador_tablas.dart';
import 'outbox.dart';
import 'sentencias.dart';

/// Acceso al outbox local y aplicación de cambios remotos.
///
/// Implementa [AlmacenOutbox], el puerto que `lib/nube/` consume. La dirección
/// de la dependencia es a propósito: el puerto vive con quien lo usa, así
/// `nube/` no depende de drift — exactamente como `PagoYa.Cloud` depende de
/// `IOutboxStore` y no de `PagoYa.Data`. Sin este `implements`, `OutboxStore` no
/// encaja en `FabricaSync.crear(outbox: …)`.
final class OutboxStore implements AlmacenOutbox {
  final EjecutorSql _db;

  /// Señales para los `Stream` de observación. Aplicar cambios remotos toca
  /// tablas de negocio, así que la pantalla de inventario o el mapa del salón
  /// tienen que enterarse igual que si el cambio hubiera sido local.
  final FuenteDeCambios _cambios;

  OutboxStore(this._db)
      : _cambios = _db is FuenteDeCambios ? _db : const SinCambios();

  // ------------------------------------------------------------- Subida ---

  /// Eventos pendientes ordenados por antigüedad (máximo [max]).
  ///
  /// El orden por `created_utc` importa: la nube aplica los eventos en el orden
  /// recibido, y una venta no puede llegar antes que la caja a la que apunta.
  @override
  Future<List<EventoSyncLocal>> leerPendientes(int max) async {
    final filas = await _db.consultar(
      '''
      SELECT id, entidad, entidad_id, operacion, payload_json, intentos,
             origen_caja_id, created_utc
      FROM outbox_sync
      WHERE estado = ?
      ORDER BY created_utc
      LIMIT ?
      ''',
      [EstadoOutbox.pendiente, max],
    );
    return filas
        .map(EventoSyncLocalFila.desdeFila)
        .toList(growable: false);
  }

  /// Marca eventos como enviados (idempotente por id de outbox).
  ///
  /// La comparación de ids es **insensible a mayúsculas** (contrato de
  /// [AlmacenOutbox]): el backend puede devolver el mismo UUID con otra caja de
  /// la que se envió, y `IN (...)` sobre TEXT en SQLite es sensible por defecto.
  /// Sin el `lower()`, esos eventos nunca se marcarían y se reenviarían para
  /// siempre.
  @override
  Future<void> marcarEnviados(List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.ejecutar(
      'UPDATE outbox_sync SET estado = ?, enviado_utc = ? '
      'WHERE lower(id) IN (${Sql.marcas(ids.length)})',
      [
        EstadoOutbox.enviado,
        TiempoUtc.formatoO(DateTime.now()),
        ..._normalizar(ids),
      ],
    );
  }

  /// Incrementa intentos; al alcanzar [maxIntentos] manda el evento a
  /// dead-letter (`estado = 2`) para que un evento venenoso no bloquee la cola.
  ///
  /// Devuelve **cuántos cayeron a dead-letter en esta llamada**, que es el
  /// número que pinta la pantalla de nube. Se cuenta ANTES del `UPDATE`: los
  /// que están pendientes y cuyo siguiente intento alcanza el máximo. Contarlo
  /// después no distinguiría los que ya estaban muertos de antes.
  @override
  Future<int> registrarFallo(List<String> ids, int maxIntentos) async {
    if (ids.isEmpty) return 0;
    final normalizados = _normalizar(ids);
    final marcas = Sql.marcas(ids.length);

    final aDeadLetter = await _db.escalar(
      'SELECT COUNT(*) FROM outbox_sync '
      'WHERE estado = ? AND intentos + 1 >= ? AND lower(id) IN ($marcas)',
      [EstadoOutbox.pendiente, maxIntentos, ...normalizados],
    );

    await _db.ejecutar(
      '''
      UPDATE outbox_sync
      SET intentos = intentos + 1,
          estado = CASE WHEN intentos + 1 >= ? THEN ? ELSE estado END
      WHERE lower(id) IN ($marcas)
      ''',
      [maxIntentos, EstadoOutbox.error, ...normalizados],
    );

    return (aDeadLetter as num?)?.toInt() ?? 0;
  }

  /// Cuántos eventos quedan por enviar (para el indicador de la UI de nube).
  @override
  Future<int> contarPendientes() => _contarPorEstado(EstadoOutbox.pendiente);

  /// Cuántos eventos quedaron apartados en dead-letter.
  ///
  /// Si este número crece, hay algo que soporte debe mirar: son ventas que ya
  /// existen en el celular y que la nube nunca recibió.
  @override
  Future<int> contarDeadLetter() => _contarPorEstado(EstadoOutbox.error);

  /// Devuelve a la cola los eventos en dead-letter y reinicia sus intentos.
  ///
  /// Es el botón "reintentar los fallidos" de soporte. Se reinicia `intentos` a
  /// 0 a propósito: si se dejara el contador, el primer fallo volvería a
  /// mandarlos a dead-letter y el botón no serviría de nada. Devuelve cuántos
  /// volvieron a `estado = 0`.
  @override
  Future<int> reencolarDeadLetter() async {
    final n = await _db.ejecutarContando(
      'UPDATE outbox_sync SET estado = ?, intentos = 0 WHERE estado = ?',
      [EstadoOutbox.pendiente, EstadoOutbox.error],
    );
    if (n > 0) _cambios.notificarCambio({Tablas.outboxSync});
    return n;
  }

  Future<int> _contarPorEstado(int estado) async {
    final v = await _db.escalar(
      'SELECT COUNT(*) FROM outbox_sync WHERE estado = ?',
      [estado],
    );
    return (v as num?)?.toInt() ?? 0;
  }

  static List<String> _normalizar(List<String> ids) =>
      ids.map((i) => i.trim().toLowerCase()).toList(growable: false);

  // ------------------------------------------------------------- Cursor ---

  @override
  Future<String?> leerCursor() async {
    final v = await _db.escalar(
      'SELECT valor FROM meta WHERE clave = ?',
      [ClavesMeta.cursorSync],
    );
    return v?.toString();
  }

  @override
  Future<void> guardarCursor(String cursor) => _db.ejecutar(
        'INSERT INTO meta (clave, valor) VALUES (?, ?) '
        'ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor',
        [ClavesMeta.cursorSync, cursor],
      );

  // ------------------------------------------------------------- Bajada ---

  /// Aplica los cambios descargados de la nube. Devuelve cuántos se aplicaron
  /// de verdad (los que perdieron el LWW o ya existían cuentan 0).
  ///
  /// TODO va en UNA transacción: si un evento revienta a la mitad, la BD no
  /// queda con media venta aplicada.
  @override
  Future<int> aplicarCambiosRemotos(List<CambioRemoto> cambios) async {
    if (cambios.isEmpty) return 0;

    // Tablas tocadas, para avisar a los observadores DESPUÉS del commit: si se
    // avisara dentro, un rollback dejaría a la UI pintando datos que ya no
    // existen.
    final tocadas = <String>{};

    final aplicados = await _db.transaccion((tx) async {
      var aplicados = 0;
      for (final c in cambios) {
        tocadas.addAll(_tablasDe(c.entidad));
        final op = c.operacion.toUpperCase();
        switch (c.entidad.toLowerCase()) {
          case EntidadesSync.producto:
            aplicados += op == OperacionesSync.delete
                ? await _bajaProducto(tx, c)
                : await _upsertProducto(tx, c);
          case EntidadesSync.venta:
            aplicados += op == OperacionesSync.update
                ? await _estadoVenta(tx, c)
                : await _venta(tx, c);
          case EntidadesSync.caja:
            aplicados += await _caja(tx, c);
          case EntidadesSync.movimientoCaja:
            aplicados += await _movimientoCaja(tx, c);
          case EntidadesSync.inventario:
            aplicados += await _inventario(tx, c);
          case EntidadesSync.mesa:
            aplicados += await _mesa(tx, c);
          case EntidadesSync.pedido:
            aplicados += await _pedido(tx, c);
          case EntidadesSync.pedidoLinea:
            aplicados += await _pedidoLinea(tx, c);
          case EntidadesSync.habitacion:
            aplicados += await _habitacion(tx, c);
          case EntidadesSync.estadiaHabitacion:
            aplicados += await _estadia(tx, c);
          default:
            // Entidad no sincronizada: se ignora en silencio, igual que el
            // escritorio. Es lo que permite que una versión nueva de la PC
            // emita entidades que este móvil todavía no conoce.
            break;
        }
      }
      return aplicados;
    });

    if (aplicados > 0) _cambios.notificarCambio(tocadas);
    return aplicados;
  }

  /// Tablas que toca aplicar un cambio de cada entidad.
  ///
  /// `producto` incluye `inventario` y viceversa porque el stock cruza las dos:
  /// aplicar un kardex remoto mueve `productos.stock_actual`, y quien observa
  /// el catálogo tiene que repintar el stock aunque el evento fuera de kardex.
  static Set<String> _tablasDe(String entidad) =>
      switch (entidad.toLowerCase()) {
        EntidadesSync.producto => {Tablas.productos},
        EntidadesSync.venta => {Tablas.ventas, Tablas.detalleVentas},
        EntidadesSync.caja => {Tablas.caja},
        EntidadesSync.movimientoCaja => {Tablas.movimientosCaja, Tablas.caja},
        EntidadesSync.inventario => {Tablas.inventario, Tablas.productos},
        EntidadesSync.mesa => {Tablas.mesas},
        EntidadesSync.pedido => {Tablas.pedidos, Tablas.pedidoLineas},
        EntidadesSync.pedidoLinea => {Tablas.pedidoLineas, Tablas.pedidos},
        EntidadesSync.habitacion => {Tablas.habitaciones},
        EntidadesSync.estadiaHabitacion => {
            Tablas.estadiasHabitacion,
            Tablas.habitaciones,
          },
        _ => const <String>{},
      };

  // ----------------------------------------------------------- Producto ---

  /// Upsert de producto con LWW, **sin tocar `stock_actual` en el update**.
  Future<int> _upsertProducto(EjecutorSql tx, CambioRemoto c) async {
    final p = Producto.desdeJson(c.payload);
    if (p.id.isEmpty) return 0;

    // La marca de tiempo autoritativa es la del cambio, no la del payload:
    // es la que el servidor ordenó y con la que se compara el LWW.
    p.actualizadoUtc = c.actualizadoUtc;

    final s = Sql.upsert(
      'productos',
      p.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'codigo',
        'nombre',
        'descripcion',
        'precio_venta',
        'costo_compra',
        'precio_incluye_igv',
        'unidad_medida',
        // 'stock_actual' NO va aquí a propósito — ver cabecera del archivo.
        'controla_stock',
        'activo',
        'imagen_ruta',
        'proveedor_id',
        'tipo_descuento',
        'descuento_valor',
        'stock_minimo',
        'fecha_vencimiento',
        'lote',
        'registro_sanitario',
        'principio_activo',
        'requiere_receta',
        'personalizacion_json',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  /// Baja lógica de producto (el escritorio nunca borra filas: desactiva).
  Future<int> _bajaProducto(EjecutorSql tx, CambioRemoto c) async {
    final ts = TiempoUtc.formatoO(c.actualizadoUtc);
    final n = await tx.ejecutarContando(
      'UPDATE productos SET activo = 0, updated_utc = ? '
      'WHERE id = ? AND ? > updated_utc',
      [ts, Uuid.normalizar(c.entidadId), ts],
    );
    return n > 0 ? 1 : 0;
  }

  // -------------------------------------------------------------- Venta ---

  Future<int> _venta(EjecutorSql tx, CambioRemoto c) async {
    final v = Venta.desdeJson(c.payload);
    if (v.id.isEmpty) return 0;
    v.actualizadoUtc = c.actualizadoUtc;

    final s = Sql.upsert(
      'ventas',
      v.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'estado',
        'metodo_pago',
        'sub_total',
        'igv',
        'total',
        'monto_recibido',
        'comprobante_id',
        'updated_utc',
      ],
    );
    final n = await tx.ejecutarContando(s.sql, s.args);

    // Detalles: inmutables -> insert-if-absent. Se insertan aunque la cabecera
    // haya perdido el LWW: puede ser un reenvío en el que la cabecera ya estaba
    // y las líneas no.
    for (final d in v.detalles) {
      d.ventaId = v.id;
      if (d.origenCajaId.isEmpty) d.origenCajaId = v.origenCajaId;
      final sd = Sql.insertarSiFalta('detalle_ventas', d.aFila());
      await tx.ejecutar(sd.sql, sd.args);
    }

    return n > 0 ? 1 : 0;
  }

  /// Anulación remota: el payload es `{"id": "...", "estado": 1}` en
  /// **minúsculas**, porque el escritorio lo emite con un tipo anónimo
  /// (`new { id, estado = (int)EstadoVenta.Anulada }`) y `System.Text.Json`
  /// respeta los nombres del anónimo tal cual. Aquí se leen ambas grafías por
  /// si algún día se normaliza.
  Future<int> _estadoVenta(EjecutorSql tx, CambioRemoto c) async {
    final p = c.payload;
    final estado = (p['estado'] ?? p['Estado']) as num?;
    if (estado == null) return 0;

    final ts = TiempoUtc.formatoO(c.actualizadoUtc);
    final n = await tx.ejecutarContando(
      'UPDATE ventas SET estado = ?, updated_utc = ? '
      'WHERE id = ? AND ? > updated_utc',
      [estado.toInt(), ts, Uuid.normalizar(c.entidadId), ts],
    );
    return n > 0 ? 1 : 0;
  }

  // --------------------------------------------------------------- Caja ---

  Future<int> _caja(EjecutorSql tx, CambioRemoto c) async {
    final caja = Caja.desdeJson(c.payload);
    if (caja.id.isEmpty) return 0;
    caja.actualizadoUtc = c.actualizadoUtc;

    final s = Sql.upsert(
      'caja',
      caja.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'nombre',
        'cajero',
        'estado',
        'fecha_cierre',
        'monto_cierre',
        'diferencia',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  Future<int> _movimientoCaja(EjecutorSql tx, CambioRemoto c) async {
    final m = MovimientoCaja.desdeJson(c.payload);
    if (m.id.isEmpty) return 0;
    final s = Sql.insertarSiFalta('movimientos_caja', m.aFila());
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  // --------------------------------------------------------- Inventario ---

  /// Kardex remoto: insert-if-absent y, **solo si la fila entró de verdad**,
  /// suma su cantidad al caché `productos.stock_actual`.
  ///
  /// Aquí está la corrección del riesgo de stock con LWW: el stock se acumula
  /// por deltas idempotentes en vez de sobrescribirse con un snapshot.
  Future<int> _inventario(EjecutorSql tx, CambioRemoto c) async {
    final inv = Inventario.desdeJson(c.payload);
    if (inv.id.isEmpty) return 0;

    final s = Sql.insertarSiFalta('inventario', inv.aFila());
    final n = await tx.ejecutarContando(s.sql, s.args);
    if (n == 0) return 0; // duplicado: ya se contó, no volver a sumar

    await tx.ejecutar(
      'UPDATE productos SET stock_actual = stock_actual + ? '
      'WHERE id = ? AND controla_stock = 1',
      [inv.cantidad, inv.productoId],
    );
    return 1;
  }

  // ---------------------------------------------------- Mesas / comandas ---

  Future<int> _mesa(EjecutorSql tx, CambioRemoto c) async {
    final m = Mesa.desdeJson(c.payload);
    if (m.id.isEmpty) return 0;
    m.actualizadoUtc = c.actualizadoUtc;
    final s = Sql.upsert(
      'mesas',
      m.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'numero',
        'zona',
        'capacidad',
        'estado',
        'notas',
        'activa',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  Future<int> _pedido(EjecutorSql tx, CambioRemoto c) async {
    final p = Pedido.desdeJson(c.payload);
    if (p.id.isEmpty) return 0;
    p.actualizadoUtc = c.actualizadoUtc;

    final s = Sql.upsert(
      'pedidos',
      p.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'numero_mesa',
        'numero',
        'estado',
        'mozo',
        'comensales',
        'fecha_cierre',
        'total',
        'notas',
        'venta_id',
        'updated_utc',
      ],
    );
    final n = await tx.ejecutarContando(s.sql, s.args);

    // Las líneas de la comanda SÍ son mutables (el mozo corrige cantidades
    // antes de enviar a cocina), así que van con LWW y no insert-if-absent.
    for (final l in p.lineas) {
      l.pedidoId = p.id;
      await _upsertPedidoLinea(tx, l);
    }
    return n > 0 ? 1 : 0;
  }

  Future<int> _pedidoLinea(EjecutorSql tx, CambioRemoto c) async {
    final l = PedidoLinea.desdeJson(c.payload);
    if (l.id.isEmpty) return 0;
    l.actualizadoUtc = c.actualizadoUtc;
    return _upsertPedidoLinea(tx, l);
  }

  Future<int> _upsertPedidoLinea(EjecutorSql tx, PedidoLinea l) async {
    final s = Sql.upsert(
      'pedido_lineas',
      l.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'producto_id',
        'descripcion',
        'nota',
        'cantidad',
        'precio_unitario',
        'importe',
        'enviado_cocina',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  // --------------------------------------------------------------- Hotel ---

  Future<int> _habitacion(EjecutorSql tx, CambioRemoto c) async {
    final h = Habitacion.desdeJson(c.payload);
    if (h.id.isEmpty) return 0;
    h.actualizadoUtc = c.actualizadoUtc;
    final s = Sql.upsert(
      'habitaciones',
      h.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'numero',
        'piso',
        'tipo',
        'precio_noche',
        'precio_hora',
        'capacidad',
        'estado',
        'notas',
        'imagen_ruta',
        'comodidades',
        'activa',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  /// Estadía con LWW.
  ///
  /// `monto_consumos` viaja consolidado en la estadía porque
  /// `consumos_habitacion` NO está en el catálogo de entidades sincronizadas
  /// (ver `EntidadesSync`). Si dos recepciones cargan consumos a la vez, gana
  /// el último — asumible: a diferencia del stock, una estadía la maneja una
  /// sola recepción a la vez.
  Future<int> _estadia(EjecutorSql tx, CambioRemoto c) async {
    final e = EstadiaHabitacion.desdeJson(c.payload);
    if (e.id.isEmpty) return 0;
    e.actualizadoUtc = c.actualizadoUtc;
    final s = Sql.upsert(
      'estadias_habitacion',
      e.aFila(),
      guardaLww: true,
      columnasActualizables: const [
        'numero_habitacion',
        'huesped_nombre',
        'huesped_documento',
        'huesped_telefono',
        'personas',
        'tipo_cobro',
        'precio_unitario',
        'check_out_utc',
        'unidades',
        'monto_hospedaje',
        'monto_consumos',
        'total',
        'metodo_pago',
        'estado',
        'notas',
        'updated_utc',
      ],
    );
    return await tx.ejecutarContando(s.sql, s.args) > 0 ? 1 : 0;
  }

  // ------------------------------------------------------------ Reparación ---

  /// Reconstruye `productos.stock_actual` sumando el kardex.
  ///
  /// PRECONDICIÓN: el producto debe tener su fila de apertura en `inventario`
  /// (motivo `MotivosKardex.stockInicial`). Los productos sembrados por
  /// `PlantillasRubro` la tienen porque el repositorio la escribe al crearlos;
  /// los que llegan de una PC vieja NO, y para esos este recálculo daría un
  /// stock menor que el real. Por eso NO se llama al aplicar cambios remotos:
  /// es una herramienta de reparación explícita (botón "recalcular stock" en
  /// Inventario), no parte del camino caliente.
  ///
  /// Con [productoId] null recalcula todo el catálogo.
  Future<int> recalcularStockDesdeKardex({String? productoId}) async {
    final filtro = productoId == null ? '' : 'WHERE id = ?';
    final args = productoId == null ? const <Object?>[] : [productoId];
    return _db.ejecutarContando(
      '''
      UPDATE productos
      SET stock_actual = (
            SELECT COALESCE(SUM(i.cantidad), 0)
            FROM inventario i
            WHERE i.producto_id = productos.id
          )
      $filtro
      ''',
      args,
    );
  }

  /// True si el producto tiene fila de apertura en el kardex, o sea si
  /// [recalcularStockDesdeKardex] daría un resultado confiable para él.
  Future<bool> kardexEsCompleto(String productoId) async {
    final v = await _db.escalar(
      'SELECT COUNT(*) FROM inventario WHERE producto_id = ? AND motivo = ?',
      [productoId, MotivosKardex.stockInicial],
    );
    return ((v as num?)?.toInt() ?? 0) > 0;
  }
}
