// PagoYa Móvil — datos/repositorios/producto_repositorio.dart
//
// PORT de `ProductoRepository.cs`. Misma forma que `IProductoRepository`.
//
// Cada escritura va en una transacción junto con su fila de `outbox_sync`.

library;

import '../../dominio/inventario.dart';
import '../../dominio/producto.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/uuid.dart';
import '../contratos.dart';
import '../ejecutor_sql.dart';
import '../notificador_tablas.dart';
import '../outbox.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

/// Repositorio del catálogo de productos y de los movimientos de stock.
final class ProductoRepositorio extends BaseRepositorio
    implements RepositorioProductos {
  static const String _select = '''
      SELECT id, codigo, nombre, descripcion, precio_venta, costo_compra,
             precio_incluye_igv, unidad_medida, stock_actual, controla_stock,
             activo, imagen_ruta, proveedor_id, tipo_descuento, descuento_valor,
             stock_minimo, fecha_vencimiento, lote, registro_sanitario,
             principio_activo, requiere_receta, personalizacion_json,
             origen_caja_id, created_utc, updated_utc
      FROM productos
      ''';

  /// Columnas que se pisan en un guardado local (todas menos la PK y
  /// `created_utc`, que es inmutable).
  static const List<String> _actualizables = [
    'codigo',
    'nombre',
    'descripcion',
    'precio_venta',
    'costo_compra',
    'precio_incluye_igv',
    'unidad_medida',
    'stock_actual',
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
  ];

  ProductoRepositorio(super.db, [super.config]);

  @override
  Future<Producto?> obtenerPorId(String id) async {
    final filas =
        await db.consultar('$_select WHERE id = ?', [Uuid.normalizar(id)]);
    return filas.isEmpty ? null : Producto.desdeFila(filas.first);
  }

  /// Búsqueda por código de barras exacto (el escáner). Solo activos.
  @override
  Future<Producto?> obtenerPorCodigo(String codigo) async {
    final filas =
        await db.consultar('$_select WHERE codigo = ? AND activo = 1', [codigo]);
    return filas.isEmpty ? null : Producto.desdeFila(filas.first);
  }

  /// Catálogo activo, opcionalmente filtrado.
  ///
  /// El filtro incluye `principio_activo` para poder buscar genéricos por DCI
  /// en el rubro farmacia, igual que el escritorio.
  @override
  Future<List<Producto>> buscar([String? filtro]) async {
    final f = filtro?.trim() ?? '';
    final filas = f.isEmpty
        ? await db.consultar(
            '$_select WHERE activo = 1 ORDER BY nombre COLLATE NOCASE')
        : await db.consultar(
            '$_select WHERE activo = 1 AND (nombre LIKE ? OR codigo LIKE ? '
            'OR principio_activo LIKE ?) ORDER BY nombre COLLATE NOCASE',
            ['%$f%', '%$f%', '%$f%'],
          );
    return filas.map(Producto.desdeFila).toList(growable: false);
  }

  /// Categorías distintas presentes en el catálogo activo.
  ///
  /// OJO: la categoría vive en la columna `descripcion`, no en una columna
  /// propia — el `esquema.sql` compartido no tiene `categoria` y el escritorio
  /// reutiliza `descripcion` para eso (`SeedDemo`: "categoría reutiliza
  /// 'descripcion'"; `ProductoItemViewModel.Desde`: `Categoria = p.Descripcion`).
  /// Cambiarlo exigiría migrar el esquema en la PC y en el móvil a la vez.
  ///
  /// Se descartan las vacías porque el escritorio muestra "General" en ese caso
  /// y una cadena vacía en el selector no le dice nada a nadie.
  @override
  Future<List<String>> listarCategorias() async {
    final filas = await db.consultar(
      '''
      SELECT DISTINCT descripcion AS categoria
      FROM productos
      WHERE activo = 1 AND descripcion IS NOT NULL AND trim(descripcion) <> ''
      ORDER BY descripcion COLLATE NOCASE
      ''',
    );
    return filas
        .map((f) => (f['categoria'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
  }

  /// Observa el catálogo para que la pantalla de inventario se refresque sola.
  ///
  /// Escucha también `inventario`: una venta hecha desde la pantalla de cobro
  /// mueve el stock sin tocar la fila de `productos` por esta vía, y el
  /// inventario tiene que repintarlo igual.
  @override
  Stream<List<Producto>> observarCatalogo() =>
      observar({Tablas.productos, Tablas.inventario}, () => buscar());

  /// Productos con stock por debajo del umbral (alertas de reposición).
  Future<List<Producto>> stockBajo() async {
    final filas = await db.consultar(
      '$_select WHERE activo = 1 AND controla_stock = 1 AND stock_minimo > 0 '
      'AND stock_actual <= stock_minimo ORDER BY nombre COLLATE NOCASE',
    );
    return filas.map(Producto.desdeFila).toList(growable: false);
  }

  /// Productos vencidos o por vencer dentro de [dias] (rubro farmacia).
  Future<List<Producto>> porVencer({int dias = 30, DateTime? hoy}) async {
    final limite = (hoy ?? DateTime.now()).add(Duration(days: dias));
    final filas = await db.consultar(
      '$_select WHERE activo = 1 AND fecha_vencimiento IS NOT NULL '
      'AND fecha_vencimiento <= ? ORDER BY fecha_vencimiento',
      [TiempoUtc.formatoFecha(limite)],
    );
    return filas.map(Producto.desdeFila).toList(growable: false);
  }

  /// Guarda (inserta o actualiza) un producto + su evento de outbox, atómico.
  ///
  /// La operación del outbox es `UPSERT` porque es lo que registra el
  /// escritorio, y `OutboxStore` trata cualquier operación distinta de
  /// `DELETE` como upsert.
  @override
  Future<void> guardar(Producto producto) async {
    await estampar(producto);
    await db.transaccion((tx) async {
      final s = Sql.upsert('productos', producto.aFila(),
          columnasActualizables: _actualizables);
      await tx.ejecutar(s.sql, s.args);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.producto,
        entidadId: producto.id,
        operacion: OperacionesSync.upsert,
        payload: producto.aJson(),
        origenCajaId: producto.origenCajaId,
      );
    });
    notificar({Tablas.productos});
  }

  /// Crea un producto **con su fila de apertura en el kardex**.
  ///
  /// Es la forma correcta de sembrar catálogo (onboarding por rubro, alta
  /// manual con stock inicial): sin la fila "Stock inicial" el kardex no
  /// explica de dónde salió el stock y `recalcularStockDesdeKardex` daría 0.
  /// El escritorio hoy NO escribe esa fila; el móvil sí, y la fila extra es
  /// inofensiva para la PC (la inserta en su kardex y ya).
  Future<void> crearConStockInicial(Producto producto) async {
    final stockInicial = producto.stockActual;
    await estampar(producto);

    await db.transaccion((tx) async {
      final s = Sql.upsert('productos', producto.aFila(),
          columnasActualizables: _actualizables);
      await tx.ejecutar(s.sql, s.args);
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.producto,
        entidadId: producto.id,
        operacion: OperacionesSync.upsert,
        payload: producto.aJson(),
        origenCajaId: producto.origenCajaId,
      );

      if (producto.controlaStock && stockInicial != 0) {
        await _registrarKardex(
          tx,
          productoId: producto.id,
          cantidad: stockInicial,
          stockResultante: stockInicial,
          motivo: MotivosKardex.stockInicial,
          origenCajaId: producto.origenCajaId,
        );
      }
    });
    notificar({Tablas.productos, Tablas.inventario});
  }

  /// Ajuste de stock: escribe el kardex, actualiza el caché y emite el evento.
  ///
  /// [cantidad] es un DELTA con signo (+ entrada, − salida). Se devuelve el
  /// stock resultante para que la UI lo muestre sin releer.
  Future<double> ajustarStock({
    required String productoId,
    required double cantidad,
    required String motivo,
    String? referenciaId,
    String? origenCajaId,
  }) async {
    // Fuente única de `origen_caja_id`: si el llamador no lo fuerza, se usa el
    // del dispositivo (el mismo que `flutter-sync` manda como `?origen=`).
    final origen = origenCajaId ?? await origenPropio();
    final resultado = await db.transaccion((tx) async {
      final controla = await tx.escalar(
        'SELECT controla_stock FROM productos WHERE id = ?',
        [productoId],
      );
      if (controla == null) {
        throw ErrorDatos('No existe el producto $productoId');
      }
      if (((controla as num).toInt()) != 1) {
        // Producto que no controla stock (servicios): no hay kardex que mover.
        return 0.0;
      }

      final ahora = DateTime.now().toUtc();
      await tx.ejecutar(
        'UPDATE productos SET stock_actual = stock_actual + ?, updated_utc = ? '
        'WHERE id = ?',
        [cantidad, TiempoUtc.formatoO(ahora), productoId],
      );
      final resultante =
          ((await tx.escalar('SELECT stock_actual FROM productos WHERE id = ?',
                  [productoId])) as num?)
                  ?.toDouble() ??
              0;

      await _registrarKardex(
        tx,
        productoId: productoId,
        cantidad: cantidad,
        stockResultante: resultante,
        motivo: motivo,
        referenciaId: referenciaId,
        origenCajaId: origen,
        ahora: ahora,
      );
      return resultante;
    });
    notificar({Tablas.productos, Tablas.inventario});
    return resultado;
  }

  /// Baja lógica (el POS nunca borra: desactiva, para no romper el historial
  /// de ventas que apunta al producto por FK).
  @override
  Future<void> desactivar(String id) async {
    final idn = Uuid.normalizar(id);
    final ahora = TiempoUtc.formatoO(DateTime.now());
    final origen = await origenPropio();
    await db.transaccion((tx) async {
      await tx.ejecutar(
        'UPDATE productos SET activo = 0, updated_utc = ? WHERE id = ?',
        [ahora, idn],
      );
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.producto,
        entidadId: idn,
        operacion: OperacionesSync.delete,
        // Payload mínimo, con la clave en MINÚSCULAS: el escritorio lo emite
        // como tipo anónimo `new { id }` y así lo espera al leerlo.
        payload: {'id': idn},
        origenCajaId: origen,
      );
    });
    notificar({Tablas.productos});
  }

  /// Kardex de un producto, del más reciente al más antiguo.
  Future<List<Inventario>> kardex(String productoId, {int limite = 200}) async {
    final filas = await db.consultar(
      '''
      SELECT id, producto_id, cantidad, stock_resultante, motivo, referencia_id,
             fecha_hora, origen_caja_id, created_utc, updated_utc
      FROM inventario WHERE producto_id = ?
      ORDER BY fecha_hora DESC LIMIT ?
      ''',
      [Uuid.normalizar(productoId), limite],
    );
    return filas.map(Inventario.desdeFila).toList(growable: false);
  }

  /// Inserta una fila de kardex + su evento de outbox, dentro de [tx].
  ///
  /// Público a nivel de librería porque `VentaRepositorio` lo reusa: la venta
  /// debe escribir su kardex en SU MISMA transacción, no en una aparte.
  static Future<Inventario> _registrarKardex(
    EjecutorSql tx, {
    required String productoId,
    required double cantidad,
    required double stockResultante,
    required String motivo,
    String? referenciaId,
    String origenCajaId = '',
    DateTime? ahora,
  }) async {
    final t = ahora ?? DateTime.now().toUtc();
    final inv = Inventario(
      productoId: productoId,
      cantidad: cantidad,
      stockResultante: stockResultante,
      motivo: motivo,
      referenciaId: referenciaId,
      fechaHora: t,
      origenCajaId: origenCajaId,
      creadoUtc: t,
      actualizadoUtc: t,
    );
    final s = Sql.insertar('inventario', inv.aFila());
    await tx.ejecutar(s.sql, s.args);

    await OutboxHelper.registrar(
      tx,
      entidad: EntidadesSync.inventario,
      entidadId: inv.id,
      operacion: OperacionesSync.insert,
      payload: inv.aJson(),
      origenCajaId: origenCajaId,
      ahora: t,
    );
    return inv;
  }

  /// Punto de entrada del kardex para otros repositorios de esta librería.
  static Future<Inventario> registrarKardexEnTransaccion(
    EjecutorSql tx, {
    required String productoId,
    required double cantidad,
    required double stockResultante,
    required String motivo,
    String? referenciaId,
    String origenCajaId = '',
    DateTime? ahora,
  }) =>
      _registrarKardex(
        tx,
        productoId: productoId,
        cantidad: cantidad,
        stockResultante: stockResultante,
        motivo: motivo,
        referenciaId: referenciaId,
        origenCajaId: origenCajaId,
        ahora: ahora,
      );
}
