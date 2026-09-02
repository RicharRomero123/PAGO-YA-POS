using System.Management;
using System.Security.Cryptography;
using System.Text;
using PagoYa.Core.Contratos;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Implementación Windows de <see cref="IHardwareId"/>.
///
/// Deriva el HWID de <b>CPU ID</b> (Win32_Processor.ProcessorId) +
/// <b>BaseBoard serial</b> (Win32_BaseBoard.SerialNumber) vía WMI
/// (System.Management), combina ambos y los hashea con SHA-256 para obtener un
/// identificador estable por equipo (determinístico entre arranques).
///
/// Robustez:
///   * El resultado se cachea en memoria: WMI es relativamente lento y el HWID
///     no cambia durante la sesión.
///   * Si algún componente WMI falla o devuelve vacío/placeholder (comunes en
///     placas OEM que reportan "To be filled by O.E.M." o "None"), se
///     descarta ese valor y se recurre a un fallback estable
///     (MachineGuid del registro + nombre de máquina) para no romper la
///     validación de licencia. El hash final nunca queda vacío.
///
/// Compatibilidad: Windows 10/11. WMI está siempre disponible; no requiere
/// privilegios de administrador para estas clases. En entornos headless/CI sin
/// WMI, el fallback garantiza un HWID no vacío.
/// </summary>
public sealed class HardwareIdWindows : IHardwareId
{
    private static readonly string[] ValoresBasura =
    {
        "", "none", "n/a", "na", "null", "default string", "to be filled by o.e.m.",
        "0", "00000000", "ffffffffffffffff", "system serial number"
    };

    private string? _cache;

    /// <inheritdoc />
    public string ObtenerHwid()
    {
        if (_cache is not null) return _cache;

        var cpuId = LeerWmi("Win32_Processor", "ProcessorId");
        var baseBoard = LeerWmi("Win32_BaseBoard", "SerialNumber");

        var partes = new List<string>();
        if (EsValido(cpuId)) partes.Add("CPU:" + cpuId);
        if (EsValido(baseBoard)) partes.Add("MB:" + baseBoard);

        // Fallback si WMI no dio nada útil (placas OEM, headless, permisos).
        if (partes.Count == 0)
        {
            var machineGuid = LeerMachineGuid();
            if (EsValido(machineGuid)) partes.Add("MG:" + machineGuid);
            partes.Add("HOST:" + Environment.MachineName);
        }

        var semilla = string.Join("|", partes);
        _cache = HashSha256(semilla);
        return _cache;
    }

    private static bool EsValido(string? valor)
        => !string.IsNullOrWhiteSpace(valor)
           && !ValoresBasura.Contains(valor.Trim().ToLowerInvariant());

    private static string? LeerWmi(string clase, string propiedad)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher($"SELECT {propiedad} FROM {clase}");
            foreach (var obj in searcher.Get())
            {
                var valor = obj[propiedad]?.ToString()?.Trim();
                if (!string.IsNullOrWhiteSpace(valor))
                    return valor;
            }
        }
        catch
        {
            // WMI no disponible / bloqueado: seguimos con fallback.
        }
        return null;
    }

    /// <summary>
    /// Lee HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid, un identificador
    /// estable generado en la instalación de Windows. Fallback fiable.
    /// </summary>
    private static string? LeerMachineGuid()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Cryptography");
            return key?.GetValue("MachineGuid")?.ToString();
        }
        catch
        {
            return null;
        }
    }

    private static string HashSha256(string entrada)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(entrada));
        // Hex en minúsculas: estable y comparable case-insensitive con el token.
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
