// PagoYa Móvil — datos/repositorios/venta_repositorio.dart
//
// PORT de `VentaRepository.cs`. Es el repositorio más crítico del POS.
//
// `registrar` es ATÓMICO: dentro de UNA sola transacción
//   (1) asigna el correlativo con prefijo de dispositivo (si falta),
//   (2) inserta la cabecera `ventas`,
//   (3) inserta las líneas `detalle_ventas`,
//   (4) por cada línea de un producto que controla stock, descuenta el caché
//       e inserta el movimiento negativo en `inventario` (+ su outbox),
//   (5) registra el evento `venta` en `outbox_sync`.
//
// Si algo falla se hace ROLLBACK y la caja nunca queda a medias: no hay venta
// sin kardex, ni kardex sin venta, ni venta sin evento de sincronización.
// Esa es la regla de negocio, no una optimización.

library;

import '../../dominio/inventario.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/uuid.dart';
import '../../dominio/venta.dart';
import '../../dominio/enums.dart';
import '../configuracion_dispositivo.dart';
import '../contratos.dart';
import '../correlativos.dart';
import '../ejecutor_sql.dart';
import '../notificador_tablas.dart';
import '../outbox.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';
import 'producto_repositorio.dart';

final class VentaRepositorio extends BaseRepositorio
    implements RepositorioVentas {
  static const String _selectVenta = '''
      SELECT id, numero, caja_id, fecha_hora, metodo_pago, estado, sub_total,
             igv, total, monto_recibido, comprobante_id, origen_caja_id,
             created_utc, updated_utc
      FROM ventas
      ''';

  static const String _selectDetalle = '''
      SELECT id, venta_id, producto_id, descripcion_producto, cantidad,
             precio_unitario, descuento, importe, origen_caja_id,
             created_utc, updated_utc
      FROM detalle_ventas
      ''';

  final Correlativos _correlativos;

  VentaRepositorio(EjecutorSql db, [ConfiguracionDispositivo? config])
      : _correlativos = Correlativos(db, config),
        super(db, config);

  @override
  Future<Venta?> obtenerPorId(String id) async {
    final idn = Uuid.normalizar(id);
    final cab = await db.consultar('$_selectVenta WHERE id = ?', [idn]);
    if (cab.isEmpty) return null;

    final venta = Venta.desdeFila(cab.first);
    final det =
        await db.consultar('$_selectDetalle WHERE venta_id = ?', [idn]);
    venta.detalles = det.map(DetalleVenta.desdeFila).toList();
    return venta;
  }

  @override
  Future<List<Venta>> listarPorCaja(String cajaId) async {
    final filas = await db.consultar(
      '$_selectVenta WHERE caja_id = ? ORDER BY fecha_hora',
      [Uuid.normalizar(cajaId)],
    );
    return filas.map(Venta.desdeFila).toList(growable: false);
  }

  /// Ventas de un día (hora LOCAL del negocio, igual que los reportes de la PC:
  /// `substr(fecha_hora, 1, 10)`).
  Future<List<Venta>> listarPorDia(DateTime dia) async {
    final filas = await db.consultar(
      '$_selectVenta WHERE substr(fecha_hora, 1, 10) = ? ORDER BY fecha_hora',
      [TiempoUtc.formatoFecha(dia)],
    );
    return filas.map(Venta.desdeFila).toList(growable: false);
  }

  /// Registra la venta completa de forma atómica. Ver la cabecera del archivo.
  ///
  /// Si [venta] no trae `numero`, se le asigna uno con el prefijo de este
  /// dispositivo DENTRO de la transacción: si la venta hace rollback, el
  /// correlativo no se consume y la numeración no deja huecos.
  Future<Venta> registrar(Venta venta) async {
    if (venta.detalles.isEmpty) {
      throw const ErrorDatos(
          'No se puede registrar una venta sin líneas de detalle.');
    }

    // Estampa `origen_caja_id` desde la fuente única antes de escribir nada:
    // ese valor tiene que coincidir con el `?origen=` del pull para que el
    // filtro de eco del backend funcione.
    await estampar(venta);

    await db.transaccion((tx) async {
      if (venta.numero.trim().isEmpty) {
        venta.numero = await _correlativos.siguienteVenta(tx);
      }

      // (2) Cabecera.
      final sc = Sql.insertar('ventas', venta.aFila());
      await tx.ejecutar(sc.sql, sc.args);

      // (3) y (4) Líneas + kardex.
      for (final d in venta.detalles) {
        d.ventaId = venta.id;
        if (d.origenCajaId.isEmpty) d.origenCajaId = venta.origenCajaId;

        final sd = Sql.insertar('detalle_ventas', d.aFila());
        await tx.ejecutar(sd.sql, sd.args);

        // Solo se mueve stock de productos que lo controlan y que existen.
        final controla = await tx.escalar(
          'SELECT controla_stock FROM productos WHERE id = ?',
          [d.productoId],
        );
        if (controla == null || (controla as num).toInt() != 1) continue;

        final ahora = DateTime.now().toUtc();
        await tx.ejecutar(
          'UPDATE productos SET stock_actual = stock_actual - ?, '
          'updated_utc = ? WHERE id = ?',
          [d.cantidad, TiempoUtc.formatoO(ahora), d.productoId],
        );
        final resultante = ((await tx.escalar(
                    'SELECT stock_actual FROM productos WHERE id = ?',
                    [d.productoId])) as num?)
                ?.toDouble() ??
            0;

        await ProductoRepositorio.registrarKardexEnTransaccion(
          tx,
          productoId: d.productoId,
          cantidad: -d.cantidad, // salida
          stockResultante: resultante,
          motivo: MotivosKardex.venta(venta.numero),
          referenciaId: venta.id,
          origenCajaId: venta.origenCajaId,
          ahora: ahora,
        );
      }

      // (5) Outbox de la venta, en la MISMA transacción.
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.venta,
        entidadId: venta.id,
        operacion: OperacionesSync.insert,
        payload: venta.aJson(),
        origenCajaId: venta.origenCajaId,
      );
    });

    return venta;
  }

  /// Anula una venta: devuelve el stock al kardex y marca la cabecera.
  ///
  /// La venta NO se borra (trazabilidad): cambia de estado a `anulada` y la
  /// reversa queda como movimiento positivo en el kardex, así el histórico
  /// explica por qué el stock subió.
  Future<void> anular(String id) async {
    final idn = Uuid.normalizar(id);
    final origenDispositivo = await origenPropio();

    await db.transaccion((tx) async {
      final cab = await tx.consultar(
        'SELECT numero, estado, origen_caja_id FROM ventas WHERE id = ?',
        [idn],
      );
      if (cab.isEmpty) throw ErrorDatos('No existe la venta $idn');
      if (((cab.first['estado'] as num?)?.toInt() ?? 0) ==
          EstadoVenta.anulada.valor) {
        return; // ya anulada: idempotente, no duplicar la reversa
      }

      final numero = (cab.first['numero'] ?? '').toString();
      // El escritorio deja `origen_caja_id` vacío en la reversa, lo que rompe
      // el filtro de eco: ese evento vuelve en el siguiente pull. Aquí se
      // estampa SIEMPRE el origen de este dispositivo (fuente única), porque
      // quien anula es este dispositivo, aunque la venta original venga de la
      // PC. Si la venta no tiene origen, se cae al de la venta como respaldo.
      final origenVenta = (cab.first['origen_caja_id'] ?? '').toString();
      final origen =
          origenDispositivo.isNotEmpty ? origenDispositivo : origenVenta;

      final detalles = await tx.consultar(
        'SELECT producto_id, cantidad FROM detalle_ventas WHERE venta_id = ?',
        [idn],
      );

      final ahora = DateTime.now().toUtc();
      final ts = TiempoUtc.formatoO(ahora);

      for (final d in detalles) {
        final productoId = (d['producto_id'] ?? '').toString();
        final cantidad = (d['cantidad'] as num?)?.toDouble() ?? 0;

        final controla = await tx.escalar(
          'SELECT controla_stock FROM productos WHERE id = ?',
          [productoId],
        );
        if (controla == null || (controla as num).toInt() != 1) continue;

        await tx.ejecutar(
          'UPDATE productos SET stock_actual = stock_actual + ?, '
          'updated_utc = ? WHERE id = ?',
          [cantidad, ts, productoId],
        );
        final resultante = ((await tx.escalar(
                    'SELECT stock_actual FROM productos WHERE id = ?',
                    [productoId])) as num?)
                ?.toDouble() ??
            0;

        await ProductoRepositorio.registrarKardexEnTransaccion(
          tx,
          productoId: productoId,
          cantidad: cantidad, // entrada (reversa)
          stockResultante: resultante,
          motivo: MotivosKardex.anulacion(numero),
          referenciaId: idn,
          origenCajaId: origen,
          ahora: ahora,
        );
      }

      await tx.ejecutar(
        'UPDATE ventas SET estado = ?, updated_utc = ? WHERE id = ?',
        [EstadoVenta.anulada.valor, ts, idn],
      );

      // Payload de anulación con claves en MINÚSCULAS: es el tipo anónimo
      // `new { id, estado }` que emite el escritorio y que su
      // `AplicarEstadoVentaAsync` lee con `LeerEntero(payload, "estado")`.
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.venta,
        entidadId: idn,
        operacion: OperacionesSync.update,
        payload: {'id': idn, 'estado': EstadoVenta.anulada.valor},
        origenCajaId: origen,
        ahora: ahora,
      );
    });
  }
}
