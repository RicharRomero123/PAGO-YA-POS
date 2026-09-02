// PagoYa Móvil — datos/repositorios/reportes_repositorio.dart
//
// PORT de `ReportesRepository.cs` / `IReportesRepository`.
//
// Alimenta la pantalla de "ventas del día", que es lo primero que mira el dueño
// al cerrar la bodega. Solo lectura: no escribe nada y por tanto no toca el
// outbox.
//
// DOS REGLAS QUE NO SON OBVIAS
// ----------------------------
// 1. **El día es LOCAL, no UTC.** Se filtra con `substr(fecha_hora, 1, 10)`,
//    igual que el escritorio, porque `ventas.fecha_hora` se guarda en hora local
//    del negocio. Filtrar por UTC en Perú (UTC−5) movería las ventas de después
//    de las 7 p. m. al día siguiente y el arqueo no cuadraría con el cajón.
// 2. **Las anuladas cuentan para el listado pero no para los totales.** El dueño
//    tiene que VER que hubo una anulación (trazabilidad), pero esa venta no
//    entró a la caja. Mezclarlas es la forma más rápida de que el reporte no
//    cuadre con el efectivo contado.

library;

import '../../dominio/dinero.dart';
import '../../dominio/enums.dart';
import '../../dominio/tiempo.dart';
import '../contratos.dart';
import '../ejecutor_sql.dart';

/// Consultas de agregación para la pantalla de reportes.
final class ReportesRepositorio implements RepositorioReportes {
  /// Cuántas ventas recientes se muestran en el resumen del día.
  static const int _maxUltimasVentas = 20;

  /// Cuántos productos entran en el ranking de más vendidos.
  static const int _maxRanking = 10;

  final EjecutorSql _db;

  const ReportesRepositorio(this._db);

  @override
  Future<ReporteDia> obtenerReporteDelDia(DateTime fecha) async {
    final dia = TiempoUtc.formatoFecha(fecha);
    final completada = EstadoVenta.completada.valor;

    // Totales del día: solo ventas completadas.
    final agregado = await _db.consultar(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS suma
      FROM ventas
      WHERE substr(fecha_hora, 1, 10) = ? AND estado = ?
      ''',
      [dia, completada],
    );

    final cantidadVentas =
        agregado.isEmpty ? 0 : (agregado.first['n'] as num?)?.toInt() ?? 0;
    final totalVendido = agregado.isEmpty
        ? Dinero.cero
        : Dinero.desdeDb(agregado.first['suma'] as num?);

    if (cantidadVentas == 0) {
      // Día sin ventas: se devuelve el vacío canónico en vez de un reporte con
      // ceros a medias, para que la UI tenga un solo caso que pintar.
      return ReporteDia.vacio(_soloFecha(fecha));
    }

    // Ticket promedio en céntimos enteros: dividir los doubles del SUM daría
    // un valor que no coincide con la suma de los tickets impresos.
    final ticketPromedio = Dinero.enCentimos(
      divRedondeadoMitadPar(totalVendido.centimos, cantidadVentas),
    );

    final unidades = await _db.escalar(
      '''
      SELECT COALESCE(SUM(d.cantidad), 0)
      FROM detalle_ventas d
      JOIN ventas v ON v.id = d.venta_id
      WHERE substr(v.fecha_hora, 1, 10) = ? AND v.estado = ?
      ''',
      [dia, completada],
    );

    return ReporteDia(
      fecha: _soloFecha(fecha),
      totalVendido: totalVendido,
      cantidadVentas: cantidadVentas,
      ticketPromedio: ticketPromedio,
      productosVendidos: (unidades as num?)?.toDouble() ?? 0,
      ultimasVentas: await _ultimasVentas(dia),
      masVendidos: await _masVendidos(dia, completada),
      porMetodo: await _porMetodo(dia, completada),
    );
  }

  @override
  Future<List<VentaResumen>> listarVentasRango(
      DateTime desde, DateTime hasta) async {
    var d = desde;
    var h = hasta;
    if (h.isBefore(d)) {
      final t = d;
      d = h;
      h = t;
    }

    final filas = await _db.consultar(
      '''
      SELECT id, numero, fecha_hora, metodo_pago, total, estado
      FROM ventas
      WHERE substr(fecha_hora, 1, 10) BETWEEN ? AND ?
      ORDER BY fecha_hora DESC
      ''',
      [TiempoUtc.formatoFecha(d), TiempoUtc.formatoFecha(h)],
    );
    return filas.map(_aResumen).toList(growable: false);
  }

  /// Últimas ventas del día, **incluidas las anuladas** (trazabilidad).
  Future<List<VentaResumen>> _ultimasVentas(String dia) async {
    final filas = await _db.consultar(
      '''
      SELECT id, numero, fecha_hora, metodo_pago, total, estado
      FROM ventas
      WHERE substr(fecha_hora, 1, 10) = ?
      ORDER BY fecha_hora DESC
      LIMIT ?
      ''',
      [dia, _maxUltimasVentas],
    );
    return filas.map(_aResumen).toList(growable: false);
  }

  /// Ranking de más vendidos, solo de ventas completadas.
  ///
  /// Se agrupa por `descripcion_producto` (el nombre CONGELADO en la línea) y
  /// no por `producto_id`: si el dueño renombra un producto, el histórico debe
  /// seguir mostrando con qué nombre se vendió, que es lo que él recuerda.
  Future<List<ProductoRanking>> _masVendidos(String dia, int completada) async {
    final filas = await _db.consultar(
      '''
      SELECT d.descripcion_producto AS nombre,
             COALESCE(SUM(d.cantidad), 0) AS unidades,
             COALESCE(SUM(d.importe), 0)  AS total
      FROM detalle_ventas d
      JOIN ventas v ON v.id = d.venta_id
      WHERE substr(v.fecha_hora, 1, 10) = ? AND v.estado = ?
      GROUP BY d.descripcion_producto
      ORDER BY unidades DESC, total DESC
      LIMIT ?
      ''',
      [dia, completada, _maxRanking],
    );

    return filas
        .map((f) => ProductoRanking(
              nombre: (f['nombre'] ?? '').toString(),
              unidades: (f['unidades'] as num?)?.toDouble() ?? 0,
              total: Dinero.desdeDb(f['total'] as num?),
            ))
        .toList(growable: false);
  }

  /// Desglose por método de pago, para conciliar contra el arqueo.
  ///
  /// Es la consulta que responde "el cajón dice S/ 340 pero vendí S/ 890":
  /// la diferencia está en Yape y tarjeta, que no entran al efectivo.
  Future<List<TotalPorMetodo>> _porMetodo(String dia, int completada) async {
    final filas = await _db.consultar(
      '''
      SELECT metodo_pago,
             COALESCE(SUM(total), 0) AS suma,
             COUNT(*) AS n
      FROM ventas
      WHERE substr(fecha_hora, 1, 10) = ? AND estado = ?
      GROUP BY metodo_pago
      ORDER BY suma DESC
      ''',
      [dia, completada],
    );

    return filas
        .map((f) => TotalPorMetodo(
              metodo: MetodoPago.desde((f['metodo_pago'] as num?)?.toInt()),
              total: Dinero.desdeDb(f['suma'] as num?),
              cantidad: (f['n'] as num?)?.toInt() ?? 0,
            ))
        .toList(growable: false);
  }

  static VentaResumen _aResumen(Map<String, Object?> f) => VentaResumen(
        id: (f['id'] ?? '').toString(),
        numero: (f['numero'] ?? '').toString(),
        fechaHora:
            TiempoUtc.parsear((f['fecha_hora'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
        metodo: MetodoPago.desde((f['metodo_pago'] as num?)?.toInt()),
        total: Dinero.desdeDb(f['total'] as num?),
        estado: EstadoVenta.desde((f['estado'] as num?)?.toInt()),
      );

  /// Fecha local a medianoche, que es la convención de `DateOnly` en Dart
  /// según §4.1.
  static DateTime _soloFecha(DateTime f) => DateTime(f.year, f.month, f.day);
}
