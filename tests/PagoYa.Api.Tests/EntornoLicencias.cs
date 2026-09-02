using System.Security.Cryptography;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using PagoYa.Api.Datos;
using PagoYa.Api.Firma;
using PagoYa.Api.Servicios;
using PagoYa.Core.Contratos;
using PagoYa.Licensing;

namespace PagoYa.Api.Tests;

/// <summary>
/// Entorno hermético para los tests: BD SQLite en memoria + un par de claves
/// RSA-2048 recién generado. El server firma con la privada; el validador del
/// cliente verifica con la pública correspondiente. Al generar el par al vuelo,
/// los tests NO dependen de la clave dev del repo ni de la embebida.
/// </summary>
public sealed class EntornoLicencias : IDisposable
{
    private readonly SqliteConnection _conn;

    public LicenciasDbContext Db { get; }
    public ServicioLicencias Servicio { get; }
    public ServicioSync ServicioSync { get; }
    public VerificadorToken Verificador { get; }

    /// <summary>Clave pública (PEM) para construir el validador del cliente.</summary>
    public string PublicKeyPem { get; }

    public EntornoLicencias()
    {
        _conn = new SqliteConnection("DataSource=:memory:");
        _conn.Open(); // in-memory vive mientras la conexión esté abierta

        var opciones = new DbContextOptionsBuilder<LicenciasDbContext>()
            .UseSqlite(_conn)
            .Options;

        Db = new LicenciasDbContext(opciones);
        Db.Database.EnsureCreated();

        using var rsa = RSA.Create(2048);
        var privPem = rsa.ExportPkcs8PrivateKeyPem();
        PublicKeyPem = rsa.ExportSubjectPublicKeyInfoPem();

        var opcionesFirma = new OpcionesFirma { PrivateKeyPem = privPem };
        var emisor = new EmisorTokens(opcionesFirma);
        Servicio = new ServicioLicencias(Db, emisor, NullLogger<ServicioLicencias>.Instance);
        ServicioSync = new ServicioSync(Db, NullLogger<ServicioSync>.Instance);
        Verificador = new VerificadorToken(opcionesFirma);
    }

    /// <summary>Emite y activa una licencia Cloud, devolviendo (licenciaId, token firmado).</summary>
    public async Task<(Guid LicenciaId, string Token)> EmitirYActivarCloudAsync(string hwid)
    {
        var emision = await Servicio.EmitirAsync(
            new PagoYa.Api.Contratos.EmitirLicenciaRequest { Tier = "cloud" }, default);
        var activacion = await Servicio.ActivarAsync(
            new PagoYa.Api.Contratos.ActivarRequest { LicenseKey = emision.Valor!.ClaveLicencia, Hwid = hwid }, null, default);
        return (emision.Valor.LicenciaId, activacion.Valor!.Token);
    }

    /// <summary>Validador del cliente atado a la pública de este entorno.</summary>
    public LicenseTokenValidator CrearValidadorCliente() => new(PublicKeyPem);

    /// <summary>LicenseService del cliente con HWID y store simulados.</summary>
    public LicenseService CrearServicioCliente(string hwid, out StoreFake store)
    {
        store = new StoreFake();
        return new LicenseService(CrearValidadorCliente(), new HwidFake(hwid), store);
    }

    public void Dispose()
    {
        Db.Dispose();
        _conn.Dispose();
    }
}

/// <summary>HWID fijo para simular una máquina concreta en el cliente.</summary>
public sealed class HwidFake : IHardwareId
{
    private readonly string _hwid;
    public HwidFake(string hwid) => _hwid = hwid;
    public string ObtenerHwid() => _hwid;
}

/// <summary>Store de licencia en memoria para observar la persistencia del cliente.</summary>
public sealed class StoreFake : ILicenseStore
{
    public string? TokenGuardado { get; private set; }
    public string? LeerToken() => TokenGuardado;
    public void GuardarToken(string tokenFirmado) => TokenGuardado = tokenFirmado;
}
