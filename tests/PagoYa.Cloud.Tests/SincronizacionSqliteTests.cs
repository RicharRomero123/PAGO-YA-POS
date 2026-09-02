using System.Text.Json;
using Dapper;
using PagoYa.Cloud;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Data;
using PagoYa.Data.Repositorios;
using Xunit;

namespace PagoYa.Cloud.Tests;

/// <summary>
/// Sincronización real sobre SQLite: OutboxStore contra una BD temporal y
/// consolidación multi-caja extremo a extremo vía el transporte en memoria.
/// </summary>
public sealed class SincronizacionSqliteTests
{
    /// <summary>Nodo/caja de sincronización: BD SQLite temporal ya inicializada, con repos + outbox store.</summary>
    private sealed class Nodo : IDisposable
    {
        public string Ruta { get; }
        public PagoYaDbContext Db { get; }
        public ProductoRepository Productos { get; }
        public CajaRepository Cajas { get; }
        public VentaRepository Ventas { get; }
        public OutboxStore Outbox { get; }

        public Nodo()
        {
            Ruta = Path.Combine(Path.GetTempPath(), $"pagoya-sync-{Guid.NewGuid():N}.db");
            Db = new PagoYaDbContext(Ruta);
            Db.InicializarEsquema();
            Productos = new ProductoRepository(Db);
            Cajas = new CajaRepository(Db);
            Ventas = new VentaRepository(Db);
            Outbox = new OutboxStore(Db);
        }

        public void Dispose()
        {
            foreach (var f in new[] { Ruta, Ruta + "-wal", Ruta + "-shm" })
                try { if (File.Exists(f)) File.Delete(f); } catch { /* best effort */ }
        }
    }

    private static Producto NuevoProducto(string codigo, string nombre, string origen = "cajaA") => new()
    {
        Id = Guid.NewGuid(),
        Codigo = codigo,
        Nombre = nombre,
        PrecioVenta = 3.50m,
        OrigenCajaId = origen
    };

    // -------------------------------------------------------- OutboxStore ---

    [Fact]
    public async Task Outbox_Pendientes_SeMarcanEnviados()
    {
        using var caja = new Nodo();
        await caja.Productos.GuardarAsync(NuevoProducto("001", "Inca Kola"));

        var pend = await caja.Outbox.LeerPendientesAsync(50);
        Assert.Single(pend);
        Assert.Equal("producto", pend[0].Entidad);

        await caja.Outbox.MarcarEnviadosAsync(new[] { pend[0].Id });
        Assert.Empty(await caja.Outbox.LeerPendientesAsync(50));
    }

    [Fact]
    public async Task Outbox_Fallo_DeadLetterAlSuperarMaximo()
    {
        using var caja = new Nodo();
        await caja.Productos.GuardarAsync(NuevoProducto("001", "Item"));
        var id = (await caja.Outbox.LeerPendientesAsync(50))[0].Id;

        // maxIntentos=2: primer fallo lo deja pendiente; el segundo lo saca (estado=2).
        await caja.Outbox.RegistrarFalloAsync(new[] { id }, maxIntentos: 2);
        Assert.Single(await caja.Outbox.LeerPendientesAsync(50));

        await caja.Outbox.RegistrarFalloAsync(new[] { id }, maxIntentos: 2);
        Assert.Empty(await caja.Outbox.LeerPendientesAsync(50)); // dead-letter, ya no pendiente
    }

    [Fact]
    public async Task Outbox_Cursor_RoundTrip()
    {
        using var caja = new Nodo();
        Assert.Null(await caja.Outbox.LeerCursorAsync());
        await caja.Outbox.GuardarCursorAsync("42");
        Assert.Equal("42", await caja.Outbox.LeerCursorAsync());
        await caja.Outbox.GuardarCursorAsync("43");
        Assert.Equal("43", await caja.Outbox.LeerCursorAsync());
    }

    [Fact]
    public async Task AplicarCambios_UpsertProducto_RespetaLastWriteWins()
    {
        using var caja = new Nodo();
        var id = Guid.NewGuid();
        var t = DateTime.UtcNow;

        // 1) Insert remoto inicial.
        await caja.Outbox.AplicarCambiosRemotosAsync(new[] { CambioProducto(id, "Nombre v1", t) });
        Assert.Equal("Nombre v1", (await caja.Productos.ObtenerPorIdAsync(id))!.Nombre);

        // 2) Cambio MÁS VIEJO: no debe pisar.
        await caja.Outbox.AplicarCambiosRemotosAsync(new[] { CambioProducto(id, "Nombre viejo", t.AddMinutes(-10)) });
        Assert.Equal("Nombre v1", (await caja.Productos.ObtenerPorIdAsync(id))!.Nombre);

        // 3) Cambio MÁS NUEVO: sí pisa.
        await caja.Outbox.AplicarCambiosRemotosAsync(new[] { CambioProducto(id, "Nombre v2", t.AddMinutes(10)) });
        Assert.Equal("Nombre v2", (await caja.Productos.ObtenerPorIdAsync(id))!.Nombre);
    }

    private static CambioRemoto CambioProducto(Guid id, string nombre, DateTime actualizado)
    {
        var p = new Producto
        {
            Id = id, Codigo = "C-" + id.ToString("N")[..6], Nombre = nombre,
            PrecioVenta = 1m, OrigenCajaId = "cajaB", CreadoUtc = actualizado, ActualizadoUtc = actualizado
        };
        return new CambioRemoto("producto", id, "UPSERT", JsonSerializer.Serialize(p), actualizado, "cajaB");
    }

    // ---------------------------------------------- Consolidación E2E ------

    [Fact]
    public async Task MultiCaja_ProductoCreadoEnA_LlegaAB()
    {
        using var cajaA = new Nodo();
        using var cajaB = new Nodo();
        var backend = new TransporteSyncEnMemoria(); // "nube" compartida

        var syncA = new CloudSyncService(cajaA.Outbox, backend);
        var syncB = new CloudSyncService(cajaB.Outbox, backend);

        // En caja A se da de alta un producto (se registra en su outbox).
        var producto = NuevoProducto("7501", "Leche Gloria", origen: "cajaA");
        await cajaA.Productos.GuardarAsync(producto);

        // A sube; B baja y consolida.
        var rA = await syncA.SincronizarAsync();
        var rB = await syncB.SincronizarAsync();

        Assert.True(rA.Exito, rA.Mensaje);
        Assert.Equal(1, rA.Enviados);
        Assert.True(rB.Exito, rB.Mensaje);
        Assert.True(rB.Recibidos >= 1);

        // El producto de A ahora existe en B.
        var enB = await cajaB.Productos.ObtenerPorIdAsync(producto.Id);
        Assert.NotNull(enB);
        Assert.Equal("Leche Gloria", enB!.Nombre);
    }

    [Fact]
    public async Task MultiCaja_ConsolidaCajaVentaDetalleMovimientoEInventario()
    {
        using var cajaA = new Nodo();
        using var cajaB = new Nodo();
        var backend = new TransporteSyncEnMemoria();

        // --- Caja A: abre sesión, carga producto, mueve efectivo y vende ---
        var sesion = new Caja { Nombre = "Caja 1", Cajero = "Tester", MontoApertura = 100m, OrigenCajaId = "cajaA" };
        await cajaA.Cajas.AbrirCajaAsync(sesion);

        var prod = NuevoProducto("7501", "Inca Kola", "cajaA");
        prod.StockActual = 50;
        await cajaA.Productos.GuardarAsync(prod);

        await cajaA.Cajas.RegistrarMovimientoAsync(new MovimientoCaja
        {
            CajaId = sesion.Id, Tipo = TipoMovimientoCaja.Ingreso, Monto = 50m,
            Concepto = "Aporte dueño", OrigenCajaId = "cajaA"
        });

        var venta = new Venta
        {
            Numero = "V-0001", CajaId = sesion.Id, FechaHora = DateTime.Now,
            MetodoPago = MetodoPago.Efectivo, Estado = EstadoVenta.Completada,
            SubTotal = 5.0m, Igv = 0.90m, Total = 5.90m, OrigenCajaId = "cajaA"
        };
        venta.Detalles.Add(new DetalleVenta
        {
            ProductoId = prod.Id, DescripcionProducto = prod.Nombre,
            Cantidad = 2, PrecioUnitario = 2.95m, Importe = 5.90m, OrigenCajaId = "cajaA"
        });
        await cajaA.Ventas.RegistrarAsync(venta);

        // --- Sincronización: A sube, B baja ---
        var rA = await new CloudSyncService(cajaA.Outbox, backend).SincronizarAsync();
        var rB = await new CloudSyncService(cajaB.Outbox, backend).SincronizarAsync();
        Assert.True(rA.Exito, rA.Mensaje);
        Assert.True(rB.Exito, rB.Mensaje);

        // --- En caja B se consolidó TODO ---
        Assert.NotNull(await cajaB.Cajas.ObtenerPorIdAsync(sesion.Id));               // caja
        Assert.NotNull(await cajaB.Productos.ObtenerPorIdAsync(prod.Id));             // producto

        var ventaB = await cajaB.Ventas.ObtenerPorIdAsync(venta.Id);                  // venta + detalle
        Assert.NotNull(ventaB);
        Assert.Single(ventaB!.Detalles);
        Assert.Equal(prod.Id, ventaB.Detalles[0].ProductoId);

        var movimientos = await cajaB.Cajas.ListarMovimientosAsync(sesion.Id);        // movimiento_caja
        Assert.Contains(movimientos, m => m.Concepto == "Aporte dueño");

        var kardex = await ContarInventarioAsync(cajaB, prod.Id);                     // inventario (kardex)
        Assert.True(kardex >= 1, "el kardex de la venta debió consolidarse en B");
    }

    private static async Task<long> ContarInventarioAsync(Nodo caja, Guid productoId)
    {
        await using var cx = await caja.Db.CrearConexionAsync();
        return await cx.ExecuteScalarAsync<long>(
            "SELECT COUNT(*) FROM inventario WHERE producto_id = @id",
            new { id = productoId.ToString() });
    }
}
