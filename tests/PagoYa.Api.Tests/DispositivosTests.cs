using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Firma;
using PagoYa.Api.Servicios;
using PagoYa.Core.Contratos;
using Xunit;

// OJO: no se importa PagoYa.Api.Dominio — su enum EstadoLicencia chocaría con la
// clase EstadoLicencia del cliente (PagoYa.Core.Contratos). Se cualifica al usarlo.

namespace PagoYa.Api.Tests;

/// <summary>
/// Modelo de ASIENTOS (seats): <c>POST /devices</c> vincula dispositivos
/// secundarios (el móvil del mozo) sin desvincular la PC ni quemar traslados, y
/// <c>DELETE /devices/{id}</c> los revoca liberando cupo.
///
/// El invariante que protegen estos tests es el que motivó el modelo: <b>que el
/// celular jamás deje al cliente sin su caja</b>.
/// </summary>
public sealed class DispositivosTests
{
    private const string HwidPc = "CPU-ABC123.BOARD-XYZ789";
    private const string IdMovil = "android-id-9f3a";

    private static Task<Resultado<EmitirLicenciaResponse>> EmitirAsync(
        EntornoLicencias e, string tier = "cloud", int? maxDispositivos = null) =>
        e.Servicio.EmitirAsync(new EmitirLicenciaRequest
        {
            Tier = tier,
            MaxDispositivos = maxDispositivos
        }, default);

    private static Task<Resultado<TokenResponse>> VincularAsync(
        EntornoLicencias e, string clave, string deviceId,
        string plataforma = "android", string? nombre = null) =>
        e.Servicio.VincularDispositivoAsync(new VincularDispositivoRequest
        {
            LicenseKey = clave,
            DeviceId = deviceId,
            Plataforma = plataforma,
            Nombre = nombre
        }, ip: "127.0.0.1", default);

    // ------------------------------------- El móvil no desvincula la caja ---

    [Fact]
    public async Task Vincular_NoTocaHwidActual_NiConsumeTraslados()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await VincularAsync(e, clave, IdMovil, nombre: "Celular de Juan");

        Assert.True(r.Ok, r.Error);
        var lic = await e.Db.Licencias.Include(l => l.Dispositivos).SingleAsync();
        Assert.Equal(HwidPc, lic.HwidActual);        // la PC sigue vinculada
        Assert.Equal(0, lic.TrasladosUsados);        // no se quemó ningún cupo de traslado
        Assert.Equal(2, lic.Dispositivos.Count(d => d.Activo));
    }

    [Fact]
    public async Task Vincular_EmiteTokenQueValidaEnElDispositivoMovil()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await VincularAsync(e, clave, IdMovil);
        Assert.True(r.Ok, r.Error);

        // El claim hwid del token del asiento es el id del MÓVIL, no el de la PC:
        // el cliente móvil valida contra su propia huella.
        var validador = e.CrearValidadorCliente();
        Assert.True(validador.TryValidar(r.Valor!.Token, out var token, out var error), error);
        Assert.Equal(IdMovil, token!.Hwid);
        Assert.Contains("cloud_sync", token.Features);

        // Y el token del asiento trae los claims aditivos device_id / device_prefix.
        Assert.True(e.Verificador.TryVerificar(r.Valor.Token, out var payload, out _));
        Assert.Equal(r.Valor.DeviceId!.Value.ToString(), payload!.DeviceId);
        Assert.Equal("M01", payload.DevicePrefix);
        Assert.Equal("M01", r.Valor.DevicePrefix);
    }

    [Fact]
    public async Task Vincular_DesdeElEquipoPrincipal_Rechaza_409()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await VincularAsync(e, clave, HwidPc, plataforma: "windows");

        Assert.False(r.Ok);
        Assert.Equal(409, r.Http);
    }

    [Fact]
    public async Task Traslado_DeLaPc_NoRevocaLosAsientosMoviles()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);
        await VincularAsync(e, clave, IdMovil);

        // La caja se traslada a otra PC: el asiento del móvil debe sobrevivir.
        var traslado = await e.Servicio.ActivarAsync(
            new ActivarRequest { LicenseKey = clave, Hwid = "OTRA-PC" }, null, default);
        Assert.True(traslado.Ok, traslado.Error);

        var lic = await e.Db.Licencias.Include(l => l.Dispositivos).SingleAsync();
        var movil = lic.Dispositivos.Single(d => d.Hwid == IdMovil);
        Assert.True(movil.Activo);
        Assert.Equal("OTRA-PC", lic.HwidActual);
        Assert.False(lic.Dispositivos.Single(d => d.Hwid == HwidPc).Activo);
    }

    // ---------------------------------------------------- Cupo de asientos ---

    [Fact]
    public async Task Vincular_RespetaMaxDispositivos_409AlSuperarlo()
    {
        using var e = new EntornoLicencias();
        // Cupo 2 = la PC + un solo móvil.
        var clave = (await EmitirAsync(e, maxDispositivos: 2)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        Assert.True((await VincularAsync(e, clave, "movil-1")).Ok);

        var tercero = await VincularAsync(e, clave, "movil-2");
        Assert.False(tercero.Ok);
        Assert.Equal(409, tercero.Http);
    }

    [Fact]
    public async Task Base_NoAdmiteDispositivosSecundarios()
    {
        using var e = new EntornoLicencias();
        // Default por tier: base = 1 dispositivo (solo la caja).
        var clave = (await EmitirAsync(e, tier: "base")).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var r = await VincularAsync(e, clave, IdMovil);

        Assert.False(r.Ok);
        Assert.Equal(409, r.Http);
    }

    [Theory]
    [InlineData("base", 1)]
    [InlineData("cloud", 3)]
    [InlineData("facturador", 5)]
    public async Task DefaultsPorTier_Base1_Cloud3_Facturador5(string tier, int esperado)
    {
        using var e = new EntornoLicencias();

        var emision = await e.Servicio.EmitirAsync(new EmitirLicenciaRequest { Tier = tier }, default);
        var lic = await e.Db.Licencias.SingleAsync(l => l.Id == emision.Valor!.LicenciaId);

        Assert.Equal(esperado, lic.MaxDispositivos);
        Assert.Equal(esperado, lic.MaxDispositivosEfectivo);
    }

    [Fact]
    public async Task LicenciaLegacy_ConMaxDispositivosCero_UsaElDefaultDelTier()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;

        // Simula una licencia emitida ANTES del modelo de seats: la columna llega en 0.
        var lic = await e.Db.Licencias.SingleAsync();
        lic.MaxDispositivos = 0;
        await e.Db.SaveChangesAsync();

        Assert.Equal(3, lic.MaxDispositivosEfectivo); // default de cloud
        Assert.True((await VincularAsync(e, clave, IdMovil)).Ok);
    }

    [Fact]
    public async Task Vincular_MismoDispositivo_EsIdempotente_yNoConsumeOtroCupo()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e, maxDispositivos: 2)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var primera = await VincularAsync(e, clave, IdMovil);
        var segunda = await VincularAsync(e, clave, IdMovil);

        Assert.True(segunda.Ok, segunda.Error);
        Assert.Equal(primera.Valor!.DeviceId, segunda.Valor!.DeviceId);
        Assert.Equal("M01", segunda.Valor.DevicePrefix);
        Assert.Equal(2, await e.Db.Dispositivos.CountAsync(d => d.Activo));
    }

    // --------------------------------------------------------- Prefijos -----

    [Fact]
    public async Task Prefijos_PcEsC01_MovilesM01M02_ySonUnicos()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e, maxDispositivos: 5)).Valor!.ClaveLicencia;

        var pc = await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);
        var m1 = await VincularAsync(e, clave, "movil-1");
        var m2 = await VincularAsync(e, clave, "movil-2");

        Assert.Equal("C01", pc.Valor!.DevicePrefix);
        Assert.Equal("M01", m1.Valor!.DevicePrefix);
        Assert.Equal("M02", m2.Valor!.DevicePrefix);
    }

    [Fact]
    public async Task Prefijos_NoSeReutilizanTrasRevocar()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e, maxDispositivos: 5)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var m1 = await VincularAsync(e, clave, "movil-1");
        await VincularAsync(e, clave, "movil-2");
        await e.Servicio.RevocarDispositivoAsync(m1.Valor!.DeviceId!.Value, clave, esAdmin: false, null, default);

        // M01 quedó "quemado": sus correlativos ya existen en los tickets del negocio.
        var m3 = await VincularAsync(e, clave, "movil-3");
        Assert.Equal("M03", m3.Valor!.DevicePrefix);
    }

    // ------------------------------------------------------- Revocación -----

    [Fact]
    public async Task Revocar_LiberaCupo_yDesactivaElAsiento()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e, maxDispositivos: 2)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);
        var m1 = await VincularAsync(e, clave, "movil-1");

        // Sin revocar no entra un segundo móvil.
        Assert.False((await VincularAsync(e, clave, "movil-2")).Ok);

        var rev = await e.Servicio.RevocarDispositivoAsync(
            m1.Valor!.DeviceId!.Value, clave, esAdmin: false, ip: null, default);

        Assert.True(rev.Ok, rev.Error);
        Assert.True(rev.Valor!.Revocado);
        Assert.Equal(1, rev.Valor.DispositivosActivos);
        Assert.True((await VincularAsync(e, clave, "movil-2")).Ok);
    }

    [Fact]
    public async Task Revocar_ElPrincipal_NoSePermite_409()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        var pc = await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);

        var rev = await e.Servicio.RevocarDispositivoAsync(
            pc.Valor!.DeviceId!.Value, clave, esAdmin: true, null, default);

        Assert.False(rev.Ok);
        Assert.Equal(409, rev.Http);
    }

    [Fact]
    public async Task Revocar_SinCredenciales_401_yConClaveAjena_403()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);
        var m1 = await VincularAsync(e, clave, IdMovil);
        var id = m1.Valor!.DeviceId!.Value;

        var sinNada = await e.Servicio.RevocarDispositivoAsync(id, null, esAdmin: false, null, default);
        Assert.Equal(401, sinNada.Http);

        var ajena = await e.Servicio.RevocarDispositivoAsync(
            id, "PAGOYA-XXXX-YYYY-ZZZZ-WWWW", esAdmin: false, null, default);
        Assert.Equal(403, ajena.Http);

        Assert.True(await e.Db.Dispositivos.AnyAsync(d => d.Id == id && d.Activo));
    }

    [Fact]
    public async Task Revocar_ComoAdmin_SinClave_Funciona()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        await e.Servicio.ActivarAsync(new ActivarRequest { LicenseKey = clave, Hwid = HwidPc }, null, default);
        var m1 = await VincularAsync(e, clave, IdMovil);

        var rev = await e.Servicio.RevocarDispositivoAsync(
            m1.Valor!.DeviceId!.Value, claveLicencia: null, esAdmin: true, null, default);

        Assert.True(rev.Ok, rev.Error);
    }

    [Fact]
    public async Task Revocar_DosVeces_EsIdempotente()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        var m1 = await VincularAsync(e, clave, IdMovil);
        var id = m1.Valor!.DeviceId!.Value;

        Assert.True((await e.Servicio.RevocarDispositivoAsync(id, clave, false, null, default)).Ok);
        Assert.True((await e.Servicio.RevocarDispositivoAsync(id, clave, false, null, default)).Ok);
    }

    [Fact]
    public async Task AsientoRevocado_YaNoEsVigente_paraLosEndpointsOnline()
    {
        using var e = new EntornoLicencias();
        var emision = await EmitirAsync(e);
        var clave = emision.Valor!.ClaveLicencia;
        var licenciaId = emision.Valor.LicenciaId;
        var m1 = await VincularAsync(e, clave, IdMovil);
        var id = m1.Valor!.DeviceId!.Value;

        Assert.True(await e.Servicio.AsientoVigenteAsync(licenciaId, id, default));

        await e.Servicio.RevocarDispositivoAsync(id, clave, false, null, default);

        // El token sigue firmado y verificable (validación offline), pero el
        // asiento ya no es vigente: /sync lo rechaza con 403.
        Assert.True(e.Verificador.TryVerificar(m1.Valor.Token, out _, out _));
        Assert.False(await e.Servicio.AsientoVigenteAsync(licenciaId, id, default));
    }

    // --------------------------------------------------------- Auditoría ----

    [Fact]
    public async Task Vinculo_yRevocacion_QuedanEnActivationLogs()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        var m1 = await VincularAsync(e, clave, IdMovil);
        await e.Servicio.RevocarDispositivoAsync(m1.Valor!.DeviceId!.Value, clave, false, "10.0.0.5", default);

        var acciones = await e.Db.LogsActivacion.Select(l => l.Accion).ToListAsync();
        Assert.Contains("vinculo_dispositivo", acciones);
        Assert.Contains("revocacion_dispositivo", acciones);
    }

    [Fact]
    public async Task Vincular_LicenciaSuspendida_Rechaza_409()
    {
        using var e = new EntornoLicencias();
        var emision = await EmitirAsync(e);
        var lic = await e.Db.Licencias.SingleAsync();
        lic.Estado = PagoYa.Api.Dominio.EstadoLicencia.Suspendida;
        await e.Db.SaveChangesAsync();

        var r = await VincularAsync(e, emision.Valor!.ClaveLicencia, IdMovil);

        Assert.False(r.Ok);
        Assert.Equal(409, r.Http);
    }

    [Fact]
    public async Task Vincular_ClaveInexistente_404()
    {
        using var e = new EntornoLicencias();
        var r = await VincularAsync(e, "PAGOYA-XXXX-YYYY-ZZZZ-WWWW", IdMovil);
        Assert.False(r.Ok);
        Assert.Equal(404, r.Http);
    }

    // ------------------------------------------ Compatibilidad del token ----

    [Fact]
    public async Task TokenDeAsiento_LoAceptaElValidadorDelClienteEnCampo()
    {
        using var e = new EntornoLicencias();
        var clave = (await EmitirAsync(e)).Valor!.ClaveLicencia;
        var r = await VincularAsync(e, clave, IdMovil);

        // El cliente ya desplegado deserializa ignorando claims desconocidos:
        // los aditivos device_id/device_prefix no rompen su validación.
        var servicioCliente = e.CrearServicioCliente(IdMovil, out var store);
        var estado = servicioCliente.ActivarLicencia(r.Valor!.Token);

        Assert.True(estado.EsValida);
        Assert.True(estado.TieneCaracteristica(CaracteristicaLicencia.CloudSync));
        Assert.Equal(r.Valor.Token, store.TokenGuardado);
    }
}
