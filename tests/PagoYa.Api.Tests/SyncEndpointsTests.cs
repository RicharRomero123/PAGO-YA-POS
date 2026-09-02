using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Firma;
using Xunit;

namespace PagoYa.Api.Tests;

/// <summary>
/// Lógica de los endpoints /sync: push idempotente por licencia, pull por cursor
/// con aislamiento de tenant, y autenticación por token de licencia Cloud.
/// </summary>
public sealed class SyncEndpointsTests
{
    private static EventoSyncDto Evento(string entidad, DateTime actualizado, string origen = "cajaA")
    {
        var id = Guid.NewGuid();
        var payload = $$"""{"Nombre":"Producto","ActualizadoUtc":"{{actualizado:o}}"}""";
        return new EventoSyncDto
        {
            Id = id, Entidad = entidad, EntidadId = Guid.NewGuid(), Operacion = "UPSERT",
            PayloadJson = payload, OrigenCajaId = origen, CreadoUtc = DateTime.UtcNow
        };
    }

    // --------------------------------------------------------------- Push ---

    [Fact]
    public async Task Push_GuardaEventos_yEsIdempotente()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        var req = new SyncPushRequest { Eventos = { Evento("producto", DateTime.UtcNow), Evento("venta", DateTime.UtcNow) } };

        var r1 = await e.ServicioSync.ProcesarPushAsync(lic, req, default);
        Assert.Equal(2, r1.Aceptados.Count);
        Assert.Equal(2, await e.Db.EventosSync.CountAsync());

        // Reenviar el MISMO lote: acepta todo pero no duplica.
        var r2 = await e.ServicioSync.ProcesarPushAsync(lic, req, default);
        Assert.Equal(2, r2.Aceptados.Count);
        Assert.Equal(2, await e.Db.EventosSync.CountAsync());
    }

    // --------------------------------------------------------------- Pull ---

    [Fact]
    public async Task Pull_DevuelveCambios_yAvanzaCursor()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        await e.ServicioSync.ProcesarPushAsync(lic,
            new SyncPushRequest { Eventos = { Evento("producto", DateTime.UtcNow), Evento("producto", DateTime.UtcNow) } }, default);

        var pull1 = await e.ServicioSync.ObtenerCambiosAsync(lic, cursor: null, default);
        Assert.Equal(2, pull1.Cambios.Count);
        Assert.Equal("2", pull1.Cursor);

        // Con el cursor devuelto ya no hay nada nuevo.
        var pull2 = await e.ServicioSync.ObtenerCambiosAsync(lic, pull1.Cursor, default);
        Assert.Empty(pull2.Cambios);
        Assert.Equal("2", pull2.Cursor);
    }

    [Fact]
    public async Task Pull_ExtraeActualizadoUtcDelPayload_ParaLwww()
    {
        using var e = new EntornoLicencias();
        var lic = Guid.NewGuid();
        var marca = new DateTime(2026, 8, 26, 10, 0, 0, DateTimeKind.Utc);

        await e.ServicioSync.ProcesarPushAsync(lic,
            new SyncPushRequest { Eventos = { Evento("producto", marca) } }, default);

        var pull = await e.ServicioSync.ObtenerCambiosAsync(lic, null, default);
        Assert.Single(pull.Cambios);
        Assert.Equal(marca.Ticks, pull.Cambios[0].ActualizadoUtc.Ticks);
    }

    [Fact]
    public async Task Pull_AislaPorLicencia()
    {
        using var e = new EntornoLicencias();
        var licA = Guid.NewGuid();
        var licB = Guid.NewGuid();

        await e.ServicioSync.ProcesarPushAsync(licA,
            new SyncPushRequest { Eventos = { Evento("producto", DateTime.UtcNow) } }, default);

        // Otra licencia (tenant) no ve los cambios de la primera.
        var pullB = await e.ServicioSync.ObtenerCambiosAsync(licB, null, default);
        Assert.Empty(pullB.Cambios);
    }

    // ------------------------------------------------------ Autenticación ---

    [Fact]
    public async Task Verificador_TokenCloud_ValidoConLicenseIdYFlag()
    {
        using var e = new EntornoLicencias();
        var (licenciaId, token) = await e.EmitirYActivarCloudAsync("HWID-CAJA-1");

        Assert.True(e.Verificador.TryVerificar(token, out var payload, out var error), error);
        Assert.NotNull(payload);
        Assert.Equal(licenciaId.ToString(), payload!.LicenseId);
        Assert.True(VerificadorToken.ExigeFeature(payload, "cloud_sync"));
    }

    [Fact]
    public async Task Verificador_TokenBase_NoTieneCloudSync()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "base" }, default);
        var act = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = "HW" }, null, default);

        Assert.True(e.Verificador.TryVerificar(act.Valor!.Token, out var payload, out _));
        Assert.False(VerificadorToken.ExigeFeature(payload!, "cloud_sync"));
    }

    [Fact]
    public async Task Verificador_TokenManipulado_Rechaza()
    {
        using var e = new EntornoLicencias();
        var (_, token) = await e.EmitirYActivarCloudAsync("HW");

        var partes = token.Split('.');
        var payload = partes[0];
        var i = payload.Length / 2;
        var alterado = payload[i] == 'A' ? 'B' : 'A';
        var manipulado = $"{payload[..i]}{alterado}{payload[(i + 1)..]}.{partes[1]}";

        Assert.False(e.Verificador.TryVerificar(manipulado, out _, out _));
    }
}
