using System.IO;
using System.Security.Cryptography;
using System.Text;
using PagoYa.Licensing;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Implementación de <see cref="ILicenseStore"/> basada en archivo local,
/// <b>cifrado en reposo con DPAPI</b> (ProtectedData, scope CurrentUser).
///
/// El token de licencia se guarda en %LocalAppData%\PagoYa\licencia.token como
/// blob cifrado (no texto plano). DPAPI ata el descifrado a la cuenta de
/// usuario de Windows: otro usuario/equipo no puede leer el token, lo que
/// dificulta copiar la licencia entre PCs (defensa en profundidad junto al HWID).
///
/// Nota: DPAPI (CurrentUser) es específico de Windows. Si en el futuro se porta
/// a otra plataforma, este store debe reemplazarse. La firma RSA del token
/// sigue siendo la barrera criptográfica principal; DPAPI solo protege el
/// artefacto en disco.
///
/// Compatibilidad: el archivo se movió a %LocalAppData% (antes %APPDATA%) para
/// alinearse con la BD y con datos que no deben roamear. Se mantiene lectura del
/// archivo antiguo por compatibilidad si aún existe.
/// </summary>
public sealed class LicenseStoreArchivo : ILicenseStore
{
    // Entropía adicional específica de la app: refuerza el cifrado DPAPI.
    private static readonly byte[] Entropia = Encoding.UTF8.GetBytes("PagoYa.Licencia.v1");

    private readonly string _rutaArchivo;
    private readonly string _rutaLegacy;

    public LicenseStoreArchivo()
    {
        var carpeta = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PagoYa");
        Directory.CreateDirectory(carpeta);
        _rutaArchivo = Path.Combine(carpeta, "licencia.token");

        _rutaLegacy = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PagoYa", "licencia.token");
    }

    /// <inheritdoc />
    public string? LeerToken()
    {
        var ruta = File.Exists(_rutaArchivo) ? _rutaArchivo
                 : File.Exists(_rutaLegacy) ? _rutaLegacy
                 : null;
        if (ruta is null) return null;

        try
        {
            var cifrado = File.ReadAllBytes(ruta);
            if (cifrado.Length == 0) return null;
            var plano = ProtectedData.Unprotect(cifrado, Entropia, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plano);
        }
        catch (CryptographicException)
        {
            // Token corrupto o cifrado con otra cuenta: se ignora (degrada a Base).
            return null;
        }
    }

    /// <inheritdoc />
    public void GuardarToken(string tokenFirmado)
    {
        var plano = Encoding.UTF8.GetBytes(tokenFirmado);
        var cifrado = ProtectedData.Protect(plano, Entropia, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_rutaArchivo, cifrado);
    }
}
