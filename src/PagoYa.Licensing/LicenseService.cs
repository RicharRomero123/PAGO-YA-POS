using PagoYa.Core.Contratos;
using PagoYa.Core.Enums;

namespace PagoYa.Licensing;

/// <summary>
/// Implementación cliente de <see cref="ILicenseService"/>. Orquesta la
/// validación completa de la licencia:
///   1. Verifica la firma RSA (delegando en <see cref="LicenseTokenValidator"/>).
///   2. Verifica que el HWID del token coincida con el de esta máquina.
///   3. Aplica expiración con grace period.
///   4. Traduce el token a <see cref="EstadoLicencia"/> para feature-gating.
///
/// Si algo falla, devuelve un estado <b>Base</b> seguro: nunca habilita
/// features premium sin un token válido (regla de negocio clave de CLAUDE.md).
/// </summary>
public sealed class LicenseService : ILicenseService
{
    /// <summary>
    /// Días de gracia tras la expiración durante los cuales la app sigue
    /// operando con las features del tier, mostrando aviso de renovación.
    /// Motivo: evitar que un corte de pago/red bloquee al negocio en caliente.
    /// </summary>
    public const int DiasGracia = 7;

    private readonly LicenseTokenValidator _validator;
    private readonly IHardwareId _hardwareId;
    private readonly ILicenseStore _store;

    private EstadoLicencia _estadoActual = EstadoLicencia.Base("Licencia no cargada.");

    public LicenseService(LicenseTokenValidator validator, IHardwareId hardwareId, ILicenseStore store)
    {
        _validator = validator;
        _hardwareId = hardwareId;
        _store = store;
    }

    /// <inheritdoc />
    public EstadoLicencia EstadoActual => _estadoActual;

    /// <inheritdoc />
    public EstadoLicencia CargarLicenciaLocal()
    {
        var tokenGuardado = _store.LeerToken();
        if (string.IsNullOrWhiteSpace(tokenGuardado))
        {
            _estadoActual = EstadoLicencia.Base("Sin licencia instalada. Operando en modo Base.");
            return _estadoActual;
        }
        return ValidarToken(tokenGuardado);
    }

    /// <inheritdoc />
    public EstadoLicencia ValidarToken(string tokenFirmado)
    {
        _estadoActual = ValidarInterno(tokenFirmado, out _);
        return _estadoActual;
    }

    /// <inheritdoc />
    public EstadoLicencia ActivarLicencia(string tokenFirmado)
    {
        _estadoActual = ValidarInterno(tokenFirmado, out var esAutentica);

        // Solo persistimos tokens auténticos (firma + HWID + no vencidos): así una
        // activación fallida nunca sobrescribe una licencia buena ya instalada.
        if (esAutentica)
            _store.GuardarToken(tokenFirmado);

        return _estadoActual;
    }

    /// <summary>
    /// Núcleo de validación (puro respecto al estado: no muta ni persiste).
    /// <paramref name="esAutentica"/> es true solo si el token superó firma, HWID
    /// y ventana de expiración/gracia; false en cualquier fallo (que degrada a Base).
    /// </summary>
    private EstadoLicencia ValidarInterno(string tokenFirmado, out bool esAutentica)
    {
        esAutentica = false;

        // 1) Firma criptográfica.
        if (!_validator.TryValidar(tokenFirmado, out var token, out var error) || token is null)
            return EstadoLicencia.Base($"Token inválido: {error}");

        // 2) Vinculación a hardware (anti-reuso del token en otro PC).
        if (!string.IsNullOrEmpty(token.Hwid))
        {
            var hwidLocal = _hardwareId.ObtenerHwid();
            if (!string.Equals(token.Hwid, hwidLocal, StringComparison.OrdinalIgnoreCase))
                return EstadoLicencia.Base("La licencia pertenece a otro equipo.");
        }

        // 3) Expiración + grace period.
        var ahoraUtc = DateTime.UtcNow;
        var enGracia = false;
        if (!token.EsPerpetua && token.ExpiraUtc is { } expira)
        {
            if (ahoraUtc > expira)
            {
                var limiteGracia = expira.AddDays(DiasGracia);
                if (ahoraUtc > limiteGracia)
                    return EstadoLicencia.Base(
                        $"La licencia expiró el {expira:d} y venció el periodo de gracia.");
                enGracia = true;
            }
        }

        // 4) Token válido -> estado con features habilitados.
        esAutentica = true;
        return new EstadoLicencia
        {
            EsValida = true,
            EstaActivada = true,   // token auténtico instalado (incluye Base activada)
            Tier = MapearTier(token.Tier),
            FeaturesHabilitadas = new HashSet<string>(token.Features, StringComparer.OrdinalIgnoreCase),
            ExpiraUtc = token.ExpiraUtc,
            EnPeriodoGracia = enGracia,
            Motivo = enGracia ? "Licencia en periodo de gracia. Renueve para evitar cortes." : null
        };
    }

    /// <inheritdoc />
    public bool TieneCaracteristica(CaracteristicaLicencia caracteristica)
        => _estadoActual.TieneCaracteristica(caracteristica);

    private static TierLicencia MapearTier(string tier) => tier.ToLowerInvariant() switch
    {
        "cloud" => TierLicencia.Cloud,
        "facturador" or "facturador_pro" => TierLicencia.FacturadorPro,
        _ => TierLicencia.Base
    };
}

/// <summary>
/// Abstracción del almacenamiento local del token (archivo cifrado, registro,
/// etc.). Se define aquí para desacoplar <see cref="LicenseService"/> del
/// mecanismo de persistencia. Implementa: desktop-dev.
/// </summary>
public interface ILicenseStore
{
    /// <summary>Lee el token de licencia persistido, o null si no existe.</summary>
    string? LeerToken();

    /// <summary>Guarda/actualiza el token de licencia localmente.</summary>
    void GuardarToken(string tokenFirmado);
}
