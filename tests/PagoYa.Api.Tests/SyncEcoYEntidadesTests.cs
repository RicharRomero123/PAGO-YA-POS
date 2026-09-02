using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Servicios;
using Xunit;

namespace PagoYa.Api.Tests;

/// <summary>
/// Dos garantías del pull multi-dispositivo:
///
/// 1. <b>Filtro de eco</b>: un dispositivo nunca se descarga sus propios eventos.
///    Con una sola caja era inofensivo (LWW idempotente); con PC + móvil es
///    tráfico duplicado y riesgo de que un snapshot viejo pise uno más nuevo.
/// 2. <b>Catálogo de entidades</b>: el server entiende las comandas del móvil
///    (mesa, pedido, pedido_linea) además de las cinco originales.
/// </summary>
public sealed class SyncEcoYEntidadesTests
{
    private const string OrigenPc = "C01";
    private const string OrigenMovil = "M01";

    private static EventoSyncDto Evento(string entidad, string origen) => new()
    {
        Id = Guid.NewGuid(),
        Entidad = entidad,
        EntidadId = Guid.NewGuid(),
        Operacion = "UPSERT",
        PayloadJson = $$"""{"Nombre":"X","ActualizadoUtc":"{{DateTime.UtcNow:o}}"}""",
        OrigenCajaId = origen,
        CreadoUtc = DateTime.UtcNow
    };

    private static SyncPushRequest Lote(params EventoSyncDto[] eventos) =>
        new() { Eventos = eventos.ToList() };

    // ---------------------------------------------------- Filtro de eco ----

    [Fact]
    public async Task Pull_NoDevuelveLosEventosDelPropioOrigen()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();

        await e.ServicioSync.ProcesarPushAsync(lic, Lote(
            Evento("venta", OrigenPc),
            Evento("pedido", OrigenMovil),
            Evento("venta", OrigenPc)), default);

        // El móvil solo debe recibir lo que subió la PC.
        var pullMovil = await e.ServicioSync.ObtenerCambiosAsync(lic, null, OrigenMovil, default);
        Assert.Equal(2, pullMovil.Cambios.Count);
        Assert.All(pullMovil.Cambios, c => Assert.Equal(OrigenPc, c.OrigenCajaId));

        // Y la PC solo lo que subió el móvil.
        var pullPc = await e.ServicioSync.ObtenerCambiosAsync(lic, null, OrigenPc, default);
        Assert.Single(pullPc.Cambios);
        Assert.Equal(OrigenMovil, pullPc.Cambios[0].OrigenCajaId);
    }

    [Fact]
    public async Task Pull_ComparaElOrigenSinDistinguirMayusculas()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("venta", "m01")), default);

        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, null, "M01", default);

        Assert.Empty(pull.Cambios);
    }

    [Fact]
    public async Task Pull_SinOrigen_DevuelveTodo_CompatibilidadConClientesViejos()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(
            Evento("venta", OrigenPc),
            Evento("pedido", OrigenMovil)), default);

        // El cliente de escritorio en campo aún no manda ?origen=: no debe cambiar
        // nada para él (sigue recibiendo todo y resolviendo por LWW).
        var sinParametro = await e.ServicioSync.ObtenerCambiosAsync(lic, null, default);
        Assert.Equal(2, sinParametro.Cambios.Count);

        var vacio = await e.ServicioSync.ObtenerCambiosAsync(lic, null, "  ", default);
        Assert.Equal(2, vacio.Cambios.Count);
    }

    [Fact]
    public async Task Pull_AvanzaElCursor_AunqueTodaLaVentanaSeaPropia()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(
            Evento("venta", OrigenPc),
            Evento("venta", OrigenPc)), default);

        // Nada que aplicar, pero el cursor debe avanzar: si no, cada pull volvería
        // a escanear los mismos eventos propios para siempre.
        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, null, OrigenPc, default);
        Assert.Empty(pull.Cambios);
        Assert.Equal("2", pull.Cursor);

        // Y desde ese cursor, un evento ajeno posterior sí llega.
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("pedido", OrigenMovil)), default);
        var siguiente = await e.ServicioSync.ObtenerCambiosAsync(lic, pull.Cursor, OrigenPc, default);
        Assert.Single(siguiente.Cambios);
        Assert.Equal("3", siguiente.Cursor);
    }

    [Fact]
    public async Task Pull_ElFiltroDeEcoNoRompeElAislamientoPorLicencia()
    {
        using var e = new EntornoLicencias();
        var licA = Guid.NewGuid();
        var licB = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(licA, Lote(Evento("venta", OrigenPc)), default);

        var pullB = await e.ServicioSync.ObtenerCambiosAsync(licB, null, OrigenMovil, default);

        Assert.Empty(pullB.Cambios);
    }

    // ------------------------------------------------ Cursor adelantado ----

    [Fact]
    public async Task Pull_CursorPorDelanteDeLaSecuencia_SeAcotaAlMaximoReal()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(
            Evento("venta", OrigenPc),
            Evento("venta", OrigenPc)), default);

        // Cursor corrupto hacia adelante (BD restaurada, tenant equivocado...).
        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, "999", OrigenMovil, default);

        // Se devuelve el máximo REAL: si repitiéramos "999", ese dispositivo se
        // quedaría clavado ahí para siempre y no podría repararse solo.
        Assert.Equal("2", pull.Cursor);
        Assert.Empty(pull.Cambios);
    }

    [Fact]
    public async Task Pull_TrasAcotarElCursor_ElDispositivoVuelveARecibirCambios()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("venta", OrigenPc)), default);

        var reparado = await e.ServicioSync.ObtenerCambiosAsync(lic, "999", OrigenMovil, default);
        Assert.Equal("1", reparado.Cursor);

        // Con el cursor ya reparado, lo nuevo llega con normalidad.
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("pedido", OrigenPc)), default);
        var siguiente = await e.ServicioSync.ObtenerCambiosAsync(lic, reparado.Cursor, OrigenMovil, default);

        Assert.Single(siguiente.Cambios);
        Assert.Equal("2", siguiente.Cursor);
    }

    [Fact]
    public async Task Pull_CursorAdelantado_NoReenviaElHistorico()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(
            Evento("venta", OrigenPc),
            Evento("venta", OrigenPc)), default);

        // Acotar NO es reiniciar: nadie quiere que un cursor corrupto dispare la
        // re-descarga de todo el histórico del negocio.
        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, "999", OrigenMovil, default);

        Assert.Empty(pull.Cambios);
    }

    [Fact]
    public async Task Pull_LicenciaSinEventos_ConCursorAdelantado_VuelveACero()
    {
        using var e = new EntornoLicencias();

        var pull = await e.ServicioSync.ObtenerCambiosAsync(Guid.NewGuid(), "999", OrigenMovil, default);

        Assert.Equal("0", pull.Cursor);
        Assert.Empty(pull.Cambios);
    }

    [Fact]
    public async Task Pull_CursorNoNumericoONegativo_SeTrataComoCero()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("venta", OrigenPc)), default);

        foreach (var basura in new[] { "abc", "", "-5" })
        {
            var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, basura, OrigenMovil, default);
            Assert.Single(pull.Cambios);
            Assert.Equal("1", pull.Cursor);
        }
    }

    // ------------------------------------------- Entidades sincronizadas ----

    [Fact]
    public void Catalogo_ContieneLasCincoOriginalesYLasDeComandas()
    {
        Assert.Contains("producto", EntidadesSync.Catalogo);
        Assert.Contains("venta", EntidadesSync.Catalogo);
        Assert.Contains("caja", EntidadesSync.Catalogo);
        Assert.Contains("movimiento_caja", EntidadesSync.Catalogo);
        Assert.Contains("inventario", EntidadesSync.Catalogo);

        // Lo que el móvil necesita para el mozo tomando comandas.
        Assert.Contains("mesa", EntidadesSync.Catalogo);
        Assert.Contains("pedido", EntidadesSync.Catalogo);
        Assert.Contains("pedido_linea", EntidadesSync.Catalogo);

        // Rubro hotel: el desktop ya las emitía al outbox.
        Assert.Contains("habitacion", EntidadesSync.Catalogo);
        Assert.Contains("estadia_habitacion", EntidadesSync.Catalogo);
    }

    [Theory]
    [InlineData("mesa")]
    [InlineData("pedido")]
    [InlineData("pedido_linea")]
    public async Task Push_AceptaLasEntidadesDeComandas_SinReportarlasComoDesconocidas(string entidad)
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();

        var resp = await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento(entidad, OrigenMovil)), default);

        Assert.Single(resp.Aceptados);
        Assert.Empty(resp.EntidadesDesconocidas);

        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, null, OrigenPc, default);
        Assert.Single(pull.Cambios);
        Assert.Equal(entidad, pull.Cambios[0].Entidad);
    }

    [Fact]
    public async Task Push_EntidadFueraDelCatalogo_SeAlmacenaIgual_PeroSeReporta()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();

        var resp = await e.ServicioSync.ProcesarPushAsync(lic, Lote(Evento("teletransporte", OrigenMovil)), default);

        // No se descarta (perder datos del cliente sería peor)...
        Assert.Single(resp.Aceptados);
        Assert.Equal(1, await e.Db.EventosSync.CountAsync());
        // ...pero se reporta para detectar desalineación de contrato.
        Assert.Contains("teletransporte", resp.EntidadesDesconocidas);
    }
}
