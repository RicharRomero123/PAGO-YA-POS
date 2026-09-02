using PagoYa.Core.Enums;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Consultas de agregación para los reportes locales del POS (tier Base).
/// Trabaja sobre las mismas tablas 'ventas' / 'detalle_ventas' que llena
/// <see cref="IVentaRepository"/>, pero de solo-lectura y orientado a métricas.
/// Implementa: desktop-dev. Los reportes móviles/nube requieren flag cloud_sync.
/// </summary>
public interface IReportesRepository
{
    /// <summary>
    /// Calcula el reporte de un día (fecha local del POS): métricas del día,
    /// últimas ventas, ranking de productos y desglose por método de pago.
    /// </summary>
    Task<ReporteDia> ObtenerReporteDelDiaAsync(DateOnly fecha, CancellationToken ct = default);

    /// <summary>
    /// Lista TODAS las ventas (incluye anuladas) en el rango de fechas locales
    /// [desde, hasta] inclusive, más recientes primero. Para exportar a Excel.
    /// </summary>
    Task<IReadOnlyList<VentaResumen>> ListarVentasRangoAsync(DateOnly desde, DateOnly hasta, CancellationToken ct = default);
}

/// <summary>Reporte consolidado de una jornada. Los montos son en soles (PEN).</summary>
public sealed record ReporteDia(
    DateOnly Fecha,
    decimal TotalVendido,
    int CantidadVentas,
    decimal TicketPromedio,
    decimal ProductosVendidos,
    IReadOnlyList<VentaResumen> UltimasVentas,
    IReadOnlyList<ProductoRanking> MasVendidos,
    IReadOnlyList<TotalPorMetodo> PorMetodo)
{
    /// <summary>Reporte vacío (día sin ventas), evita null en la UI.</summary>
    public static ReporteDia Vacio(DateOnly fecha) =>
        new(fecha, 0m, 0, 0m, 0m,
            Array.Empty<VentaResumen>(), Array.Empty<ProductoRanking>(), Array.Empty<TotalPorMetodo>());
}

/// <summary>Fila de "últimas ventas": incluye anuladas (para trazabilidad).</summary>
public sealed record VentaResumen(
    Guid Id, string Numero, DateTime FechaHora, MetodoPago Metodo, decimal Total, EstadoVenta Estado);

/// <summary>Producto en el ranking de más vendidos (solo ventas completadas).</summary>
public sealed record ProductoRanking(string Nombre, decimal Unidades, decimal Total);

/// <summary>Total y cantidad de ventas por método de pago (conciliación de caja).</summary>
public sealed record TotalPorMetodo(MetodoPago Metodo, decimal Total, int Cantidad);
