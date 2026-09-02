using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using Xunit;

namespace PagoYa.Api.Tests;

/// <summary>
/// Los códigos de error son un CONTRATO machine-readable: el cliente ramifica por
/// <c>ErrorResponse.Codigo</c>, nunca por subcadenas del mensaje (que se reescribe
/// o se traduce). Estos tests fijan tanto los valores publicados como el código que
/// devuelve cada camino de fallo.
/// </summary>
public sealed class CodigosErrorTests
{
    private const string HwidPc = "CPU-ABC123.BOARD-XYZ789";

    // ------------------------------------ Valores publicados (no cambian) ---

    [Fact]
    public void ValoresPublicados_NoCambian()
    {
        // Renombrar cualquiera de estas cadenas rompe a los clientes en campo.
        // Los dos primeros separan dos caminos de usuario muy distintos:
        // upsell al tier Cloud vs. "vuelve a vincular este equipo".
        Assert.Equal("sin_flag_cloud_sync", CodigosError.SinFlagCloudSync);
        Assert.Equal("asiento_revocado", CodigosError.AsientoRevocado);

        Assert.Equal("cupo_dispositivos_lleno", CodigosError.CupoDispositivosLleno);
        Assert.Equal("licencia_suspendida", CodigosError.LicenciaSuspendida);
        Assert.Equal("licencia_revocada", CodigosError.LicenciaRevocada);
        Assert.Equal("clave_no_encontrada", CodigosError.ClaveNoEncontrada);
        Assert.Equal("limite_traslados", CodigosError.LimiteTraslados);
        Assert.Equal("hwid_no_coincide", CodigosError.HwidNoCoincide);
        Assert.Equal("dispositivo_ya_es_principal", CodigosError.DispositivoYaEsPrincipal);
        Assert.Equal("principal_no_revocable", CodigosError.PrincipalNoRevocable);
        Assert.Equal("token_expirado", CodigosError.TokenExpirado);
        Assert.Equal("token_invalido", CodigosError.TokenInvalido);
    }

    // ------------------------------------------ Serialización (aditiva) ----

    [Fact]
    public void ErrorResponse_SerializaCodigo_yLoOmiteCuandoEsNull()
    {
        var opts = new JsonSerializerOptions(JsonSerializerDefaults.Web);

        var conCodigo = JsonSerializer.Serialize(
            new ErrorResponse("Cupo lleno.", CodigosError.CupoDispositivosLleno), opts);
        Assert.Contains("\"codigo\":\"cupo_dispositivos_lleno\"", conCodigo);
        Assert.Contains("\"error\":", conCodigo);

        // Aditivo: un error sin clasificar no ensucia el JSON de los clientes
        // que solo leían "error".
        var sinCodigo = JsonSerializer.Serialize(new ErrorResponse("Algo falló."), opts);
        Assert.DoesNotContain("codigo", sinCodigo);
    }

    // --------------------------------------------- Códigos por operación ---

    [Fact]
    public async Task ClaveInexistente_DevuelveClaveNoEncontrada()
    {
        using var e = new EntornoLicencias();

        var r = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = "PAGOYA-XXXX-YYYY-ZZZZ-WWWW", Hwid = HwidPc }, null, default);

        Assert.Equal(404, r.Http);
        Assert.Equal(CodigosError.ClaveNoEncontrada, r.Codigo);
    }

    [Fact]
    public async Task LicenciaSuspendida_DevuelveLicenciaSuspendida()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var lic = await e.Db.Licencias.SingleAsync();
        lic.Estado = PagoYa.Api.Dominio.EstadoLicencia.Suspendida;
        await e.Db.SaveChangesAsync();

        var r = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = HwidPc }, null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.LicenciaSuspendida, r.Codigo);
    }

    [Fact]
    public async Task LimiteDeTraslados_DevuelveLimiteTraslados()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(
            new EmitirLicenciaRequest { Tier = "cloud", MaxTraslados = 0 }, default);
        var clave = emision.Valor!.ClaveLicencia;

        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = "EQUIPO-A" }, null, default);
        var r = await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = "EQUIPO-B" }, null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.LimiteTraslados, r.Codigo);
    }

    [Fact]
    public async Task ValidarConOtroHwid_DevuelveHwidNoCoincide()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var clave = emision.Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await e.Servicio.ValidarAsync(
            new ValidarRequest { LicenseKey = clave, Hwid = "OTRO" }, null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.HwidNoCoincide, r.Codigo);
    }

    [Fact]
    public async Task CupoDeAsientosLleno_DevuelveCupoDispositivosLleno()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(
            new EmitirLicenciaRequest { Tier = "cloud", MaxDispositivos = 1 }, default);
        var clave = emision.Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await e.Servicio.VincularDispositivoAsync(
            new VincularDispositivoRequest { LicenseKey = clave, DeviceId = "movil-1", Plataforma = "android" },
            null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.CupoDispositivosLleno, r.Codigo);
    }

    [Fact]
    public async Task VincularElEquipoPrincipal_DevuelveDispositivoYaEsPrincipal()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var clave = emision.Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await e.Servicio.VincularDispositivoAsync(
            new VincularDispositivoRequest { LicenseKey = clave, DeviceId = HwidPc }, null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.DispositivoYaEsPrincipal, r.Codigo);
    }

    [Fact]
    public async Task RevocarElPrincipal_DevuelvePrincipalNoRevocable()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var clave = emision.Valor!.ClaveLicencia;
        var pc = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await e.Servicio.RevocarDispositivoAsync(
            pc.Valor!.DeviceId!.Value, clave, esAdmin: false, null, default);

        Assert.Equal(409, r.Http);
        Assert.Equal(CodigosError.PrincipalNoRevocable, r.Codigo);
    }

    [Fact]
    public async Task RevocarSinCredenciales_yConClaveAjena_TienenCodigosDistintos()
    {
        using var e = new EntornoLicencias();
        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var clave = emision.Valor!.ClaveLicencia;
        var seat = await e.Servicio.VincularDispositivoAsync(
            new VincularDispositivoRequest { LicenseKey = clave, DeviceId = "movil-1" }, null, default);
        var id = seat.Valor!.DeviceId!.Value;

        var sinNada = await e.Servicio.RevocarDispositivoAsync(id, null, false, null, default);
        Assert.Equal(CodigosError.CredencialesRequeridas, sinNada.Codigo);

        var ajena = await e.Servicio.RevocarDispositivoAsync(
            id, "PAGOYA-XXXX-YYYY-ZZZZ-WWWW", false, null, default);
        Assert.Equal(CodigosError.ClaveNoCorresponde, ajena.Codigo);
    }

    [Fact]
    public async Task EmisionInvalida_DistingueTierDeFeature()
    {
        using var e = new EntornoLicencias();

        var tier = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "premium" }, default);
        Assert.Equal(CodigosError.TierInvalido, tier.Codigo);

        var feature = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest
        {
            Tier = "cloud",
            Features = new[] { "teletransporte" }
        }, default);
        Assert.Equal(CodigosError.FeatureInvalido, feature.Codigo);
    }

    // ------------------------------------------------ Códigos del token ----

    [Fact]
    public async Task TokenExpirado_yTokenManipulado_TienenCodigosDistintos()
    {
        using var e = new EntornoLicencias();

        // Licencia ya vencida: el token sale con exp en el pasado.
        var vencida = await e.Servicio.EmitirAsync(
            new EmitirLicenciaRequest { Tier = "cloud", DiasVigencia = -1 }, default);
        var actVencida = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = vencida.Valor!.ClaveLicencia, Hwid = HwidPc }, null, default);

        Assert.False(e.Verificador.TryVerificar(actVencida.Valor!.Token, out _, out _, out var codigoExp));
        Assert.Equal(CodigosError.TokenExpirado, codigoExp);

        // Token con la firma rota: es otro problema y otro camino de usuario.
        var viva = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = "cloud" }, default);
        var actViva = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = viva.Valor!.ClaveLicencia, Hwid = HwidPc }, null, default);

        var partes = actViva.Valor!.Token.Split('.');
        var i = partes[0].Length / 2;
        var alterado = partes[0][i] == 'A' ? 'B' : 'A';
        var manipulado = $"{partes[0][..i]}{alterado}{partes[0][(i + 1)..]}.{partes[1]}";

        Assert.False(e.Verificador.TryVerificar(manipulado, out _, out _, out var codigoMal));
        Assert.Equal(CodigosError.TokenInvalido, codigoMal);
    }

    [Fact]
    public void TokenAusente_DevuelveTokenAusente()
    {
        using var e = new EntornoLicencias();

        Assert.False(e.Verificador.TryVerificar("", out _, out _, out var codigo));
        Assert.Equal(CodigosError.TokenAusente, codigo);
    }
}
