using Dapper;
using Microsoft.Data.Sqlite;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IVentaRepository"/>.
///
/// <see cref="RegistrarAsync"/> es ATÓMICO: dentro de una única transacción
/// (1) inserta la cabecera 'ventas', (2) inserta las líneas 'detalle_ventas',
/// (3) por cada línea de un producto que controla stock inserta un movimiento
/// negativo en 'inventario' y actualiza el cache 'productos.stock_actual',
/// (4) registra el evento en 'outbox_sync'. Si algo falla, se hace rollback y
/// la caja nunca queda en estado inconsistente (regla de negocio clave).
/// </summary>
public sealed class VentaRepository : IVentaRepository
{
    private readonly PagoYaDbContext _db;

    public VentaRepository(PagoYaDbContext db) => _db = db;

    /// <inheritdoc />
    public async Task<Venta?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);

        var cab = await cx.QuerySingleOrDefaultAsync<FilaVenta>(new CommandDefinition(
            """
            SELECT id, numero, caja_id, fecha_hora, metodo_pago, estado, sub_total,
                   igv, total, monto_recibido, comprobante_id, origen_caja_id,
                   created_utc, updated_utc
            FROM ventas WHERE id = @id
            """,
            new { id = id.ToString() }, cancellationToken: ct));

        if (cab is null) return null;

        var detalles = await cx.QueryAsync<FilaDetalle>(new CommandDefinition(
            """
            SELECT id, venta_id, producto_id, descripcion_producto, cantidad,
                   precio_unitario, descuento, importe, origen_caja_id,
                   created_utc, updated_utc
            FROM detalle_ventas WHERE venta_id = @id
            """,
            new { id = id.ToString() }, cancellationToken: ct));

        var venta = cab.AVenta();
        venta.Detalles = detalles.Select(d => d.ADetalle()).ToList();
        return venta;
    }

    /// <inheritdoc />
    public async Task RegistrarAsync(Venta venta, CancellationToken ct = default)
    {
        if (venta.Detalles.Count == 0)
            throw new InvalidOperationException("No se puede registrar una venta sin líneas de detalle.");

        venta.ActualizadoUtc = DateTime.UtcNow;

        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);

        try
        {
            // 1) Cabecera
            await cx.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO ventas
                    (id, numero, caja_id, fecha_hora, metodo_pago, estado, sub_total,
                     igv, total, monto_recibido, comprobante_id, origen_caja_id,
                     created_utc, updated_utc)
                VALUES
                    (@Id, @Numero, @CajaId, @FechaHora, @MetodoPago, @Estado, @SubTotal,
                     @Igv, @Total, @MontoRecibido, @ComprobanteId, @OrigenCajaId,
                     @CreadoUtc, @ActualizadoUtc)
                """,
                new
                {
                    Id = venta.Id.ToString(),
                    venta.Numero,
                    CajaId = venta.CajaId.ToString(),
                    FechaHora = venta.FechaHora.ToString("o"),
                    MetodoPago = (int)venta.MetodoPago,
                    Estado = (int)venta.Estado,
                    SubTotal = (double)venta.SubTotal,
                    Igv = (double)venta.Igv,
                    Total = (double)venta.Total,
                    MontoRecibido = venta.MontoRecibido is null ? (double?)null : (double)venta.MontoRecibido.Value,
                    ComprobanteId = venta.ComprobanteId?.ToString(),
                    venta.OrigenCajaId,
                    CreadoUtc = venta.CreadoUtc.ToString("o"),
                    ActualizadoUtc = venta.ActualizadoUtc.ToString("o")
                }, tx, cancellationToken: ct));

            // 2) Detalles + 3) inventario (kardex) + cache de stock
            foreach (var d in venta.Detalles)
            {
                d.VentaId = venta.Id;
                if (d.OrigenCajaId.Length == 0) d.OrigenCajaId = venta.OrigenCajaId;

                await cx.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO detalle_ventas
                        (id, venta_id, producto_id, descripcion_producto, cantidad,
                         precio_unitario, descuento, importe, origen_caja_id,
                         created_utc, updated_utc)
                    VALUES
                        (@Id, @VentaId, @ProductoId, @DescripcionProducto, @Cantidad,
                         @PrecioUnitario, @Descuento, @Importe, @OrigenCajaId,
                         @CreadoUtc, @ActualizadoUtc)
                    """,
                    new
                    {
                        Id = d.Id.ToString(),
                        VentaId = d.VentaId.ToString(),
                        ProductoId = d.ProductoId.ToString(),
                        d.DescripcionProducto,
                        Cantidad = (double)d.Cantidad,
                        PrecioUnitario = (double)d.PrecioUnitario,
                        Descuento = (double)d.Descuento,
                        Importe = (double)d.Importe,
                        d.OrigenCajaId,
                        CreadoUtc = d.CreadoUtc.ToString("o"),
                        ActualizadoUtc = d.ActualizadoUtc.ToString("o")
                    }, tx, cancellationToken: ct));

                // Solo movemos stock de productos que lo controlan y existen.
                var controla = await cx.QuerySingleOrDefaultAsync<long?>(new CommandDefinition(
                    "SELECT controla_stock FROM productos WHERE id = @id",
                    new { id = d.ProductoId.ToString() }, tx, cancellationToken: ct));

                if (controla is 1)
                {
                    var ahoraDt = DateTime.UtcNow;
                    var ahora = ahoraDt.ToString("o");

                    // Descontar cache y devolver el stock resultante (kardex snapshot).
                    var stockResultante = await cx.ExecuteScalarAsync<double>(new CommandDefinition(
                        """
                        UPDATE productos
                        SET stock_actual = stock_actual - @cant, updated_utc = @ahora
                        WHERE id = @id
                        RETURNING stock_actual
                        """,
                        new { cant = (double)d.Cantidad, ahora, id = d.ProductoId.ToString() },
                        tx, cancellationToken: ct));

                    var invId = Guid.NewGuid();
                    await cx.ExecuteAsync(new CommandDefinition(
                        """
                        INSERT INTO inventario
                            (id, producto_id, cantidad, stock_resultante, motivo,
                             referencia_id, fecha_hora, origen_caja_id, created_utc, updated_utc)
                        VALUES
                            (@id, @producto_id, @cantidad, @stock_resultante, @motivo,
                             @referencia_id, @fecha_hora, @origen_caja_id, @created_utc, @updated_utc)
                        """,
                        new
                        {
                            id = invId.ToString(),
                            producto_id = d.ProductoId.ToString(),
                            cantidad = -(double)d.Cantidad,          // salida
                            stock_resultante = stockResultante,
                            motivo = $"Venta {venta.Numero}",
                            referencia_id = venta.Id.ToString(),
                            fecha_hora = ahora,
                            origen_caja_id = venta.OrigenCajaId,
                            created_utc = ahora,
                            updated_utc = ahora
                        }, tx, cancellationToken: ct));

                    // Kardex al outbox (inmutable): consolida stock entre cajas.
                    await OutboxHelper.RegistrarAsync(cx, tx, "inventario", invId, "INSERT",
                        new Inventario
                        {
                            Id = invId,
                            ProductoId = d.ProductoId,
                            Cantidad = -d.Cantidad,
                            StockResultante = (decimal)stockResultante,
                            Motivo = $"Venta {venta.Numero}",
                            ReferenciaId = venta.Id,
                            FechaHora = ahoraDt,
                            OrigenCajaId = venta.OrigenCajaId,
                            CreadoUtc = ahoraDt,
                            ActualizadoUtc = ahoraDt
                        }, venta.OrigenCajaId, ct);
                }
            }

            // 4) Outbox (misma transacción)
            await OutboxHelper.RegistrarAsync(cx, tx, "venta", venta.Id, "INSERT",
                venta, venta.OrigenCajaId, ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<Venta>> ListarPorCajaAsync(Guid cajaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaVenta>(new CommandDefinition(
            """
            SELECT id, numero, caja_id, fecha_hora, metodo_pago, estado, sub_total,
                   igv, total, monto_recibido, comprobante_id, origen_caja_id,
                   created_utc, updated_utc
            FROM ventas WHERE caja_id = @cajaId ORDER BY fecha_hora
            """,
            new { cajaId = cajaId.ToString() }, cancellationToken: ct));
        return filas.Select(f => f.AVenta()).ToList();
    }

    /// <inheritdoc />
    public async Task AnularAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);

        try
        {
            var ahoraDt = DateTime.UtcNow;
            var ahora = ahoraDt.ToString("o");

            // Reversa de inventario: por cada detalle, devolver stock.
            var detalles = await cx.QueryAsync<FilaDetalle>(new CommandDefinition(
                "SELECT producto_id, cantidad, descripcion_producto FROM detalle_ventas WHERE venta_id = @id",
                new { id = id.ToString() }, tx, cancellationToken: ct));

            var numero = await cx.QuerySingleOrDefaultAsync<string?>(new CommandDefinition(
                "SELECT numero FROM ventas WHERE id = @id",
                new { id = id.ToString() }, tx, cancellationToken: ct)) ?? "";

            foreach (var d in detalles)
            {
                var controla = await cx.QuerySingleOrDefaultAsync<long?>(new CommandDefinition(
                    "SELECT controla_stock FROM productos WHERE id = @id",
                    new { id = d.producto_id }, tx, cancellationToken: ct));
                if (controla is not 1) continue;

                var stockResultante = await cx.ExecuteScalarAsync<double>(new CommandDefinition(
                    """
                    UPDATE productos
                    SET stock_actual = stock_actual + @cant, updated_utc = @ahora
                    WHERE id = @id
                    RETURNING stock_actual
                    """,
                    new { cant = d.cantidad, ahora, id = d.producto_id }, tx, cancellationToken: ct));

                var invId = Guid.NewGuid();
                await cx.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO inventario
                        (id, producto_id, cantidad, stock_resultante, motivo,
                         referencia_id, fecha_hora, origen_caja_id, created_utc, updated_utc)
                    VALUES
                        (@id, @producto_id, @cantidad, @stock_resultante, @motivo,
                         @referencia_id, @fecha_hora, '', @created_utc, @updated_utc)
                    """,
                    new
                    {
                        id = invId.ToString(),
                        producto_id = d.producto_id,
                        cantidad = d.cantidad,                 // entrada (reversa)
                        stock_resultante = stockResultante,
                        motivo = $"Anulación venta {numero}",
                        referencia_id = id.ToString(),
                        fecha_hora = ahora,
                        created_utc = ahora,
                        updated_utc = ahora
                    }, tx, cancellationToken: ct));

                // Kardex de la reversa al outbox (inmutable).
                await OutboxHelper.RegistrarAsync(cx, tx, "inventario", invId, "INSERT",
                    new Inventario
                    {
                        Id = invId,
                        ProductoId = Guid.Parse(d.producto_id),
                        Cantidad = (decimal)d.cantidad,
                        StockResultante = (decimal)stockResultante,
                        Motivo = $"Anulación venta {numero}",
                        ReferenciaId = id,
                        FechaHora = ahoraDt,
                        OrigenCajaId = string.Empty,
                        CreadoUtc = ahoraDt,
                        ActualizadoUtc = ahoraDt
                    }, string.Empty, ct);
            }

            await cx.ExecuteAsync(new CommandDefinition(
                "UPDATE ventas SET estado = @estado, updated_utc = @ahora WHERE id = @id",
                new { estado = (int)EstadoVenta.Anulada, ahora, id = id.ToString() },
                tx, cancellationToken: ct));

            await OutboxHelper.RegistrarAsync(cx, tx, "venta", id, "UPDATE",
                new { id, estado = (int)EstadoVenta.Anulada }, string.Empty, ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }
}

/// <summary>Fila cruda de 'ventas'.</summary>
internal sealed class FilaVenta
{
    public string id { get; set; } = "";
    public string numero { get; set; } = "";
    public string caja_id { get; set; } = "";
    public string fecha_hora { get; set; } = "";
    public long metodo_pago { get; set; }
    public long estado { get; set; }
    public double sub_total { get; set; }
    public double igv { get; set; }
    public double total { get; set; }
    public double? monto_recibido { get; set; }
    public string? comprobante_id { get; set; }
    public string origen_caja_id { get; set; } = "";
    public string created_utc { get; set; } = "";
    public string updated_utc { get; set; } = "";

    public Venta AVenta() => new()
    {
        Id = Guid.Parse(id),
        Numero = numero,
        CajaId = Guid.Parse(caja_id),
        FechaHora = DateTime.Parse(fecha_hora, null, System.Globalization.DateTimeStyles.RoundtripKind),
        MetodoPago = (MetodoPago)metodo_pago,
        Estado = (EstadoVenta)estado,
        SubTotal = (decimal)sub_total,
        Igv = (decimal)igv,
        Total = (decimal)total,
        MontoRecibido = monto_recibido is null ? null : (decimal)monto_recibido.Value,
        ComprobanteId = comprobante_id is null ? null : Guid.Parse(comprobante_id),
        OrigenCajaId = origen_caja_id,
        CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
        ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
    };
}

/// <summary>Fila cruda de 'detalle_ventas'.</summary>
internal sealed class FilaDetalle
{
    public string id { get; set; } = "";
    public string venta_id { get; set; } = "";
    public string producto_id { get; set; } = "";
    public string descripcion_producto { get; set; } = "";
    public double cantidad { get; set; }
    public double precio_unitario { get; set; }
    public double descuento { get; set; }
    public double importe { get; set; }
    public string origen_caja_id { get; set; } = "";
    public string created_utc { get; set; } = "";
    public string updated_utc { get; set; } = "";

    public DetalleVenta ADetalle() => new()
    {
        Id = Guid.Parse(id),
        VentaId = Guid.Parse(venta_id),
        ProductoId = Guid.Parse(producto_id),
        DescripcionProducto = descripcion_producto,
        Cantidad = (decimal)cantidad,
        PrecioUnitario = (decimal)precio_unitario,
        Descuento = (decimal)descuento,
        Importe = (decimal)importe,
        OrigenCajaId = origen_caja_id,
        CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
        ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
    };
}
