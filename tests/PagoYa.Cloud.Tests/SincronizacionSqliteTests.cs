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
        public MesaRepository Mesas { get; }
        public HotelRepository Hotel { get; }
        public OutboxStore Outbox { get; }

        public Nodo()
        {
            Ruta = Path.Combine(Path.GetTempPath(), $"pagoya-sync-{Guid.NewGuid():N}.db");
            Db = new PagoYaDbContext(Ruta);
            Db.InicializarEsquema();
            Productos = new ProductoRepository(Db);
            Cajas = new CajaRepository(Db);
            Ventas = new VentaRepository(Db);
            Mesas = new MesaRepository(Db);
            Hotel = new HotelRepository(Db);
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

    // =========================================================================
    //  STOCK MULTI-CAJA: el kardex manda, `stock_actual` es caché
    //  (server/README.md §7.3, docs/MOBILE-ARQUITECTURA.md §6)
    // =========================================================================

    /// <summary>
    /// EL caso que motivó el cambio: dos cajas venden el mismo producto a la vez.
    ///
    ///   Stock inicial 10.
    ///   La PC vende 3   → localmente queda en 7 y emite su kardex (−3).
    ///   El móvil vende 2 → su snapshot de producto dice stock 8 y su kardex −2.
    ///
    /// Con last-write-wins sobre `stock_actual` ganaba el snapshot más nuevo y el
    /// stock quedaba en 8 (o en 7): una de las dos ventas desaparecía del
    /// inventario. Con deltas desde el kardex queda 10 − 3 − 2 = <b>5</b>.
    /// </summary>
    [Fact]
    public async Task Stock_DosCajasVendiendoALaVez_SeNeteanAmbasVentas_10menos2menos3igual5()
    {
        using var pc = new Nodo();

        // --- Estado inicial en la PC: 10 unidades ---
        var prod = NuevoProducto("7501", "Inca Kola", origen: "C01");
        prod.StockActual = 10m;
        prod.ControlaStock = true;
        await pc.Productos.GuardarAsync(prod);

        // --- La PC vende 3 (descuenta la caché y escribe su propio kardex) ---
        var sesion = new Caja { Nombre = "Caja 1", Cajero = "Tester", MontoApertura = 100m, OrigenCajaId = "C01" };
        await pc.Cajas.AbrirCajaAsync(sesion);

        var venta = new Venta
        {
            Numero = "C01-000001", CajaId = sesion.Id, FechaHora = DateTime.Now,
            MetodoPago = MetodoPago.Efectivo, Estado = EstadoVenta.Completada,
            SubTotal = 5.0m, Igv = 0.90m, Total = 5.90m, OrigenCajaId = "C01"
        };
        venta.Detalles.Add(new DetalleVenta
        {
            ProductoId = prod.Id, DescripcionProducto = prod.Nombre,
            Cantidad = 3, PrecioUnitario = 2.95m, Importe = 8.85m, OrigenCajaId = "C01"
        });
        await pc.Ventas.RegistrarAsync(venta);

        Assert.Equal(7m, (await pc.Productos.ObtenerPorIdAsync(prod.Id))!.StockActual);

        // --- Llega la sincronización del móvil, que vendió 2 ---
        // Su snapshot de producto es MÁS NUEVO y trae stock_actual = 8 (10 − 2,
        // porque el móvil nunca vio la venta de la PC). Además viene su kardex.
        var tMovil = DateTime.UtcNow.AddMinutes(5);

        var snapshotMovil = new Producto
        {
            Id = prod.Id, Codigo = prod.Codigo, Nombre = "Inca Kola 500ml", // sí se renombró
            PrecioVenta = 3.50m, StockActual = 8m, ControlaStock = true, Activo = true,
            OrigenCajaId = "M01", CreadoUtc = prod.CreadoUtc, ActualizadoUtc = tMovil
        };

        var kardexMovil = new Inventario
        {
            Id = Guid.NewGuid(), ProductoId = prod.Id, Cantidad = -2m, StockResultante = 8m,
            Motivo = "Venta M01-000001", ReferenciaId = Guid.NewGuid(), FechaHora = tMovil,
            OrigenCajaId = "M01", CreadoUtc = tMovil, ActualizadoUtc = tMovil
        };

        var aplicados = await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("producto", prod.Id, "UPSERT",
                JsonSerializer.Serialize(snapshotMovil), tMovil, "M01"),
            new CambioRemoto("inventario", kardexMovil.Id, "INSERT",
                JsonSerializer.Serialize(kardexMovil), tMovil, "M01")
        });

        Assert.Equal(2, aplicados);

        var despues = (await pc.Productos.ObtenerPorIdAsync(prod.Id))!;

        // El resto del producto SÍ se actualiza por LWW (es mutable y el remoto
        // es más nuevo): el renombrado del móvil llegó.
        Assert.Equal("Inca Kola 500ml", despues.Nombre);

        // Pero el stock NO se pisó con el 8 del snapshot: se acumuló el delta.
        Assert.Equal(5m, despues.StockActual);
    }

    /// <summary>
    /// El delta es idempotente: reaplicar el mismo evento de kardex (reintento,
    /// doble entrega, cursor rebobinado) no vuelve a descontar. Sin esta
    /// propiedad, "acumular deltas" sería peor que el LWW que reemplaza.
    /// </summary>
    [Fact]
    public async Task Stock_KardexRemotoReaplicado_NoDescuentaDosVeces()
    {
        using var pc = new Nodo();

        var prod = NuevoProducto("7502", "Agua San Luis", origen: "C01");
        prod.StockActual = 10m;
        await pc.Productos.GuardarAsync(prod);

        var t = DateTime.UtcNow.AddMinutes(1);
        var kardex = new Inventario
        {
            Id = Guid.NewGuid(), ProductoId = prod.Id, Cantidad = -4m, StockResultante = 6m,
            Motivo = "Venta M01-000002", FechaHora = t, OrigenCajaId = "M01",
            CreadoUtc = t, ActualizadoUtc = t
        };
        var cambio = new CambioRemoto("inventario", kardex.Id, "INSERT",
            JsonSerializer.Serialize(kardex), t, "M01");

        Assert.Equal(1, await pc.Outbox.AplicarCambiosRemotosAsync(new[] { cambio }));
        Assert.Equal(6m, (await pc.Productos.ObtenerPorIdAsync(prod.Id))!.StockActual);

        // Mismo evento otra vez: ni se cuenta como aplicado ni mueve el stock.
        Assert.Equal(0, await pc.Outbox.AplicarCambiosRemotosAsync(new[] { cambio }));
        Assert.Equal(6m, (await pc.Productos.ObtenerPorIdAsync(prod.Id))!.StockActual);
        Assert.Equal(1, await ContarInventarioAsync(pc, prod.Id));
    }

    /// <summary>
    /// Un producto que esta caja aún no conocía SÍ toma el `stock_actual` del
    /// snapshot: en un INSERT es el valor de apertura, no un conflicto.
    /// </summary>
    [Fact]
    public async Task Stock_ProductoNuevoRemoto_TomaElStockDelSnapshotComoApertura()
    {
        using var pc = new Nodo();
        var id = Guid.NewGuid();
        var t = DateTime.UtcNow;

        var remoto = new Producto
        {
            Id = id, Codigo = "9001", Nombre = "Galleta Soda", PrecioVenta = 1.20m,
            StockActual = 24m, OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };

        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("producto", id, "UPSERT", JsonSerializer.Serialize(remoto), t, "M01")
        });

        Assert.Equal(24m, (await pc.Productos.ObtenerPorIdAsync(id))!.StockActual);
    }

    // =========================================================================
    //  CATÁLOGO DE ENTIDADES DE SYNC (server/README.md §7.2)
    // =========================================================================

    [Fact]
    public void Catalogo_SonExactamenteLasDiezAcordadas()
    {
        Assert.Equal(new[]
        {
            "producto", "venta", "caja", "movimiento_caja", "inventario",
            "mesa", "pedido", "pedido_linea", "habitacion", "estadia_habitacion"
        }, EntidadesSync.Todas);

        // Las que NO se sincronizan, y así se quedan.
        Assert.False(EntidadesSync.EsConocida("proveedor"));
        Assert.False(EntidadesSync.EsConocida("usuario"));
        Assert.False(EntidadesSync.EsConocida("consumos_habitacion"));
    }

    /// <summary>
    /// Las cinco entidades nuevas (comandas + hotel) se aplican de verdad contra
    /// SQLite. Hasta ahora `AplicarCambiosRemotosAsync` las ignoraba: el mozo
    /// tomaba la comanda en el móvil y en la PC no aparecía nada.
    /// </summary>
    [Fact]
    public async Task Catalogo_MesasComandasYHotel_SeAplicanEnLaPc()
    {
        using var pc = new Nodo();
        var t = DateTime.UtcNow;

        var mesa = new Mesa
        {
            Id = Guid.NewGuid(), Numero = "7", Zona = "Terraza", Capacidad = 6,
            Estado = EstadoMesa.Ocupada, Activa = true, OrigenCajaId = "M01",
            CreadoUtc = t, ActualizadoUtc = t
        };

        var linea = new PedidoLinea
        {
            Id = Guid.NewGuid(), Descripcion = "Pollo a la brasa 1/4", Nota = "sin ají",
            Cantidad = 2m, PrecioUnitario = 15m, Importe = 30m, EnviadoCocina = true,
            OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };
        var pedido = new Pedido
        {
            Id = Guid.NewGuid(), MesaId = mesa.Id, NumeroMesa = "7", Numero = "M01-P-0001",
            Estado = EstadoPedido.Abierta, Mozo = "Luis", Comensales = 4,
            FechaApertura = DateTime.Now, Total = 30m, OrigenCajaId = "M01",
            CreadoUtc = t, ActualizadoUtc = t
        };
        pedido.Lineas.Add(linea);

        var habitacion = new Habitacion
        {
            Id = Guid.NewGuid(), Numero = "204", Piso = 2, Tipo = TipoHabitacion.Matrimonial,
            PrecioNoche = 90m, PrecioHora = 25m, Capacidad = 2,
            Estado = EstadoHabitacion.Ocupada, Activa = true, Comodidades = "TV|Wifi",
            OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };
        var estadia = new EstadiaHabitacion
        {
            Id = Guid.NewGuid(), HabitacionId = habitacion.Id, NumeroHabitacion = "204",
            HuespedNombre = "Ana Quispe", HuespedDocumento = "45678912", Personas = 2,
            TipoCobro = TipoCobroHospedaje.Noche, PrecioUnitario = 90m,
            CheckInUtc = t, Unidades = 1m, MontoHospedaje = 90m,
            MontoConsumos = 12.50m, Total = 102.50m, Estado = EstadoEstadia.Activa,
            OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };

        // Orden de llegada = orden de dependencias (mesa antes que pedido).
        var aplicados = await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("mesa", mesa.Id, "UPSERT", JsonSerializer.Serialize(mesa), t, "M01"),
            new CambioRemoto("pedido", pedido.Id, "UPSERT", JsonSerializer.Serialize(pedido), t, "M01"),
            new CambioRemoto("habitacion", habitacion.Id, "UPSERT", JsonSerializer.Serialize(habitacion), t, "M01"),
            new CambioRemoto("estadia_habitacion", estadia.Id, "UPSERT", JsonSerializer.Serialize(estadia), t, "M01")
        });
        Assert.Equal(4, aplicados);

        var mesaPc = await pc.Mesas.ObtenerMesaAsync(mesa.Id);
        Assert.NotNull(mesaPc);
        Assert.Equal("Terraza", mesaPc!.Zona);
        Assert.Equal(EstadoMesa.Ocupada, mesaPc.Estado);

        var pedidoPc = await pc.Mesas.ObtenerPedidoAsync(pedido.Id);
        Assert.NotNull(pedidoPc);
        Assert.Equal("Luis", pedidoPc!.Mozo);
        // La línea anidada en el snapshot del pedido también se aplicó.
        Assert.Single(pedidoPc.Lineas);
        Assert.Equal("Pollo a la brasa 1/4", pedidoPc.Lineas[0].Descripcion);

        var habPc = await pc.Hotel.ObtenerHabitacionAsync(habitacion.Id);
        Assert.NotNull(habPc);
        Assert.Equal(TipoHabitacion.Matrimonial, habPc!.Tipo);

        var estPc = await pc.Hotel.ObtenerEstadiaAsync(estadia.Id);
        Assert.NotNull(estPc);
        Assert.Equal("Ana Quispe", estPc!.HuespedNombre);
        // Los consumos NO se sincronizan sueltos: viajan aquí consolidados.
        Assert.Equal(12.50m, estPc.MontoConsumos);
    }

    /// <summary>
    /// `pedido_linea` también llega como entidad suelta (así la emite el móvil
    /// cuando el mozo agrega un plato a una comanda que ya existía) y es MUTABLE:
    /// corregir la cantidad antes de mandar a cocina debe pisar la línea.
    /// </summary>
    [Fact]
    public async Task Catalogo_PedidoLineaSuelta_SeAplicaYEsMutable()
    {
        using var pc = new Nodo();
        var t = DateTime.UtcNow;

        var mesa = new Mesa
        {
            Id = Guid.NewGuid(), Numero = "3", Capacidad = 4, Activa = true,
            OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };
        var pedido = new Pedido
        {
            Id = Guid.NewGuid(), MesaId = mesa.Id, NumeroMesa = "3", Numero = "M01-P-0002",
            Mozo = "Luis", FechaApertura = DateTime.Now, OrigenCajaId = "M01",
            CreadoUtc = t, ActualizadoUtc = t
        };
        var linea = new PedidoLinea
        {
            Id = Guid.NewGuid(), PedidoId = pedido.Id, Descripcion = "Chicha morada",
            Cantidad = 1m, PrecioUnitario = 5m, Importe = 5m,
            OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        };

        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("mesa", mesa.Id, "UPSERT", JsonSerializer.Serialize(mesa), t, "M01"),
            new CambioRemoto("pedido", pedido.Id, "UPSERT", JsonSerializer.Serialize(pedido), t, "M01"),
            new CambioRemoto("pedido_linea", linea.Id, "UPSERT", JsonSerializer.Serialize(linea), t, "M01")
        });

        var lineas = await pc.Mesas.ListarLineasAsync(pedido.Id);
        Assert.Single(lineas);
        Assert.Equal(1m, lineas[0].Cantidad);

        // El mozo corrige a 3 en el móvil: el evento más nuevo pisa la línea.
        var t2 = t.AddMinutes(2);
        linea.Cantidad = 3m;
        linea.Importe = 15m;
        linea.ActualizadoUtc = t2;
        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("pedido_linea", linea.Id, "UPSERT", JsonSerializer.Serialize(linea), t2, "M01")
        });

        lineas = await pc.Mesas.ListarLineasAsync(pedido.Id);
        Assert.Single(lineas);
        Assert.Equal(3m, lineas[0].Cantidad);
    }

    [Fact]
    public async Task Catalogo_EntidadFueraDelCatalogo_SeIgnoraSinRomperElLote()
    {
        using var pc = new Nodo();
        var t = DateTime.UtcNow;
        var id = Guid.NewGuid();

        // Un backend/móvil más nuevo puede emitir entidades que esta versión no
        // conoce. No deben tumbar el ciclo de sync: se ignoran y ya.
        var aplicados = await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("proveedor", id, "UPSERT", "{\"Id\":\"" + id + "\"}", t, "M01"),
            new CambioRemoto("consumos_habitacion", Guid.NewGuid(), "INSERT", "{}", t, "M01"),
            new CambioRemoto("entidad_del_futuro", Guid.NewGuid(), "UPSERT", "{}", t, "M01")
        });

        Assert.Equal(0, aplicados);
    }

    // =========================================================================
    //  CONTRATO DEL PAYLOAD: PascalCase, case-SENSITIVE
    // =========================================================================

    /// <summary>
    /// Lo que la PC EMITE al outbox va en PascalCase (opciones por defecto de
    /// System.Text.Json, sin naming policy). El móvil se apoya en esto para
    /// serializar igual, así que si alguien cambia OutboxHelper a
    /// JsonSerializerDefaults.Web este test debe caerse.
    /// </summary>
    [Fact]
    public async Task Payload_QueEmiteLaPc_EsPascalCase()
    {
        using var pc = new Nodo();
        await pc.Productos.GuardarAsync(NuevoProducto("7503", "Leche Gloria", "C01"));

        var payload = (await pc.Outbox.LeerPendientesAsync(1))[0].PayloadJson;

        Assert.Contains("\"Nombre\":", payload);
        Assert.Contains("\"StockActual\":", payload);
        Assert.Contains("\"PrecioVenta\":", payload);
        Assert.DoesNotContain("\"nombre\":", payload);
        Assert.DoesNotContain("\"stockActual\":", payload);
    }

    /// <summary>
    /// Y lo que la PC LEE es case-SENSITIVE: un payload en camelCase no se
    /// entiende. No es un capricho — es justamente por esto que el móvil emite en
    /// PascalCase. Si la PC pasara a deserializar con
    /// <c>JsonSerializerDefaults.Web</c> (camelCase + insensible a mayúsculas)
    /// este test seguiría pasando, pero el móvil se rompería en silencio; y al
    /// revés, si alguien "arreglara" el móvil a camelCase, la PC construiría
    /// entidades vacías (ventas de S/ 0) que además pisarían las buenas por LWW.
    ///
    /// Se prueba con `caja` porque su tabla no tiene claves foráneas: el fallo se
    /// ve como "la fila esperada no existe", sin ruido de integridad referencial.
    /// </summary>
    [Fact]
    public async Task Payload_EnCamelCase_NoSeAplica_ElContratoEsPascalCase()
    {
        using var pc = new Nodo();
        var id = Guid.NewGuid();
        var t = DateTime.UtcNow;
        var iso = t.ToString("o");

        var camel = $$"""
            {"id":"{{id}}","nombre":"Caja Móvil","cajero":"Ana","estado":0,
             "montoApertura":250.0,"fechaApertura":"{{iso}}","origenCajaId":"M01",
             "creadoUtc":"{{iso}}","actualizadoUtc":"{{iso}}"}
            """;

        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("caja", id, "UPSERT", camel, t, "M01")
        });

        // Ni siquiera el Id se leyó: la caja esperada no existe.
        Assert.Null(await pc.Cajas.ObtenerPorIdAsync(id));

        // El MISMO contenido en PascalCase sí entra, con sus montos correctos.
        var pascal = JsonSerializer.Serialize(new Caja
        {
            Id = id, Nombre = "Caja Móvil", Cajero = "Ana", MontoApertura = 250m,
            FechaApertura = t, OrigenCajaId = "M01", CreadoUtc = t, ActualizadoUtc = t
        });

        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("caja", id, "UPSERT", pascal, t.AddMinutes(1), "M01")
        });

        var cajaPc = await pc.Cajas.ObtenerPorIdAsync(id);
        Assert.NotNull(cajaPc);
        Assert.Equal("Caja Móvil", cajaPc!.Nombre);
        Assert.Equal(250m, cajaPc.MontoApertura);
    }

    /// <summary>
    /// Los dos payloads que SÍ van en minúsculas y así se quedan, porque el
    /// escritorio los emite con tipos anónimos: anulación de venta
    /// (<c>{id, estado}</c>) y baja de producto (<c>{id}</c>). Se leen con
    /// JsonDocument por nombre exacto, no con el deserializador de entidades.
    /// </summary>
    [Fact]
    public async Task Payload_AnulacionYBaja_SiguenEnMinusculas()
    {
        using var pc = new Nodo();

        // --- Baja de producto: {"id": "..."} en minúsculas ---
        var prod = NuevoProducto("7504", "Pan francés", "C01");
        await pc.Productos.GuardarAsync(prod);

        var tBaja = DateTime.UtcNow.AddMinutes(1);
        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("producto", prod.Id, "DELETE",
                $"{{\"id\":\"{prod.Id}\"}}", tBaja, "M01")
        });
        Assert.False((await pc.Productos.ObtenerPorIdAsync(prod.Id))!.Activo);

        // --- Anulación de venta: {"id": "...", "estado": 1} en minúsculas ---
        var sesion = new Caja { Nombre = "Caja 1", Cajero = "Tester", OrigenCajaId = "C01" };
        await pc.Cajas.AbrirCajaAsync(sesion);

        var venta = new Venta
        {
            Numero = "C01-000002", CajaId = sesion.Id, FechaHora = DateTime.Now,
            MetodoPago = MetodoPago.Efectivo, Estado = EstadoVenta.Completada,
            SubTotal = 10m, Igv = 1.80m, Total = 11.80m, OrigenCajaId = "C01"
        };
        venta.Detalles.Add(new DetalleVenta
        {
            ProductoId = prod.Id, DescripcionProducto = prod.Nombre,
            Cantidad = 1, PrecioUnitario = 11.80m, Importe = 11.80m, OrigenCajaId = "C01"
        });
        await pc.Ventas.RegistrarAsync(venta);

        var tAnul = DateTime.UtcNow.AddMinutes(2);
        await pc.Outbox.AplicarCambiosRemotosAsync(new[]
        {
            new CambioRemoto("venta", venta.Id, "UPDATE",
                $"{{\"id\":\"{venta.Id}\",\"estado\":{(int)EstadoVenta.Anulada}}}", tAnul, "M01")
        });

        Assert.Equal(EstadoVenta.Anulada, (await pc.Ventas.ObtenerPorIdAsync(venta.Id))!.Estado);
    }
}
