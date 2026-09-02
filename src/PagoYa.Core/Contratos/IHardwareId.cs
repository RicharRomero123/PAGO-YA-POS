namespace PagoYa.Core.Contratos;

/// <summary>
/// Genera el identificador de hardware (HWID) de la máquina para vincular la
/// licencia a un equipo concreto y evitar la reutilización del token en otros
/// PCs (mitigación de piratería / replay de token).
///
/// Estrategia (ver CLAUDE.md): fingerprint por CPU ID + BaseBoard serial (WMI),
/// hasheado. Implementa: desktop-dev.
/// </summary>
public interface IHardwareId
{
    /// <summary>
    /// Obtiene el HWID estable de esta máquina (hash hex/base64). Debe ser
    /// determinístico entre arranques del mismo equipo.
    /// </summary>
    string ObtenerHwid();
}
