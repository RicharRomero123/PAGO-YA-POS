using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IReportesRepository"/>.
///
/// Filtra por DÍA LOCAL: 'fecha_hora' se persiste como ISO-8601 local con
/// desfase (ej. "2026-08-25T13:47:00.12-05:00"), por lo que sus primeros 10
/// caracteres son la fecha local ("2026-08-25"). Comparar por
/// <c>substr(fecha_hora,1,10)</c> es correcto y estable ante cambios de huso,
/// a diferencia de rangos sobre timestamps con desfase.
///
/// Las métricas de dinero (total, ticket, ranking) consideran SOLO ventas
/// <see cref="EstadoVenta.Completada"/>; las anuladas se muestran en la lista
/// de "últimas ventas" por trazabilidad, pero no suman.
/// </summary>
public sealed class ReportesRepository : IReportesRepository
{
    private const int MaxUltimasVentas = 20;
    private const int MaxTopProductos = 8;

    private readonly PagoYaDbContext _db;

    public ReportesRepository(PagoYaDbContext db) => _db = db;

    /// <inheritdoc />
    public async Task<ReporteDia> ObtenerReporteDelDiaAsync(DateOnly fecha, CancellationToken ct = default)
    {
        var fechaIso = fecha.ToString("yyyy-MM-dd");
        await using var cx = await _db.CrearConexionAsync(ct);

        // 1) Métricas del día (solo completadas). COALESCE evita null en día vacío.
        var m = await cx.QuerySingleAsync<FilaMetricas>(new CommandDefinition(
            """
            SELECT
                COALESCE(SUM(total), 0)              AS total_vendido,
                COUNT(*)                             AS cantidad_ventas,
                COALESCE(SUM(
                    (SELECT COALESCE(SUM(d.cantidad), 0)
                     FROM detalle_ventas d WHERE d.venta_id = v.id)
                ), 0)                                AS productos_vendidos
            FROM ventas v
            WHERE substr(v.fecha_hora, 1, 10) = @fecha AND v.estado = @completada
            """,
            new { fecha = fechaIso, completada = (int)EstadoVenta.Completada },
            cancellationToken: ct));

        // 2) Últimas ventas (incluye anuladas), más recientes primero.
        var ventas = (await cx.QueryAsync<FilaResumenVenta>(new CommandDefinition(
            """
            SELECT id, numero, fecha_hora, metodo_pago, total, estado
            FROM ventas
            WHERE substr(fecha_hora, 1, 10) = @fecha
            ORDER BY fecha_hora DESC
            LIMIT @limite
            """,
            new { fecha = fechaIso, limite = MaxUltimasVentas },
            cancellationToken: ct))).Select(f => f.A()).ToList();

        // 3) Ranking de productos (solo ventas completadas del día).
        var top = (await cx.QueryAsync<FilaRanking>(new CommandDefinition(
            """
            SELECT d.descripcion_producto AS nombre,
                   SUM(d.cantidad)        AS unidades,
                   SUM(d.importe)         AS total
            FROM detalle_ventas d
            JOIN ventas v ON v.id = d.venta_id
            WHERE substr(v.fecha_hora, 1, 10) = @fecha AND v.estado = @completada
            GROUP BY d.descripcion_producto
            ORDER BY unidades DESC, total DESC
            LIMIT @limite
            """,
            new { fecha = fechaIso, completada = (int)EstadoVenta.Completada, limite = MaxTopProductos },
            cancellationToken: ct))).Select(f => f.A()).ToList();

        // 4) Desglose por método de pago (conciliación de caja; solo completadas).
        var porMetodo = (await cx.QueryAsync<FilaPorMetodo>(new CommandDefinition(
            """
            SELECT metodo_pago AS metodo, SUM(total) AS total, COUNT(*) AS cantidad
            FROM ventas
            WHERE substr(fecha_hora, 1, 10) = @fecha AND estado = @completada
            GROUP BY metodo_pago
            ORDER BY total DESC
            """,
            new { fecha = fechaIso, completada = (int)EstadoVenta.Completada },
            cancellationToken: ct))).Select(f => f.A()).ToList();

        var ticket = m.cantidad_ventas > 0
            ? (decimal)m.total_vendido / m.cantidad_ventas
            : 0m;

        return new ReporteDia(
            fecha,
            (decimal)m.total_vendido,
            m.cantidad_ventas,
            ticket,
            (decimal)m.productos_vendidos,
            ventas, top, porMetodo);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<VentaResumen>> ListarVentasRangoAsync(DateOnly desde, DateOnly hasta, CancellationToken ct = default)
    {
        // Normaliza el orden por si vienen invertidas.
        if (hasta < desde) (desde, hasta) = (hasta, desde);
        var d = desde.ToString("yyyy-MM-dd");
        var h = hasta.ToString("yyyy-MM-dd");

        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaResumenVenta>(new CommandDefinition(
            """
            SELECT id, numero, fecha_hora, metodo_pago, total, estado
            FROM ventas
            WHERE substr(fecha_hora, 1, 10) BETWEEN @desde AND @hasta
            ORDER BY fecha_hora DESC
            """,
            new { desde = d, hasta = h }, cancellationToken: ct));
        return filas.Select(f => f.A()).ToList();
    }

    // --- Filas crudas (Dapper) ---

    private sealed class FilaMetricas
    {
        public double total_vendido { get; set; }
        public int cantidad_ventas { get; set; }
        public double productos_vendidos { get; set; }
    }

    private sealed class FilaResumenVenta
    {
        public string id { get; set; } = "";
        public string numero { get; set; } = "";
        public string fecha_hora { get; set; } = "";
        public long metodo_pago { get; set; }
        public double total { get; set; }
        public long estado { get; set; }

        public VentaResumen A() => new(
            Guid.Parse(id),
            numero,
            DateTime.Parse(fecha_hora, null, System.Globalization.DateTimeStyles.RoundtripKind),
            (MetodoPago)metodo_pago,
            (decimal)total,
            (EstadoVenta)estado);
    }

    private sealed class FilaRanking
    {
        public string nombre { get; set; } = "";
        public double unidades { get; set; }
        public double total { get; set; }

        public ProductoRanking A() => new(nombre, (decimal)unidades, (decimal)total);
    }

    private sealed class FilaPorMetodo
    {
        public long metodo { get; set; }
        public double total { get; set; }
        public int cantidad { get; set; }

        public TotalPorMetodo A() => new((MetodoPago)metodo, (decimal)total, cantidad);
    }
}
