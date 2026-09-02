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
/// así que las dependencias — producto antes que venta, mesa antes que pedido —
/// ya están presentes al aplicar):
///   * <b>producto</b>, <b>venta</b> (cabecera), <b>caja</b>, <b>mesa</b>,
///     <b>pedido</b>, <b>pedido_linea</b>, <b>habitacion</b>,
///     <b>estadia_habitacion</b>: UPSERT con <b>last-write-wins</b> por
///     <c>updated_utc</c> (son mutables).
///   * <b>detalle de venta</b>, <b>movimiento_caja</b>, <b>inventario</b>:
///     insert-if-absent (registros inmutables, identidad UUID estable).
///   * <b>producto DELETE</b> / <b>venta UPDATE</b> (anulación): actualización con LWW.
///
/// -------------------------------------------------------------------------
///  EL STOCK NO SE RESUELVE POR LAST-WRITE-WINS (si no, se pierden ventas)
/// -------------------------------------------------------------------------
/// <c>productos.stock_actual</c> es una <b>caché derivada</b>; la verdad es el
/// kardex append-only de <c>inventario</c> (server/README.md §7.3,
/// docs/MOBILE-ARQUITECTURA.md §6). Con dos cajas vendiendo a la vez, pisar el
/// campo con el snapshot más nuevo pierde la venta de la otra caja:
///
///   stock 10. La PC vende 3 (stock 7, updated 10:00:01).
///   El móvil vende 2 (stock 8, updated 10:00:02).
///   LWW → gana el móvil → stock 8. La venta de la PC desapareció del stock.
///
/// Por eso, aquí:
///   1. El UPSERT de <c>producto</c> actualiza todo MENOS <c>stock_actual</c>
///      cuando la fila ya existe (en un INSERT nuevo sí se toma, como valor de
///      apertura). Un <c>stock_actual</c> remoto es informativo, no autoritativo.
///   2. Cada fila de <c>inventario</c> que entra <b>de verdad</b> (no un
///      duplicado) SUMA su <c>cantidad</c> a la caché. Como el kardex es
///      append-only y su UUID es global, reaplicar el mismo evento no vuelve a
///      sumar: el <c>ON CONFLICT DO NOTHING</c> devuelve 0 filas y no se toca el
///      stock. Queda un contador conmutativo: 10 − 3 − 2 = 5 llegue en el orden
///      que llegue.
///
/// -------------------------------------------------------------------------
///  CONTRATO DE SERIALIZACIÓN DEL PAYLOAD: PascalCase, case-SENSITIVE
/// -------------------------------------------------------------------------
/// <c>payload_json</c> es el snapshot que escribe <see cref="OutboxHelper"/> con
/// las opciones POR DEFECTO de System.Text.Json: sin naming policy, o sea los
/// nombres de propiedad de C# tal cual (<c>"Nombre"</c>, <c>"StockActual"</c>,
/// <c>"PrecioVenta"</c>). Aquí se deserializa igual de estricto
/// (<see cref="OpcionesPayload"/>, <c>PropertyNameCaseInsensitive = false</c>).
///
/// <b>NO cambiar a <see cref="JsonSerializerDefaults.Web"/>.</b> Web implica
/// camelCase + comparación insensible a mayúsculas, y eso rompería el contrato
/// en los dos sentidos: el móvil (mobile/packages/pagoya_core) emite su payload
/// en PascalCase precisamente porque este lado es case-sensitive, y un cambio
/// aquí haría que sus <c>"Total"</c>/<c>"SubTotal"</c> se ignoren en silencio y
/// se construyan ventas de S/ 0 que además pisarían las buenas por LWW.
/// Este contrato es de las tres partes (PC, móvil, backend): se cambia en las
/// tres a la vez o en ninguna.
///
/// Dos payloads viajan en <b>minúsculas</b> y así se quedan, porque el
/// escritorio los emite con tipos anónimos: la anulación de venta
/// (<c>{ id, estado }</c>) y la baja de producto (<c>{ id }</c>). Se leen con
/// <see cref="JsonDocument"/> por nombre exacto, no con el deserializador.
///
/// El sobre del transporte (<c>eventos</c>/<c>cambios</c>/<c>cursor</c> en
/// PagoYa.Cloud.HttpSyncTransport) SÍ usa camelCase: es otra capa, y
/// <c>payloadJson</c> viaja ahí dentro como cadena opaca sin re-serializar.
/// </summary>
public sealed class OutboxStore : IOutboxStore
{
    private const string ClaveCursor = "sync_cursor";

    /// <summary>
    /// Opciones de deserialización del <c>payload_json</c>. Explícitas a
    /// propósito: la distinción de mayúsculas es el contrato con el móvil, no un
    /// accidente del valor por defecto. Ver la nota de la clase.
    /// </summary>
    private static readonly JsonSerializerOptions OpcionesPayload = new()
    {
        PropertyNameCaseInsensitive = false
    };

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
                    EntidadesSync.Producto => op == "DELETE"
                        ? await AplicarBajaProductoAsync(cx, tx, c, ct)
                        : await AplicarUpsertProductoAsync(cx, tx, c, ct),
                    EntidadesSync.Venta => op == "UPDATE"
                        ? await AplicarEstadoVentaAsync(cx, tx, c, ct)
                        : await AplicarVentaAsync(cx, tx, c, ct),
                    EntidadesSync.Caja => await AplicarCajaAsync(cx, tx, c, ct),
                    EntidadesSync.MovimientoCaja => await AplicarMovimientoCajaAsync(cx, tx, c, ct),
                    EntidadesSync.Inventario => await AplicarInventarioAsync(cx, tx, c, ct),
                    EntidadesSync.Mesa => await AplicarMesaAsync(cx, tx, c, ct),
                    EntidadesSync.Pedido => await AplicarPedidoAsync(cx, tx, c, ct),
                    EntidadesSync.PedidoLinea => await AplicarPedidoLineaRemotaAsync(cx, tx, c, ct),
                    EntidadesSync.Habitacion => await AplicarHabitacionAsync(cx, tx, c, ct),
                    EntidadesSync.EstadiaHabitacion => await AplicarEstadiaAsync(cx, tx, c, ct),
                    // Entidad fuera del catálogo: se ignora en silencio (así una
                    // versión más nueva del móvil puede emitir entidades que esta
                    // instalación todavía no conoce, sin romper el ciclo de sync).
                    _ => 0
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
        var p = JsonSerializer.Deserialize<Producto>(c.PayloadJson, OpcionesPayload);
        if (p is null) return 0;

        // Upsert por id con LWW: solo pisa lo local si el remoto es más nuevo.
        //
        // OJO: `stock_actual` NO está en el DO UPDATE, a propósito. Es caché
        // derivada del kardex y pisarla por LWW pierde las ventas de la otra
        // caja (ver la nota de la clase y server/README.md §7.3). En el INSERT
        // sí se toma, porque ahí es el valor de apertura de un producto que esta
        // caja todavía no conocía; a partir de entonces solo lo mueven los
        // eventos de `inventario`, que son deltas idempotentes.
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
                -- stock_actual NO se actualiza: se acumula por deltas del kardex.
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
        var v = JsonSerializer.Deserialize<Venta>(c.PayloadJson, OpcionesPayload);
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
        var caja = JsonSerializer.Deserialize<Caja>(c.PayloadJson, OpcionesPayload);
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
        var m = JsonSerializer.Deserialize<MovimientoCaja>(c.PayloadJson, OpcionesPayload);
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

    /// <summary>
    /// Kardex remoto: insert-if-absent y, <b>solo si la fila entró de verdad</b>,
    /// suma su cantidad a la caché <c>productos.stock_actual</c>.
    ///
    /// Aquí está la corrección del riesgo de stock con LWW: el stock se acumula
    /// por deltas idempotentes en vez de sobrescribirse con un snapshot ajeno.
    /// Reaplicar el mismo evento (reintento, cursor rebobinado, doble entrega)
    /// no vuelve a descontar: el <c>ON CONFLICT DO NOTHING</c> devuelve 0 filas
    /// y se sale antes de tocar el stock.
    ///
    /// No se toca <c>productos.updated_utc</c>: mover la caché no es una edición
    /// del producto, y hacerlo le regalaría a esta caja la ventaja en el próximo
    /// LWW sobre nombre/precio.
    /// </summary>
    private static async Task<int> AplicarInventarioAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var inv = JsonSerializer.Deserialize<Inventario>(c.PayloadJson, OpcionesPayload);
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

        if (filas == 0) return 0; // duplicado: ya se contó, no volver a sumar

        // Delta idempotente sobre la caché. Solo productos que controlan stock;
        // si el producto todavía no llegó a esta caja, no hay fila que mover y
        // el UPDATE no afecta nada (el kardex ya quedó guardado, así que una
        // reparación posterior puede reconstruir el valor sumando la tabla).
        await cx.ExecuteAsync(new CommandDefinition(
            """
            UPDATE productos
            SET stock_actual = stock_actual + @cantidad
            WHERE id = @producto_id AND controla_stock = 1
            """,
            new
            {
                cantidad = (double)inv.Cantidad,
                producto_id = inv.ProductoId.ToString()
            }, tx, cancellationToken: ct));

        return 1;
    }

    // ------------------------------------------------------ Mesas / comandas ---

    private static async Task<int> AplicarMesaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var m = JsonSerializer.Deserialize<Mesa>(c.PayloadJson, OpcionesPayload);
        if (m is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO mesas
                (id, numero, zona, capacidad, estado, notas, activa,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Numero, @Zona, @Capacidad, @Estado, @Notas, @Activa,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero      = excluded.numero,
                zona        = excluded.zona,
                capacidad   = excluded.capacidad,
                estado      = excluded.estado,
                notas       = excluded.notas,
                activa      = excluded.activa,
                updated_utc = excluded.updated_utc
            WHERE excluded.updated_utc > mesas.updated_utc
            """,
            new
            {
                Id = m.Id.ToString(),
                m.Numero,
                m.Zona,
                m.Capacidad,
                Estado = (int)m.Estado,
                m.Notas,
                Activa = m.Activa ? 1 : 0,
                m.OrigenCajaId,
                CreadoUtc = m.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    /// <summary>
    /// Comanda con LWW en la cabecera. Las líneas que traiga el snapshot se
    /// aplican también aquí (el escritorio serializa <c>Pedido.Lineas</c> dentro
    /// del payload), de modo que una PC que aún no emite eventos
    /// <c>pedido_linea</c> sueltos igual replica su comanda completa.
    /// </summary>
    private static async Task<int> AplicarPedidoAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var p = JsonSerializer.Deserialize<Pedido>(c.PayloadJson, OpcionesPayload);
        if (p is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO pedidos
                (id, mesa_id, numero_mesa, numero, estado, mozo, comensales,
                 fecha_apertura, fecha_cierre, total, notas, venta_id,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @MesaId, @NumeroMesa, @Numero, @Estado, @Mozo, @Comensales,
                 @FechaApertura, @FechaCierre, @Total, @Notas, @VentaId,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero_mesa = excluded.numero_mesa,
                numero      = excluded.numero,
                estado      = excluded.estado,
                mozo        = excluded.mozo,
                comensales  = excluded.comensales,
                fecha_cierre= excluded.fecha_cierre,
                total       = excluded.total,
                notas       = excluded.notas,
                venta_id    = excluded.venta_id,
                updated_utc = excluded.updated_utc
            WHERE excluded.updated_utc > pedidos.updated_utc
            """,
            new
            {
                Id = p.Id.ToString(),
                MesaId = p.MesaId.ToString(),
                p.NumeroMesa,
                p.Numero,
                Estado = (int)p.Estado,
                p.Mozo,
                p.Comensales,
                FechaApertura = p.FechaApertura.ToString("o"),
                FechaCierre = p.FechaCierre?.ToString("o"),
                Total = (double)p.Total,
                p.Notas,
                VentaId = p.VentaId?.ToString(),
                p.OrigenCajaId,
                CreadoUtc = p.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        // Las líneas SÍ son mutables (el mozo corrige cantidades antes de enviar
        // a cocina), así que van con LWW y no con insert-if-absent. Se aplican
        // aunque la cabecera haya perdido su LWW: puede ser un reenvío donde la
        // cabecera ya estaba y las líneas no.
        foreach (var l in p.Lineas ?? new List<PedidoLinea>())
        {
            l.PedidoId = p.Id;
            if (string.IsNullOrEmpty(l.OrigenCajaId)) l.OrigenCajaId = p.OrigenCajaId;
            await UpsertPedidoLineaAsync(cx, tx, l, l.ActualizadoUtc, ct);
        }

        return filas > 0 ? 1 : 0;
    }

    private static async Task<int> AplicarPedidoLineaRemotaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var l = JsonSerializer.Deserialize<PedidoLinea>(c.PayloadJson, OpcionesPayload);
        if (l is null) return 0;
        return await UpsertPedidoLineaAsync(cx, tx, l, c.ActualizadoUtc, ct);
    }

    private static async Task<int> UpsertPedidoLineaAsync(
        SqliteConnection cx, SqliteTransaction tx, PedidoLinea l, DateTime actualizadoUtc, CancellationToken ct)
    {
        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO pedido_lineas
                (id, pedido_id, producto_id, descripcion, nota, cantidad,
                 precio_unitario, importe, enviado_cocina, origen_caja_id,
                 created_utc, updated_utc)
            VALUES
                (@Id, @PedidoId, @ProductoId, @Descripcion, @Nota, @Cantidad,
                 @PrecioUnitario, @Importe, @EnviadoCocina, @OrigenCajaId,
                 @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                producto_id     = excluded.producto_id,
                descripcion     = excluded.descripcion,
                nota            = excluded.nota,
                cantidad        = excluded.cantidad,
                precio_unitario = excluded.precio_unitario,
                importe         = excluded.importe,
                enviado_cocina  = excluded.enviado_cocina,
                updated_utc     = excluded.updated_utc
            WHERE excluded.updated_utc > pedido_lineas.updated_utc
            """,
            new
            {
                Id = l.Id.ToString(),
                PedidoId = l.PedidoId.ToString(),
                // Línea ad-hoc (plato fuera de catálogo): producto_id va NULL,
                // igual que en MesaRepository.AgregarLineaAsync.
                ProductoId = l.ProductoId == Guid.Empty ? null : l.ProductoId.ToString(),
                l.Descripcion,
                l.Nota,
                Cantidad = (double)l.Cantidad,
                PrecioUnitario = (double)l.PrecioUnitario,
                Importe = (double)l.Importe,
                EnviadoCocina = l.EnviadoCocina ? 1 : 0,
                l.OrigenCajaId,
                CreadoUtc = l.CreadoUtc.ToString("o"),
                ActualizadoUtc = actualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    // ----------------------------------------------------------------- Hotel ---

    private static async Task<int> AplicarHabitacionAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var h = JsonSerializer.Deserialize<Habitacion>(c.PayloadJson, OpcionesPayload);
        if (h is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO habitaciones
                (id, numero, piso, tipo, precio_noche, precio_hora, capacidad,
                 estado, notas, imagen_ruta, comodidades, activa,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Numero, @Piso, @Tipo, @PrecioNoche, @PrecioHora, @Capacidad,
                 @Estado, @Notas, @ImagenRuta, @Comodidades, @Activa,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero       = excluded.numero,
                piso         = excluded.piso,
                tipo         = excluded.tipo,
                precio_noche = excluded.precio_noche,
                precio_hora  = excluded.precio_hora,
                capacidad    = excluded.capacidad,
                estado       = excluded.estado,
                notas        = excluded.notas,
                imagen_ruta  = excluded.imagen_ruta,
                comodidades  = excluded.comodidades,
                activa       = excluded.activa,
                updated_utc  = excluded.updated_utc
            WHERE excluded.updated_utc > habitaciones.updated_utc
            """,
            new
            {
                Id = h.Id.ToString(),
                h.Numero,
                h.Piso,
                Tipo = (int)h.Tipo,
                PrecioNoche = (double)h.PrecioNoche,
                PrecioHora = (double)h.PrecioHora,
                h.Capacidad,
                Estado = (int)h.Estado,
                h.Notas,
                h.ImagenRuta,
                h.Comodidades,
                Activa = h.Activa ? 1 : 0,
                h.OrigenCajaId,
                CreadoUtc = h.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
            }, tx, cancellationToken: ct));

        return filas > 0 ? 1 : 0;
    }

    /// <summary>
    /// Estadía con LWW. <c>monto_consumos</c> viaja ya consolidado aquí porque
    /// <c>consumos_habitacion</c> NO está en el catálogo de entidades
    /// sincronizadas (ver <see cref="EntidadesSync"/>). Si dos recepciones cargan
    /// consumos a la vez gana el último, y es asumible: a diferencia del stock,
    /// una estadía la atiende una sola recepción a la vez.
    /// </summary>
    private static async Task<int> AplicarEstadiaAsync(
        SqliteConnection cx, SqliteTransaction tx, CambioRemoto c, CancellationToken ct)
    {
        var e = JsonSerializer.Deserialize<EstadiaHabitacion>(c.PayloadJson, OpcionesPayload);
        if (e is null) return 0;

        var filas = await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO estadias_habitacion
                (id, habitacion_id, numero_habitacion, huesped_nombre,
                 huesped_documento, huesped_telefono, personas, tipo_cobro,
                 precio_unitario, check_in_utc, check_out_utc, unidades,
                 monto_hospedaje, monto_consumos, total, metodo_pago, estado,
                 notas, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @HabitacionId, @NumeroHabitacion, @HuespedNombre,
                 @HuespedDocumento, @HuespedTelefono, @Personas, @TipoCobro,
                 @PrecioUnitario, @CheckInUtc, @CheckOutUtc, @Unidades,
                 @MontoHospedaje, @MontoConsumos, @Total, @MetodoPago, @Estado,
                 @Notas, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero_habitacion = excluded.numero_habitacion,
                huesped_nombre    = excluded.huesped_nombre,
                huesped_documento = excluded.huesped_documento,
                huesped_telefono  = excluded.huesped_telefono,
                personas          = excluded.personas,
                tipo_cobro        = excluded.tipo_cobro,
                precio_unitario   = excluded.precio_unitario,
                check_out_utc     = excluded.check_out_utc,
                unidades          = excluded.unidades,
                monto_hospedaje   = excluded.monto_hospedaje,
                monto_consumos    = excluded.monto_consumos,
                total             = excluded.total,
                metodo_pago       = excluded.metodo_pago,
                estado            = excluded.estado,
                notas             = excluded.notas,
                updated_utc       = excluded.updated_utc
            WHERE excluded.updated_utc > estadias_habitacion.updated_utc
            """,
            new
            {
                Id = e.Id.ToString(),
                HabitacionId = e.HabitacionId.ToString(),
                e.NumeroHabitacion,
                e.HuespedNombre,
                e.HuespedDocumento,
                e.HuespedTelefono,
                e.Personas,
                TipoCobro = (int)e.TipoCobro,
                PrecioUnitario = (double)e.PrecioUnitario,
                CheckInUtc = e.CheckInUtc.ToString("o"),
                CheckOutUtc = e.CheckOutUtc?.ToString("o"),
                Unidades = (double)e.Unidades,
                MontoHospedaje = (double)e.MontoHospedaje,
                MontoConsumos = (double)e.MontoConsumos,
                Total = (double)e.Total,
                e.MetodoPago,
                Estado = (int)e.Estado,
                e.Notas,
                e.OrigenCajaId,
                CreadoUtc = e.CreadoUtc.ToString("o"),
                ActualizadoUtc = c.ActualizadoUtc.ToString("o")
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
