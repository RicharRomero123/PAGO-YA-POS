// PagoYa Móvil — datos/repositorios/mesa_repositorio.dart
//
// PORT de `MesaRepository.cs` / `IMesaRepository`: mesas, comandas y líneas.
//
// Es el caso de uso estrella del móvil (el mozo toma el pedido en el celular),
// así que las tres entidades — `mesa`, `pedido`, `pedido_linea` — SÍ emiten
// evento de outbox: están en el catálogo cerrado de `backend-seats` y el
// backend ya las acepta. El escritorio todavía no las aplica al recibirlas
// (docs/MOBILE-ARQUITECTURA.md §6.3); eso no impide emitirlas ahora, y así el
// día que la PC se amplíe el historial ya está en la nube.

library;

import '../../dominio/dinero.dart';
import '../../dominio/enums.dart';
import '../../dominio/restaurante.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/uuid.dart';
import '../correlativos.dart';
import '../configuracion_dispositivo.dart';
import '../ejecutor_sql.dart';
import '../outbox.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

final class MesaRepositorio extends BaseRepositorio {
  static const String _selectMesa = '''
      SELECT id, numero, zona, capacidad, estado, notas, activa,
             origen_caja_id, created_utc, updated_utc
      FROM mesas
      ''';

  static const String _selectPedido = '''
      SELECT id, mesa_id, numero_mesa, numero, estado, mozo, comensales,
             fecha_apertura, fecha_cierre, total, notas, venta_id,
             origen_caja_id, created_utc, updated_utc
      FROM pedidos
      ''';

  static const String _selectLinea = '''
      SELECT id, pedido_id, producto_id, descripcion, nota, cantidad,
             precio_unitario, importe, enviado_cocina, origen_caja_id,
             created_utc, updated_utc
      FROM pedido_lineas
      ''';

  final Correlativos _correlativos;

  MesaRepositorio(EjecutorSql db, [ConfiguracionDispositivo? config])
      : _correlativos = Correlativos(db, config),
        super(db, config);

  // ---------------------------------------------------------------- Mesas ---

  Future<List<Mesa>> listarMesas({bool soloActivas = true}) async {
    final filas = await db.consultar(
      soloActivas
          ? '$_selectMesa WHERE activa = 1 ORDER BY zona, numero'
          : '$_selectMesa ORDER BY zona, numero',
    );
    return filas.map(Mesa.desdeFila).toList(growable: false);
  }

  Future<Mesa?> obtenerMesa(String id) async {
    final filas =
        await db.consultar('$_selectMesa WHERE id = ?', [Uuid.normalizar(id)]);
    return filas.isEmpty ? null : Mesa.desdeFila(filas.first);
  }

  Future<void> guardarMesa(Mesa mesa) async {
    await estampar(mesa);
    await db.transaccion((tx) async {
      final s = Sql.upsert('mesas', mesa.aFila(), columnasActualizables: const [
        'numero',
        'zona',
        'capacidad',
        'estado',
        'notas',
        'activa',
        'updated_utc',
      ]);
      await tx.ejecutar(s.sql, s.args);
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.mesa,
        entidadId: mesa.id,
        operacion: OperacionesSync.upsert,
        payload: mesa.aJson(),
        origenCajaId: mesa.origenCajaId,
      );
    });
  }

  Future<void> desactivarMesa(String id) async {
    final mesa = await obtenerMesa(id);
    if (mesa == null) return;
    mesa.activa = false;
    await guardarMesa(mesa);
  }

  /// Cambia solo el estado del mapa del salón (libre / ocupada / por cobrar).
  Future<void> cambiarEstadoMesa(String id, EstadoMesa estado) async {
    final mesa = await obtenerMesa(id);
    if (mesa == null) return;
    mesa.estado = estado;
    await guardarMesa(mesa);
  }

  // -------------------------------------------------------------- Pedidos ---

  /// Comanda abierta de una mesa (null si la mesa está libre).
  Future<Pedido?> obtenerPedidoAbierto(String mesaId) async {
    final filas = await db.consultar(
      '$_selectPedido WHERE mesa_id = ? AND estado = ? '
      'ORDER BY fecha_apertura DESC LIMIT 1',
      [Uuid.normalizar(mesaId), EstadoPedido.abierta.valor],
    );
    if (filas.isEmpty) return null;
    final p = Pedido.desdeFila(filas.first);
    p.lineas = await listarLineas(p.id);
    return p;
  }

  Future<Pedido?> obtenerPedido(String pedidoId) async {
    final filas = await db
        .consultar('$_selectPedido WHERE id = ?', [Uuid.normalizar(pedidoId)]);
    if (filas.isEmpty) return null;
    final p = Pedido.desdeFila(filas.first);
    p.lineas = await listarLineas(p.id);
    return p;
  }

  /// Abre una comanda nueva y marca la mesa como ocupada, atómico.
  ///
  /// El correlativo del pedido se consume dentro de la misma transacción, por
  /// la misma razón que en las ventas: si la apertura falla, no queda un hueco
  /// en la numeración.
  Future<Pedido> abrirPedido(Pedido pedido) async {
    await estampar(pedido);

    await db.transaccion((tx) async {
      if (pedido.numero.trim().isEmpty) {
        pedido.numero = await _correlativos.siguientePedido(tx);
      }
      final s = Sql.insertar('pedidos', pedido.aFila());
      await tx.ejecutar(s.sql, s.args);

      await tx.ejecutar(
        'UPDATE mesas SET estado = ?, updated_utc = ? WHERE id = ?',
        [
          EstadoMesa.ocupada.valor,
          TiempoUtc.formatoO(pedido.actualizadoUtc),
          pedido.mesaId,
        ],
      );

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.pedido,
        entidadId: pedido.id,
        operacion: OperacionesSync.insert,
        payload: pedido.aJson(),
        origenCajaId: pedido.origenCajaId,
      );
    });

    return pedido;
  }

  /// Guarda la cabecera del pedido (estado, total, mozo, venta asociada).
  Future<void> guardarPedido(Pedido pedido) async {
    await estampar(pedido);
    await db.transaccion((tx) async {
      final s =
          Sql.upsert('pedidos', pedido.aFila(), columnasActualizables: const [
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
      ]);
      await tx.ejecutar(s.sql, s.args);
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.pedido,
        entidadId: pedido.id,
        operacion: OperacionesSync.upsert,
        payload: pedido.aJson(),
        origenCajaId: pedido.origenCajaId,
      );
    });
  }

  // --------------------------------------------------------------- Líneas ---

  Future<List<PedidoLinea>> listarLineas(String pedidoId) async {
    final filas = await db.consultar(
      '$_selectLinea WHERE pedido_id = ? ORDER BY created_utc',
      [Uuid.normalizar(pedidoId)],
    );
    return filas.map(PedidoLinea.desdeFila).toList();
  }

  /// Agrega una línea a la comanda y actualiza el total, atómico.
  ///
  /// El total se recalcula SUMANDO desde la tabla y no incrementando el caché:
  /// dos mozos agregando platos a la misma mesa desde dos celulares llegarían
  /// al mismo total.
  Future<PedidoLinea> agregarLinea(PedidoLinea linea) async {
    linea.recalcularImporte();
    await estampar(linea);

    await db.transaccion((tx) async {
      final s = Sql.insertar('pedido_lineas', linea.aFila());
      await tx.ejecutar(s.sql, s.args);
      await _refrescarTotal(tx, linea.pedidoId, linea.origenCajaId);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.pedidoLinea,
        entidadId: linea.id,
        operacion: OperacionesSync.insert,
        payload: linea.aJson(),
        origenCajaId: linea.origenCajaId,
      );
    });

    return linea;
  }

  /// Quita una línea (solo tiene sentido si aún no fue a cocina).
  Future<void> quitarLinea(String lineaId) async {
    final idn = Uuid.normalizar(lineaId);
    final origen = await origenPropio();

    await db.transaccion((tx) async {
      final filas =
          await tx.consultar('$_selectLinea WHERE id = ?', [idn]);
      if (filas.isEmpty) return;
      final linea = PedidoLinea.desdeFila(filas.first);

      await tx.ejecutar('DELETE FROM pedido_lineas WHERE id = ?', [idn]);
      await _refrescarTotal(tx, linea.pedidoId, origen);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.pedidoLinea,
        entidadId: idn,
        operacion: OperacionesSync.delete,
        // Claves en minúsculas, como el payload de baja del escritorio.
        payload: {'id': idn, 'pedido_id': linea.pedidoId},
        origenCajaId: origen,
      );
    });
  }

  /// Marca las líneas pendientes como enviadas a cocina (tras imprimir la
  /// comanda). No emite un evento por línea: emite el pedido completo, que es
  /// lo que la cocina necesita ver.
  Future<void> marcarLineasEnviadas(String pedidoId) async {
    final idn = Uuid.normalizar(pedidoId);
    final ts = TiempoUtc.formatoO(DateTime.now());
    await db.ejecutar(
      'UPDATE pedido_lineas SET enviado_cocina = 1, updated_utc = ? '
      'WHERE pedido_id = ? AND enviado_cocina = 0',
      [ts, idn],
    );
    final pedido = await obtenerPedido(idn);
    if (pedido != null) await guardarPedido(pedido);
  }

  /// Total de la comanda sumando las líneas (fuente de verdad).
  Future<Dinero> totalPedido(String pedidoId) async {
    final filas = await db.consultar(
      'SELECT importe FROM pedido_lineas WHERE pedido_id = ?',
      [Uuid.normalizar(pedidoId)],
    );
    return Dinero.sumar(
      filas.map((f) => Dinero.desdeDb(f['importe'] as num?)),
    );
  }

  /// Recalcula y persiste `pedidos.total` dentro de [tx].
  Future<void> _refrescarTotal(
      EjecutorSql tx, String pedidoId, String origen) async {
    final filas = await tx.consultar(
      'SELECT importe FROM pedido_lineas WHERE pedido_id = ?',
      [pedidoId],
    );
    final total =
        Dinero.sumar(filas.map((f) => Dinero.desdeDb(f['importe'] as num?)));
    await tx.ejecutar(
      'UPDATE pedidos SET total = ?, updated_utc = ? WHERE id = ?',
      [total.aDb(), TiempoUtc.formatoO(DateTime.now()), pedidoId],
    );
  }
}
