using PagoYa.Api.Contratos;
using PagoYa.Core.Contratos;
using PagoYa.Core.Enums;
using Xunit;

namespace PagoYa.Api.Tests;

/// <summary>
/// Ciclo de vida del licenciamiento probado de punta a punta a nivel de servicio:
/// emisión → activación → token firmado → validación en el CLIENTE. Cada test
/// arma su propio <see cref="EntornoLicencias"/> (BD y claves aisladas).
/// </summary>
public sealed class FlujoLicenciasTests
{
    private const string Hwid = "CPU-ABC123.BOARD-XYZ789";

    // ------------------------------------------------------- Ciclo feliz ---

    [Fact]
    public async Task Emitir_Activar_Facturador_TokenValidaEnCliente()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest
        {
            Tier = "facturador",
            Ruc = "20512345678",
            DiasVigencia = 30,
            CanalVenta = "whatsapp"
        }, default);
        Assert.True(emision.Ok, emision.Error);

        var activacion = await e.Servicio.ActivarAsync(new ActivarRequest
        {
            LicenseKey = emision.Valor!.ClaveLicencia,
            Hwid = Hwid
        }, ip: "127.0.0.1", default);
        Assert.True(activacion.Ok, activacion.Error);

        // El validador del cliente acepta el token del server (contrato + firma).
        var validador = e.CrearValidadorCliente();
        var ok = validador.TryValidar(activacion.Valor!.Token, out var token, out var error);

        Assert.True(ok, error);
        Assert.NotNull(token);
        Assert.Equal("facturador", token!.Tier);
        Assert.Equal(Hwid, token.Hwid);
        Assert.Equal("20512345678", token.Sub);
        Assert.Contains("invoicing", token.Features);
        Assert.Contains("cloud_sync", token.Features);
        Assert.Contains("multi_site", token.Features);
        Assert.False(token.EsPerpetua);
        Assert.True(token.ExpiraUtc > DateTime.UtcNow);
    }

    [Fact]
    public async Task Cliente_ActivaLicencia_DesbloqueaFeatures_y_Persiste()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var activacion = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = Hwid }, null, default);

        // Cliente: mismo HWID que el vinculado por el server.
        var licenciaCliente = e.CrearServicioCliente(Hwid, out var store);
        var estado = licenciaCliente.ActivarLicencia(activacion.Valor!.Token);

        Assert.True(estado.EsValida);
        Assert.Equal(TierLicencia.Cloud, estado.Tier);
        Assert.True(estado.TieneCaracteristica(CaracteristicaLicencia.CloudSync));
        Assert.True(estado.TieneCaracteristica(CaracteristicaLicencia.MultiSite));
        Assert.False(estado.TieneCaracteristica(CaracteristicaLicencia.Invoicing));

        // Activación válida => el cliente PERSISTE el token para próximos arranques.
        Assert.Equal(activacion.Valor!.Token, store.TokenGuardado);
    }

    [Fact]
    public async Task Base_EsPerpetua_SinFeatures()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "base" }, default);
        Assert.Equal(0, emision.Valor!.ExpUnix);

        var activacion = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor.ClaveLicencia, Hwid = Hwid }, null, default);

        var validador = e.CrearValidadorCliente();
        Assert.True(validador.TryValidar(activacion.Valor!.Token, out var token, out _));
        Assert.Equal("base", token!.Tier);
        Assert.True(token.EsPerpetua);
        Assert.Empty(token.Features);
    }

    // --------------------------------------------------- Política de HWID ---

    [Fact]
    public async Task Cliente_RechazaTokenDeOtroEquipo()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var activacion = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = Hwid }, null, default);

        // Cliente en OTRA máquina: la firma es válida, pero el HWID no coincide.
        var licenciaCliente = e.CrearServicioCliente("OTRO-EQUIPO", out var store);
        var estado = licenciaCliente.ActivarLicencia(activacion.Valor!.Token);

        Assert.Equal(TierLicencia.Base, estado.Tier);
        Assert.Contains("otro equipo", estado.Motivo, StringComparison.OrdinalIgnoreCase);
        Assert.Null(store.TokenGuardado); // no se persiste una licencia ajena
    }

    [Fact]
    public async Task Validar_ConHwidDistinto_Rechaza_409()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var clave = emision.Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = Hwid }, null, default);

        var reval = await e.Servicio.ValidarAsync(
            new ValidarRequest { LicenseKey = clave, Hwid = "HWID-DISTINTO" }, null, default);

        Assert.False(reval.Ok);
        Assert.Equal(409, reval.Http);
    }

    [Fact]
    public async Task Traslados_ConsumeCupo_y_RechazaAlSuperarLimite()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(
            new EmitirLicenciaRequest { Tier = "cloud", MaxTraslados = 1 }, default);
        var clave = emision.Valor!.ClaveLicencia;

        // Equipo A: primer vínculo (no consume traslado).
        Assert.True((await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = "EQUIPO-A" }, null, default)).Ok);
        // Equipo B: traslado 1/1.
        Assert.True((await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = "EQUIPO-B" }, null, default)).Ok);
        // Equipo C: excede el límite → rechazo.
        var tercero = await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = "EQUIPO-C" }, null, default);

        Assert.False(tercero.Ok);
        Assert.Equal(409, tercero.Http);
    }

    [Fact]
    public async Task ReactivarMismoEquipo_NoConsumeTraslado()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(
            new EmitirLicenciaRequest { Tier = "cloud", MaxTraslados = 0 }, default);
        var clave = emision.Valor!.ClaveLicencia;

        Assert.True((await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = Hwid }, null, default)).Ok);
        // Reactivar en el MISMO equipo debe funcionar aun con MaxTraslados=0.
        Assert.True((await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = Hwid }, null, default)).Ok);
    }

    // ------------------------------------------------- Errores de emisión ---

    [Fact]
    public async Task Emitir_TierInvalido_400()
    {
        using var e = new EntornoLicencias();
        var r = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "premium" }, default);
        Assert.False(r.Ok);
        Assert.Equal(400, r.Http);
    }

    [Fact]
    public async Task Emitir_FeatureInvalido_400()
    {
        using var e = new EntornoLicencias();
        var r = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest
        {
            Tier = "cloud",
            Features = new[] { "cloud_sync", "teletransporte" }
        }, default);
        Assert.False(r.Ok);
        Assert.Equal(400, r.Http);
    }

    [Fact]
    public async Task Activar_ClaveInexistente_404()
    {
        using var e = new EntornoLicencias();
        var r = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = "PAGOYA-XXXX-YYYY-ZZZZ-WWWW", Hwid = Hwid }, null, default);
        Assert.False(r.Ok);
        Assert.Equal(404, r.Http);
    }

    // ------------------------------------------------ Integridad de firma ---

    [Fact]
    public async Task TokenManipulado_FirmaInvalida_EsRechazado()
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "facturador" }, default);
        var activacion = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = Hwid }, null, default);

        // Alteramos un carácter del payload: la firma deja de cuadrar.
        var token = activacion.Valor!.Token;
        var partes = token.Split('.');
        var payload = partes[0];
        var idx = payload.Length / 2;
        var alterado = payload[idx] == 'A' ? 'B' : 'A';
        var payloadMalo = payload[..idx] + alterado + payload[(idx + 1)..];
        var tokenManipulado = $"{payloadMalo}.{partes[1]}";

        var validador = e.CrearValidadorCliente();
        Assert.False(validador.TryValidar(tokenManipulado, out _, out _));
    }
}
