using Dapper;
using Microsoft.Data.Sqlite;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="ICajaRepository"/>.
///
/// Tablas 'caja' y 'movimientos_caja'. Reglas:
///   * Solo puede existir UNA caja Abierta a la vez (se valida en apertura).
///   * Abrir caja inserta la sesión + un movimiento AperturaFondo, atómico.
///   * Cerrar caja registra arqueo (monto contado + diferencia).
/// </summary>
public sealed class CajaRepository : ICajaRepository
{
    private readonly PagoYaDbContext _db;

    public CajaRepository(PagoYaDbContext db) => _db = db;

    private const string SelectCaja = """
        SELECT id, nombre, cajero, estado, monto_apertura, fecha_apertura,
               fecha_cierre, monto_cierre, diferencia, origen_caja_id,
               created_utc, updated_utc
        FROM caja
        """;

    /// <inheritdoc />
    public async Task<Caja?> ObtenerCajaAbiertaAsync(CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaCaja>(new CommandDefinition(
            $"{SelectCaja} WHERE estado = @estado ORDER BY fecha_apertura DESC LIMIT 1",
            new { estado = (int)EstadoCaja.Abierta }, cancellationToken: ct));
        return fila?.ACaja();
    }

    /// <inheritdoc />
    public async Task<Caja?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaCaja>(new CommandDefinition(
            $"{SelectCaja} WHERE id = @id",
            new { id = id.ToString() }, cancellationToken: ct));
        return fila?.ACaja();
    }

    /// <inheritdoc />
    public async Task AbrirCajaAsync(Caja caja, CancellationToken ct = default)
    {
        caja.Estado = EstadoCaja.Abierta;
        caja.ActualizadoUtc = DateTime.UtcNow;

        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);

        try
        {
            // Invariante: no puede haber otra caja abierta.
            var abiertas = await cx.ExecuteScalarAsync<long>(new CommandDefinition(
                "SELECT COUNT(*) FROM caja WHERE estado = @estado",
                new { estado = (int)EstadoCaja.Abierta }, tx, cancellationToken: ct));
            if (abiertas > 0)
                throw new InvalidOperationException("Ya existe una caja abierta. Ciérrela antes de abrir otra.");

            await cx.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO caja
                    (id, nombre, cajero, estado, monto_apertura, fecha_apertura,
                     fecha_cierre, monto_cierre, diferencia, origen_caja_id,
                     created_utc, updated_utc)
                VALUES
                    (@Id, @Nombre, @Cajero, @Estado, @MontoApertura, @FechaApertura,
                     NULL, NULL, NULL, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
                """,
                new
                {
                    Id = caja.Id.ToString(),
                    caja.Nombre,
                    caja.Cajero,
                    Estado = (int)caja.Estado,
                    MontoApertura = (double)caja.MontoApertura,
                    FechaApertura = caja.FechaApertura.ToString("o"),
                    caja.OrigenCajaId,
                    CreadoUtc = caja.CreadoUtc.ToString("o"),
                    ActualizadoUtc = caja.ActualizadoUtc.ToString("o")
                }, tx, cancellationToken: ct));

            // Movimiento de fondo de apertura.
            var aperturaUtc = DateTime.UtcNow.ToString("o");
            await cx.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO movimientos_caja
                    (id, caja_id, tipo, monto, concepto, fecha_hora, origen_caja_id,
                     created_utc, updated_utc)
                VALUES
                    (@id, @caja_id, @tipo, @monto, @concepto, @fecha_hora, @origen_caja_id,
                     @created_utc, @updated_utc)
                """,
                new
                {
                    id = Guid.NewGuid().ToString(),
                    caja_id = caja.Id.ToString(),
                    tipo = (int)TipoMovimientoCaja.AperturaFondo,
                    monto = (double)caja.MontoApertura,
                    concepto = "Fondo inicial",
                    fecha_hora = caja.FechaApertura.ToString("o"),
                    origen_caja_id = caja.OrigenCajaId,
                    created_utc = aperturaUtc,
                    updated_utc = aperturaUtc
                }, tx, cancellationToken: ct));

            await OutboxHelper.RegistrarAsync(cx, tx, "caja", caja.Id, "INSERT",
                caja, caja.OrigenCajaId, ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task CerrarCajaAsync(Caja caja, CancellationToken ct = default)
    {
        caja.Estado = EstadoCaja.Cerrada;
        caja.FechaCierre ??= DateTime.Now;
        caja.ActualizadoUtc = DateTime.UtcNow;

        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);

        try
        {
            await cx.ExecuteAsync(new CommandDefinition(
                """
                UPDATE caja SET
                    estado       = @Estado,
                    fecha_cierre = @FechaCierre,
                    monto_cierre = @MontoCierre,
                    diferencia   = @Diferencia,
                    updated_utc  = @ActualizadoUtc
                WHERE id = @Id
                """,
                new
                {
                    Id = caja.Id.ToString(),
                    Estado = (int)caja.Estado,
                    FechaCierre = caja.FechaCierre?.ToString("o"),
                    MontoCierre = caja.MontoCierre is null ? (double?)null : (double)caja.MontoCierre.Value,
                    Diferencia = caja.Diferencia is null ? (double?)null : (double)caja.Diferencia.Value,
                    ActualizadoUtc = caja.ActualizadoUtc.ToString("o")
                }, tx, cancellationToken: ct));

            await OutboxHelper.RegistrarAsync(cx, tx, "caja", caja.Id, "UPDATE",
                caja, caja.OrigenCajaId, ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task RegistrarMovimientoAsync(MovimientoCaja movimiento, CancellationToken ct = default)
    {
        movimiento.ActualizadoUtc = DateTime.UtcNow;

        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);

        try
        {
            await cx.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO movimientos_caja
                    (id, caja_id, tipo, monto, concepto, fecha_hora, origen_caja_id,
                     created_utc, updated_utc)
                VALUES
                    (@Id, @CajaId, @Tipo, @Monto, @Concepto, @FechaHora, @OrigenCajaId,
                     @CreadoUtc, @ActualizadoUtc)
                """,
                new
                {
                    Id = movimiento.Id.ToString(),
                    CajaId = movimiento.CajaId.ToString(),
                    Tipo = (int)movimiento.Tipo,
                    Monto = (double)movimiento.Monto,
                    movimiento.Concepto,
                    FechaHora = movimiento.FechaHora.ToString("o"),
                    movimiento.OrigenCajaId,
                    CreadoUtc = movimiento.CreadoUtc.ToString("o"),
                    ActualizadoUtc = movimiento.ActualizadoUtc.ToString("o")
                }, tx, cancellationToken: ct));

            await OutboxHelper.RegistrarAsync(cx, tx, "movimiento_caja", movimiento.Id, "INSERT",
                movimiento, movimiento.OrigenCajaId, ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<MovimientoCaja>> ListarMovimientosAsync(Guid cajaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaMovimiento>(new CommandDefinition(
            """
            SELECT id, caja_id, tipo, monto, concepto, fecha_hora, origen_caja_id,
                   created_utc, updated_utc
            FROM movimientos_caja WHERE caja_id = @cajaId ORDER BY fecha_hora
            """,
            new { cajaId = cajaId.ToString() }, cancellationToken: ct));
        return filas.Select(f => f.AMovimiento()).ToList();
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<Caja>> ListarSesionesAsync(DateOnly desde, DateOnly hasta, CancellationToken ct = default)
    {
        if (hasta < desde) (desde, hasta) = (hasta, desde);
        var d = desde.ToString("yyyy-MM-dd");
        var h = hasta.ToString("yyyy-MM-dd");

        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaCaja>(new CommandDefinition(
            $"{SelectCaja} WHERE substr(fecha_apertura, 1, 10) BETWEEN @d AND @h ORDER BY fecha_apertura DESC",
            new { d, h }, cancellationToken: ct));
        return filas.Select(f => f.ACaja()).ToList();
    }
}

/// <summary>Fila cruda de 'caja'.</summary>
internal sealed class FilaCaja
{
    public string id { get; set; } = "";
    public string nombre { get; set; } = "";
    public string cajero { get; set; } = "";
    public long estado { get; set; }
    public double monto_apertura { get; set; }
    public string fecha_apertura { get; set; } = "";
    public string? fecha_cierre { get; set; }
    public double? monto_cierre { get; set; }
    public double? diferencia { get; set; }
    public string origen_caja_id { get; set; } = "";
    public string created_utc { get; set; } = "";
    public string updated_utc { get; set; } = "";

    public Caja ACaja() => new()
    {
        Id = Guid.Parse(id),
        Nombre = nombre,
        Cajero = cajero,
        Estado = (EstadoCaja)estado,
        MontoApertura = (decimal)monto_apertura,
        FechaApertura = DateTime.Parse(fecha_apertura, null, System.Globalization.DateTimeStyles.RoundtripKind),
        FechaCierre = fecha_cierre is null ? null : DateTime.Parse(fecha_cierre, null, System.Globalization.DateTimeStyles.RoundtripKind),
        MontoCierre = monto_cierre is null ? null : (decimal)monto_cierre.Value,
        Diferencia = diferencia is null ? null : (decimal)diferencia.Value,
        OrigenCajaId = origen_caja_id,
        CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
        ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
    };
}

/// <summary>Fila cruda de 'movimientos_caja'.</summary>
internal sealed class FilaMovimiento
{
    public string id { get; set; } = "";
    public string caja_id { get; set; } = "";
    public long tipo { get; set; }
    public double monto { get; set; }
    public string concepto { get; set; } = "";
    public string fecha_hora { get; set; } = "";
    public string origen_caja_id { get; set; } = "";
    public string created_utc { get; set; } = "";
    public string updated_utc { get; set; } = "";

    public MovimientoCaja AMovimiento() => new()
    {
        Id = Guid.Parse(id),
        CajaId = Guid.Parse(caja_id),
        Tipo = (TipoMovimientoCaja)tipo,
        Monto = (decimal)monto,
        Concepto = concepto,
        FechaHora = DateTime.Parse(fecha_hora, null, System.Globalization.DateTimeStyles.RoundtripKind),
        OrigenCajaId = origen_caja_id,
        CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
        ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
    };
}
