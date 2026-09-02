using System.Text.Json;
using Dapper;
using Microsoft.Data.Sqlite;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IOutboxStore"/> para el motor de
/// sincronización. Lee/marca la tabla <c>outbox_sync</c>, guarda el cursor de
/// bajada en <c>meta</c> y aplica cambios remotos con resolución de conflictos.
///
/// Estrategia de merge por entidad (los eventos llegan ordenados por secuencia,
/// así que las dependencias — producto antes que venta, caja antes que venta —
/// ya están presentes al aplicar):
///   * <b>producto</b>, <b>venta</b> (cabecera), <b>caja</b>: UPSERT con
///     <b>last-write-wins</b> por <c>updated_utc</c> (mutables).
///   * <b>detalle de venta</b>, <b>movimiento_caja</b>, <b>inventario</b>:
///     insert-if-absent (registros inmutables, identidad UUID estable).
///   * <b>producto DELETE</b> / <b>venta UPDATE</b> (anulación): actualización con LWW.
///
/// Nota: la conciliación fina del stock entre cajas (netear salidas concurrentes)
/// es un paso posterior; aquí se replican las filas fielmente (respaldo + historial).
/// </summary>
public sealed class OutboxStore : IOutboxStore
{
    private const string ClaveCursor = "sync_cursor";
    private readonly PagoYaDbContext _db;

    public OutboxStore(PagoYaDbContext db) => _db = db;

    /// <inheritdoc />
    public async Task<IReadOnlyList<EventoSyncLocal>> LeerPendientesAsync(int max, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaOutbox>(new CommandDefinition(
            """
            SELECT id, entidad, entidad_id, operacion, payload_json, intentos,
                   origen_caja_id, created_utc
            FROM outbox_sync
            WHERE estado = 0
            ORDER BY created_utc
            LIMIT @max
            """,
            new { max }, cancellationToken: ct));

        return filas.Select(f => f.A()).ToList();
    }

    /// <inheritdoc />
    public async Task MarcarEnviadosAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct = default)
    {
        if (ids.Count == 0) return;
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE outbox_sync SET estado = 1, enviado_utc = @ahora WHERE id IN @ids",
            new { ahora = DateTime.UtcNow.ToString("o"), ids = ids.Select(i => i.ToString()) },
            cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task RegistrarFalloAsync(IReadOnlyCollection<Guid> ids, int maxIntentos, CancellationToken ct = default)
    {
        if (ids.Count == 0) return;
        await using var cx = await _db.CrearConexionAsync(ct);
        // Incrementa intentos; si alcanza el máximo, dead-letter (estado=2).
        await cx.ExecuteAsync(new CommandDefinition(
            """
            UPDATE outbox_sync
            SET intentos = intentos + 1,
                estado = CASE WHEN intentos + 1 >= @max THEN 2 ELSE estado END
            WHERE id IN @ids
            """,
            new { max = maxIntentos, ids = ids.Select(i => i.ToString()) },
            cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task<int> AplicarCambiosRemotosAsync(IReadOnlyList<CambioRemoto> cambios, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = (SqliteTransaction)await cx.BeginTransactionAsync(ct);
        var aplicados = 0;
        try
        {
            foreach (var c in cambios)
            {
                var op = c.Operacion.ToUpperInvariant();
                aplicados += c.Entidad.ToLowerInvariant() switch
                {
                    "producto" => op == "DELETE"
                        ? await AplicarBajaProductoAsync(cx, tx, c, ct)
                        : await AplicarUpsertProductoAsync(cx, tx, c, ct),
                    "venta" => op == "UPDATE"
                        ? await AplicarEstadoVentaAsync(cx, tx, c, ct)
                        : await AplicarVentaAsync(cx, tx, c, ct),
                    "caja" => await AplicarCajaAsync(cx, tx, c, ct),
                    "movimiento_caja" => await AplicarMovimientoCajaAsync(cx, tx, c, ct),
                    "inventario" => await AplicarInventarioAsync(cx, tx, c, ct),
                    _ => 0 // entidad no sincronizada: se ignora
                };
            }
            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
        return aplicados;
    }

    /// <inheritdoc />
    public async Task<string?> LeerCursorAsync(CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        return await cx.QuerySingleOrDefaultAsync<string?>(new CommandDefinition(
            "SELECT valor FROM meta WHERE clave = @clave",
            new { clave = ClaveCursor }, cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task GuardarCursorAsync(string cursor, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO meta (clave, valor) VALUES (@clave, @valor)
            ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor
            """,
            new { clave = ClaveCursor, valor = cursor }, cancellationToken: ct));
    }

    // ------------------------------------------------------------- Producto ---

    private static async Task<int> AplicarUpsertProductoAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var p = JsonSerializer.Deserialize<Producto>(c.PayloadJson);
        if (p is null) return 0;

        // Upsert por id con LWW: solo pisa lo local si el remoto es más nuevo.
        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO productos
                (id, codigo, nombre, descripcion, precio_venta, costo_compra,
                 precio_incluye_igv, unidad_medida, stock_actual, controla_stock,
                 activo, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Codigo, @Nombre, @Descripcion, @PrecioVenta, @CostoCompra,
                 @PrecioIncluyeIgv, @UnidadMedida, @StockActual, @ControlaStock,
                 @Activo, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                codigo             = excluded.codigo,
                nombre             = excluded.nombre,
                descripcion        = excluded.descripcion,
                precio_venta       = excluded.precio_venta,
                costo_compra       = excluded.costo_compra,
                precio_incluye_igv = excluded.precio_incluye_igv,
                unidad_medida      = excluded.unidad_medida,
                stock_actual       = excluded.stock_actual,
                controla_stock     = excluded.controla_stock,
                activo             = excluded.activo,
                updated_utc        = excluded.updated_utc
            WHERE excluded.updated_utc > productos.updated_utc
            """,
            new
            {
                Id = p.Id.ToString(),
                p.Codigo,
                p.Nombre,
                p.Descripcion,
                PrecioVenta = (double)p.PrecioVenta,
                CostoCompra = p.CostoCompra is null ? (double?)null : (double)p.CostoCompra.Value,
                PrecioIncluyeIgv = p.PrecioIncluyeIgv ? 1 : 0,
                p.UnidadMedida,
                StockActual = (double)p.StockActual,
                ControlaStock = p.ControlaStock ? 1 : 0,
                Activo = p.Activo ? 1 : 0,
                p.OrigenCajaId,
                CreadoUtc = p.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    private static async Task<int> AplicarBajaProductoAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            UPDATE productos SET activo = 0, updated_utc = @ts
            WHERE id = @id AND @ts > updated_utc
            """,
            new { id = c.EntidadId.ToString(), ts = c.ActualizadoUtc.ToString("o") },
            tx, cancellationToken: ct));
        return filas > 0 ? 1 : 0;
    }

    // ---------------------------------------------------------------- Venta ---

    private static async Task<int> AplicarVentaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var v = JsonSerializer.Deserialize<Venta>(c.PayloadJson);
        if (v is null) return 0;

        // Cabecera con LWW.
        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO ventas
                (id, numero, caja_id, fecha_hora, metodo_pago, estado, sub_total,
                 igv, total, monto_recibido, comprobante_id, origen_caja_id,
                 created_utc, updated_utc)
            VALUES
                (@Id, @Numero, @CajaId, @FechaHora, @MetodoPago, @Estado, @SubTotal,
                 @Igv, @Total, @MontoRecibido, @ComprobanteId, @OrigenCajaId,
                 @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                estado         = excluded.estado,
                metodo_pago    = excluded.metodo_pago,
                sub_total      = excluded.sub_total,
                igv            = excluded.igv,
                total          = excluded.total,
                monto_recibido = excluded.monto_recibido,
                comprobante_id = excluded.comprobante_id,
                updated_utc    = excluded.updated_utc
            WHERE excluded.updated_utc > ventas.updated_utc
            """,
            new
            {
                Id = v.Id.ToString(),
                v.Numero,
                CajaId = v.CajaId.ToString(),
                FechaHora = v.FechaHora.ToString("o"),
                MetodoPago = (int)v.MetodoPago,
                Estado = (int)v.Estado,
                SubTotal = (double)v.SubTotal,
                Igv = (double)v.Igv,
                Total = (double)v.Total,
                MontoRecibido = v.MontoRecibido is null ? (double?)null : (double)v.MontoRecibido.Value,
                ComprobanteId = v.ComprobanteId?.ToString(),
                v.OrigenCajaId,
                CreadoUtc = v.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        // Detalles (inmutables): insert-if-absent.
        foreach (var d in v.Detalles)
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
                ON CONFLICT(id) DO NOTHING
                """,
                new
                {
                    Id = d.Id.ToString(),
                    VentaId = v.Id.ToString(),
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

        return filas > 0 ? 1 : 0;
    }

    private static async Task<int> AplicarEstadoVentaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var estado = LeerEntero(c.PayloadJson, "estado");
        if (estado is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE ventas SET estado = @estado, updated_utc = @ts WHERE id = @id AND @ts > updated_utc",
            new { estado = estado.Value, ts = c.ActualizadoUtc.ToString("o"), id = c.EntidadId.ToString() },
            tx, cancellationToken: ct));
        return filas > 0 ? 1 : 0;
    }

    // ----------------------------------------------------------------- Caja ---

    private static async Task<int> AplicarCajaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var caja = JsonSerializer.Deserialize<Caja>(c.PayloadJson);
        if (caja is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO caja
                (id, nombre, cajero, estado, monto_apertura, fecha_apertura,
                 fecha_cierre, monto_cierre, diferencia, origen_caja_id,
                 created_utc, updated_utc)
            VALUES
                (@Id, @Nombre, @Cajero, @Estado, @MontoApertura, @FechaApertura,
                 @FechaCierre, @MontoCierre, @Diferencia, @OrigenCajaId,
                 @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                nombre       = excluded.nombre,
                cajero       = excluded.cajero,
                estado       = excluded.estado,
                fecha_cierre = excluded.fecha_cierre,
                monto_cierre = excluded.monto_cierre,
                diferencia   = excluded.diferencia,
                updated_utc  = excluded.updated_utc
            WHERE excluded.updated_utc > caja.updated_utc
            """,
            new
            {
                Id = caja.Id.ToString(),
                caja.Nombre,
                caja.Cajero,
                Estado = (int)caja.Estado,
                MontoApertura = (double)caja.MontoApertura,
                FechaApertura = caja.FechaApertura.ToString("o"),
                FechaCierre = caja.FechaCierre?.ToString("o"),
                MontoCierre = caja.MontoCierre is null ? (double?)null : (double)caja.MontoCierre.Value,
                Diferencia = caja.Diferencia is null ? (double?)null : (double)caja.Diferencia.Value,
                caja.OrigenCajaId,
                CreadoUtc = caja.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    private static async Task<int> AplicarMovimientoCajaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var m = JsonSerializer.Deserialize<MovimientoCaja>(c.PayloadJson);
        if (m is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO movimientos_caja
                (id, caja_id, tipo, monto, concepto, fecha_hora, origen_caja_id,
                 created_utc, updated_utc)
            VALUES
                (@Id, @CajaId, @Tipo, @Monto, @Concepto, @FechaHora, @OrigenCajaId,
                 @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO NOTHING
            """,
            new
            {
                Id = m.Id.ToString(),
                CajaId = m.CajaId.ToString(),
                Tipo = (int)m.Tipo,
                Monto = (double)m.Monto,
                m.Concepto,
                FechaHora = m.FechaHora.ToString("o"),
                m.OrigenCajaId,
                CreadoUtc = m.CreadoUtc.ToString("o"),
                ActualizadoUtc = m.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    // ------------------------------------------------------------ Inventario ---

    private static async Task<int> AplicarInventarioAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var inv = JsonSerializer.Deserialize<Inventario>(c.PayloadJson);
        if (inv is null) return 0;

        // Kardex inmutable: insert-if-absent (union por UUID entre cajas).
        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO inventario
                (id, producto_id, cantidad, stock_resultante, motivo, referencia_id,
                 fecha_hora, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @ProductoId, @Cantidad, @StockResultante, @Motivo, @ReferenciaId,
                 @FechaHora, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO NOTHING
            """,
            new
            {
                Id = inv.Id.ToString(),
                ProductoId = inv.ProductoId.ToString(),
                Cantidad = (double)inv.Cantidad,
                StockResultante = (double)inv.StockResultante,
                inv.Motivo,
                ReferenciaId = inv.ReferenciaId?.ToString(),
                FechaHora = inv.FechaHora.ToString("o"),
                inv.OrigenCajaId,
                CreadoUtc = inv.CreadoUtc.ToString("o"),
                ActualizadoUtc = inv.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    // --------------------------------------------------------------- Helpers ---

    private static int? LeerEntero(string payloadJson, string propiedad)
    {
        try
        {
            using var doc = JsonDocument.Parse(payloadJson);
            if (doc.RootElement.TryGetProperty(propiedad, out var p) && p.TryGetInt32(out var v))
                return v;
        }
        catch (JsonException) { /* payload sin esa propiedad */ }
        return null;
    }

    private sealed class FilaOutbox
    {
        public string id { get; set; } = "";
        public string entidad { get; set; } = "";
        public string entidad_id { get; set; } = "";
        public string operacion { get; set; } = "";
        public string payload_json { get; set; } = "";
        public long intentos { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";

        public EventoSyncLocal A() => new(
            Guid.Parse(id), entidad, Guid.Parse(entidad_id), operacion, payload_json,
            (int)intentos, origen_caja_id,
            DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind));
    }
}
