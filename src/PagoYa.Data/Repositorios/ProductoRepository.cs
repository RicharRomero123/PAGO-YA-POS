using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IProductoRepository"/>.
///
/// Mapea la tabla 'productos'. Los montos decimales se guardan como REAL en
/// SQLite; el mapeo Dapper convierte automáticamente decimal &lt;-&gt; double.
/// Los booleanos viajan como INTEGER 0/1 (ver <see cref="MapeoProducto"/>).
///
/// Nota outbox: en el tier Base la tabla outbox_sync existe pero se ignora; se
/// escribe en ella igualmente para que, al activar Cloud, el histórico ya esté
/// disponible para sincronizar. Ver <see cref="OutboxHelper"/>.
/// </summary>
public sealed class ProductoRepository : IProductoRepository
{
    private readonly PagoYaDbContext _db;

    public ProductoRepository(PagoYaDbContext db) => _db = db;

    private const string SelectBase = """
        SELECT id, codigo, nombre, descripcion, precio_venta, costo_compra,
               precio_incluye_igv, unidad_medida, stock_actual, controla_stock,
               activo, imagen_ruta, proveedor_id, tipo_descuento, descuento_valor,
               stock_minimo, fecha_vencimiento, lote, registro_sanitario,
               principio_activo, requiere_receta, personalizacion_json,
               origen_caja_id, created_utc, updated_utc
        FROM productos
        """;

    /// <inheritdoc />
    public async Task<Producto?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaProducto>(
            new CommandDefinition(
                $"{SelectBase} WHERE id = @id",
                new { id = id.ToString() },
                cancellationToken: ct));
        return fila?.AProducto();
    }

    /// <inheritdoc />
    public async Task<Producto?> ObtenerPorCodigoAsync(string codigo, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaProducto>(
            new CommandDefinition(
                $"{SelectBase} WHERE codigo = @codigo AND activo = 1",
                new { codigo },
                cancellationToken: ct));
        return fila?.AProducto();
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<Producto>> BuscarAsync(string? filtro = null, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);

        string sql;
        object? parametros;
        if (string.IsNullOrWhiteSpace(filtro))
        {
            sql = $"{SelectBase} WHERE activo = 1 ORDER BY nombre COLLATE NOCASE";
            parametros = null;
        }
        else
        {
            // Incluye principio_activo para poder buscar genéricos por DCI (farmacia).
            sql = $"{SelectBase} WHERE activo = 1 AND (nombre LIKE @f OR codigo LIKE @f OR principio_activo LIKE @f) ORDER BY nombre COLLATE NOCASE";
            parametros = new { f = $"%{filtro.Trim()}%" };
        }

        var filas = await cx.QueryAsync<FilaProducto>(
            new CommandDefinition(sql, parametros, cancellationToken: ct));
        return filas.Select(f => f.AProducto()).ToList();
    }

    /// <inheritdoc />
    public async Task GuardarAsync(Producto producto, CancellationToken ct = default)
    {
        producto.ActualizadoUtc = DateTime.UtcNow;

        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        const string upsert = """
            INSERT INTO productos
                (id, codigo, nombre, descripcion, precio_venta, costo_compra,
                 precio_incluye_igv, unidad_medida, stock_actual, controla_stock,
                 activo, imagen_ruta, proveedor_id, tipo_descuento, descuento_valor,
                 stock_minimo, fecha_vencimiento, lote, registro_sanitario,
                 principio_activo, requiere_receta, personalizacion_json,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Codigo, @Nombre, @Descripcion, @PrecioVenta, @CostoCompra,
                 @PrecioIncluyeIgv, @UnidadMedida, @StockActual, @ControlaStock,
                 @Activo, @ImagenRuta, @ProveedorId, @TipoDescuento, @DescuentoValor,
                 @StockMinimo, @FechaVencimiento, @Lote, @RegistroSanitario,
                 @PrincipioActivo, @RequiereReceta, @PersonalizacionJson,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
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
                imagen_ruta        = excluded.imagen_ruta,
                proveedor_id       = excluded.proveedor_id,
                tipo_descuento     = excluded.tipo_descuento,
                descuento_valor    = excluded.descuento_valor,
                stock_minimo       = excluded.stock_minimo,
                fecha_vencimiento  = excluded.fecha_vencimiento,
                lote               = excluded.lote,
                registro_sanitario = excluded.registro_sanitario,
                principio_activo   = excluded.principio_activo,
                requiere_receta    = excluded.requiere_receta,
                personalizacion_json = excluded.personalizacion_json,
                updated_utc        = excluded.updated_utc
            """;

        await cx.ExecuteAsync(new CommandDefinition(
            upsert, MapeoProducto.AParametros(producto), tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "producto", producto.Id, "UPSERT",
            producto, producto.OrigenCajaId, ct);

        await tx.CommitAsync(ct);
    }

    /// <inheritdoc />
    public async Task DesactivarAsync(Guid id, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE productos SET activo = 0, updated_utc = @ahora WHERE id = @id",
            new { id = id.ToString(), ahora }, tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "producto", id, "DELETE",
            new { id }, string.Empty, ct);

        await tx.CommitAsync(ct);
    }
}

/// <summary>Fila cruda de la tabla 'productos' (nombres snake_case de SQLite).</summary>
internal sealed class FilaProducto
{
    public string id { get; set; } = "";
    public string codigo { get; set; } = "";
    public string nombre { get; set; } = "";
    public string? descripcion { get; set; }
    public double precio_venta { get; set; }
    public double? costo_compra { get; set; }
    public long precio_incluye_igv { get; set; }
    public string unidad_medida { get; set; } = "NIU";
    public double stock_actual { get; set; }
    public long controla_stock { get; set; }
    public long activo { get; set; }
    public string? imagen_ruta { get; set; }
    public string? proveedor_id { get; set; }
    public long tipo_descuento { get; set; }
    public double descuento_valor { get; set; }
    public double stock_minimo { get; set; }
    public string? fecha_vencimiento { get; set; }
    public string? lote { get; set; }
    public string? registro_sanitario { get; set; }
    public string? principio_activo { get; set; }
    public long requiere_receta { get; set; }
    public string? personalizacion_json { get; set; }
    public string origen_caja_id { get; set; } = "";
    public string created_utc { get; set; } = "";
    public string updated_utc { get; set; } = "";

    public Producto AProducto() => new()
    {
        Id = Guid.Parse(id),
        Codigo = codigo,
        Nombre = nombre,
        Descripcion = descripcion,
        PrecioVenta = (decimal)precio_venta,
        CostoCompra = costo_compra is null ? null : (decimal)costo_compra.Value,
        PrecioIncluyeIgv = precio_incluye_igv != 0,
        UnidadMedida = unidad_medida,
        StockActual = (decimal)stock_actual,
        ControlaStock = controla_stock != 0,
        Activo = activo != 0,
        ImagenRuta = imagen_ruta,
        ProveedorId = string.IsNullOrEmpty(proveedor_id) ? null : Guid.Parse(proveedor_id),
        TipoDescuento = (PagoYa.Core.Enums.TipoDescuento)tipo_descuento,
        DescuentoValor = (decimal)descuento_valor,
        StockMinimo = (decimal)stock_minimo,
        FechaVencimiento = string.IsNullOrWhiteSpace(fecha_vencimiento)
            ? null
            : DateTime.Parse(fecha_vencimiento, System.Globalization.CultureInfo.InvariantCulture,
                             System.Globalization.DateTimeStyles.None),
        Lote = lote,
        RegistroSanitario = registro_sanitario,
        PrincipioActivo = principio_activo,
        RequiereReceta = requiere_receta != 0,
        PersonalizacionJson = personalizacion_json,
        OrigenCajaId = origen_caja_id,
        CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
        ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
    };
}

/// <summary>Mapeo de <see cref="Producto"/> a parámetros SQL con conversión de tipos SQLite.</summary>
internal static class MapeoProducto
{
    public static object AParametros(Producto p) => new
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
        p.ImagenRuta,
        ProveedorId = p.ProveedorId?.ToString(),
        TipoDescuento = (int)p.TipoDescuento,
        DescuentoValor = (double)p.DescuentoValor,
        StockMinimo = (double)p.StockMinimo,
        FechaVencimiento = p.FechaVencimiento?.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture),
        p.Lote,
        p.RegistroSanitario,
        p.PrincipioActivo,
        RequiereReceta = p.RequiereReceta ? 1 : 0,
        p.PersonalizacionJson,
        p.OrigenCajaId,
        CreadoUtc = p.CreadoUtc.ToString("o"),
        ActualizadoUtc = p.ActualizadoUtc.ToString("o")
    };
}
