using System.Globalization;
using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IMesaRepository"/>: mesas, pedidos
/// (comandas) y líneas del rubro restaurante. Sigue las convenciones del resto de
/// repositorios (REAL para montos, TEXT ISO-8601 para fechas UTC, escritura del
/// outbox en la misma transacción para sync futura).
/// </summary>
public sealed class MesaRepository : IMesaRepository
{
    private readonly PagoYaDbContext _db;

    public MesaRepository(PagoYaDbContext db) => _db = db;

    private static readonly DateTimeStyles Iso = DateTimeStyles.RoundtripKind;

    // ==================== MESAS ====================

    private const string SelectMesa = """
        SELECT id, numero, zona, capacidad, estado, notas, activa,
               origen_caja_id, created_utc, updated_utc
        FROM mesas
        """;

    public async Task<IReadOnlyList<Mesa>> ListarMesasAsync(bool soloActivas = true, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var sql = soloActivas ? $"{SelectMesa} WHERE activa = 1" : SelectMesa;
        sql += " ORDER BY zona COLLATE NOCASE, numero COLLATE NOCASE";
        var filas = await cx.QueryAsync<FilaMesa>(new CommandDefinition(sql, cancellationToken: ct));
        return filas.Select(f => f.AMesa()).ToList();
    }

    public async Task<Mesa?> ObtenerMesaAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaMesa>(
            new CommandDefinition($"{SelectMesa} WHERE id = @id", new { id = id.ToString() }, cancellationToken: ct));
        return fila?.AMesa();
    }

    public async Task GuardarMesaAsync(Mesa m, CancellationToken ct = default)
    {
        m.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        const string upsert = """
            INSERT INTO mesas
                (id, numero, zona, capacidad, estado, notas, activa,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Numero, @Zona, @Capacidad, @Estado, @Notas, @Activa,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero = excluded.numero, zona = excluded.zona, capacidad = excluded.capacidad,
                estado = excluded.estado, notas = excluded.notas, activa = excluded.activa,
                updated_utc = excluded.updated_utc
            """;

        await cx.ExecuteAsync(new CommandDefinition(upsert, new
        {
            Id = m.Id.ToString(), m.Numero, m.Zona, m.Capacidad, Estado = (int)m.Estado,
            m.Notas, Activa = m.Activa ? 1 : 0, m.OrigenCajaId,
            CreadoUtc = m.CreadoUtc.ToString("o"), ActualizadoUtc = m.ActualizadoUtc.ToString("o")
        }, tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "mesa", m.Id, "UPSERT", m, m.OrigenCajaId, ct);
        await tx.CommitAsync(ct);
    }

    public async Task DesactivarMesaAsync(Guid id, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE mesas SET activa = 0, updated_utc = @ahora WHERE id = @id",
            new { id = id.ToString(), ahora }, cancellationToken: ct));
    }

    public async Task CambiarEstadoMesaAsync(Guid id, EstadoMesa estado, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE mesas SET estado = @estado, updated_utc = @ahora WHERE id = @id",
            new { id = id.ToString(), estado = (int)estado, ahora }, cancellationToken: ct));
    }

    // ==================== PEDIDOS (comandas) ====================

    private const string SelectPedido = """
        SELECT id, mesa_id, numero_mesa, numero, estado, mozo, comensales,
               fecha_apertura, fecha_cierre, total, notas, venta_id,
               origen_caja_id, created_utc, updated_utc
        FROM pedidos
        """;

    public async Task<Pedido?> ObtenerPedidoAbiertoAsync(Guid mesaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaPedido>(new CommandDefinition(
            $"{SelectPedido} WHERE mesa_id = @m AND estado = 0 ORDER BY fecha_apertura DESC LIMIT 1",
            new { m = mesaId.ToString() }, cancellationToken: ct));
        if (fila is null) return null;
        var pedido = fila.APedido();
        pedido.Lineas = (await ListarLineasAsync(pedido.Id, ct)).ToList();
        return pedido;
    }

    public async Task<Pedido?> ObtenerPedidoAsync(Guid pedidoId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaPedido>(new CommandDefinition(
            $"{SelectPedido} WHERE id = @id", new { id = pedidoId.ToString() }, cancellationToken: ct));
        if (fila is null) return null;
        var pedido = fila.APedido();
        pedido.Lineas = (await ListarLineasAsync(pedido.Id, ct)).ToList();
        return pedido;
    }

    public async Task GuardarPedidoAsync(Pedido p, CancellationToken ct = default)
    {
        p.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        const string upsert = """
            INSERT INTO pedidos
                (id, mesa_id, numero_mesa, numero, estado, mozo, comensales,
                 fecha_apertura, fecha_cierre, total, notas, venta_id,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @MesaId, @NumeroMesa, @Numero, @Estado, @Mozo, @Comensales,
                 @FechaApertura, @FechaCierre, @Total, @Notas, @VentaId,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                estado = excluded.estado, mozo = excluded.mozo, comensales = excluded.comensales,
                fecha_cierre = excluded.fecha_cierre, total = excluded.total, notas = excluded.notas,
                venta_id = excluded.venta_id, updated_utc = excluded.updated_utc
            """;

        await cx.ExecuteAsync(new CommandDefinition(upsert, new
        {
            Id = p.Id.ToString(), MesaId = p.MesaId.ToString(), p.NumeroMesa, p.Numero,
            Estado = (int)p.Estado, p.Mozo, p.Comensales,
            FechaApertura = p.FechaApertura.ToString("o"),
            FechaCierre = p.FechaCierre?.ToString("o"),
            Total = (double)p.Total, p.Notas, VentaId = p.VentaId?.ToString(),
            p.OrigenCajaId, CreadoUtc = p.CreadoUtc.ToString("o"), ActualizadoUtc = p.ActualizadoUtc.ToString("o")
        }, tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "pedido", p.Id, "UPSERT", p, p.OrigenCajaId, ct);
        await tx.CommitAsync(ct);
    }

    // ==================== LÍNEAS ====================

    private const string SelectLinea = """
        SELECT id, pedido_id, producto_id, descripcion, nota, cantidad, precio_unitario,
               importe, enviado_cocina, origen_caja_id, created_utc, updated_utc
        FROM pedido_lineas
        """;

    public async Task<IReadOnlyList<PedidoLinea>> ListarLineasAsync(Guid pedidoId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaLinea>(new CommandDefinition(
            $"{SelectLinea} WHERE pedido_id = @p ORDER BY created_utc",
            new { p = pedidoId.ToString() }, cancellationToken: ct));
        return filas.Select(f => f.ALinea()).ToList();
    }

    public async Task AgregarLineaAsync(PedidoLinea l, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        const string insert = """
            INSERT INTO pedido_lineas
                (id, pedido_id, producto_id, descripcion, nota, cantidad, precio_unitario,
                 importe, enviado_cocina, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @PedidoId, @ProductoId, @Descripcion, @Nota, @Cantidad, @PrecioUnitario,
                 @Importe, @EnviadoCocina, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            """;
        await cx.ExecuteAsync(new CommandDefinition(insert, new
        {
            Id = l.Id.ToString(), PedidoId = l.PedidoId.ToString(),
            ProductoId = l.ProductoId == Guid.Empty ? null : l.ProductoId.ToString(),
            l.Descripcion, l.Nota, Cantidad = (double)l.Cantidad, PrecioUnitario = (double)l.PrecioUnitario,
            Importe = (double)l.Importe, EnviadoCocina = l.EnviadoCocina ? 1 : 0, l.OrigenCajaId,
            CreadoUtc = l.CreadoUtc.ToString("o"), ActualizadoUtc = l.ActualizadoUtc.ToString("o")
        }, cancellationToken: ct));
    }

    public async Task QuitarLineaAsync(Guid lineaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "DELETE FROM pedido_lineas WHERE id = @id", new { id = lineaId.ToString() }, cancellationToken: ct));
    }

    public async Task MarcarLineasEnviadasAsync(Guid pedidoId, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE pedido_lineas SET enviado_cocina = 1, updated_utc = @ahora WHERE pedido_id = @p AND enviado_cocina = 0",
            new { p = pedidoId.ToString(), ahora }, cancellationToken: ct));
    }

    public async Task<decimal> TotalPedidoAsync(Guid pedidoId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var total = await cx.ExecuteScalarAsync<double?>(new CommandDefinition(
            "SELECT COALESCE(SUM(importe), 0) FROM pedido_lineas WHERE pedido_id = @p",
            new { p = pedidoId.ToString() }, cancellationToken: ct));
        return (decimal)(total ?? 0);
    }

    // ==================== FILAS (mapeo snake_case) ====================

    private sealed class FilaMesa
    {
        public string id { get; set; } = "";
        public string numero { get; set; } = "";
        public string? zona { get; set; }
        public long capacidad { get; set; }
        public long estado { get; set; }
        public string? notas { get; set; }
        public long activa { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public Mesa AMesa() => new()
        {
            Id = Guid.Parse(id), Numero = numero, Zona = zona, Capacidad = (int)capacidad,
            Estado = (EstadoMesa)estado, Notas = notas, Activa = activa != 0,
            OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }

    private sealed class FilaPedido
    {
        public string id { get; set; } = "";
        public string mesa_id { get; set; } = "";
        public string numero_mesa { get; set; } = "";
        public string numero { get; set; } = "";
        public long estado { get; set; }
        public string mozo { get; set; } = "";
        public long comensales { get; set; }
        public string fecha_apertura { get; set; } = "";
        public string? fecha_cierre { get; set; }
        public double total { get; set; }
        public string? notas { get; set; }
        public string? venta_id { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public Pedido APedido() => new()
        {
            Id = Guid.Parse(id), MesaId = Guid.Parse(mesa_id), NumeroMesa = numero_mesa, Numero = numero,
            Estado = (EstadoPedido)estado, Mozo = mozo, Comensales = (int)comensales,
            FechaApertura = DateTime.Parse(fecha_apertura, null, Iso),
            FechaCierre = string.IsNullOrEmpty(fecha_cierre) ? null : DateTime.Parse(fecha_cierre, null, Iso),
            Total = (decimal)total, Notas = notas,
            VentaId = string.IsNullOrEmpty(venta_id) ? null : Guid.Parse(venta_id),
            OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }

    private sealed class FilaLinea
    {
        public string id { get; set; } = "";
        public string pedido_id { get; set; } = "";
        public string? producto_id { get; set; }
        public string descripcion { get; set; } = "";
        public string? nota { get; set; }
        public double cantidad { get; set; }
        public double precio_unitario { get; set; }
        public double importe { get; set; }
        public long enviado_cocina { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public PedidoLinea ALinea() => new()
        {
            Id = Guid.Parse(id), PedidoId = Guid.Parse(pedido_id),
            ProductoId = string.IsNullOrEmpty(producto_id) ? Guid.Empty : Guid.Parse(producto_id),
            Descripcion = descripcion, Nota = nota, Cantidad = (decimal)cantidad,
            PrecioUnitario = (decimal)precio_unitario, Importe = (decimal)importe,
            EnviadoCocina = enviado_cocina != 0, OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }
}
