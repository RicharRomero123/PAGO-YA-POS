using PagoYa.Core.Enums;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Resultado de validar la licencia local. Es un snapshot inmutable que la
/// UI y los servicios consultan para hacer feature-gating. Se obtiene de
/// <see cref="ILicenseService"/>.
/// </summary>
public sealed class EstadoLicencia
{
    /// <summary>True si el token es válido (firma OK, HWID OK, no expirado o en gracia).</summary>
    public bool EsValida { get; init; }

    /// <summary>
    /// True solo si hay un token de licencia AUTÉNTICO instalado (firma válida +
    /// HWID de esta máquina + no vencido), sea del tier que sea, <b>incluido Base</b>.
    /// False si no hay token o es inválido: bajo el modelo "Base exige activación",
    /// la app debe mostrar la pantalla de activación y no permitir operar hasta que
    /// esto sea true. Distinto de <see cref="EsValida"/>, que es true incluso en el
    /// modo Base de respaldo sin token.
    /// </summary>
    public bool EstaActivada { get; init; }

    /// <summary>Tier comercial resuelto del token. Base si no hay licencia válida.</summary>
    public TierLicencia Tier { get; init; } = TierLicencia.Base;

    /// <summary>Conjunto de flags habilitados (nombres canónicos, ver <see cref="Flags"/>).</summary>
    public IReadOnlySet<string> FeaturesHabilitadas { get; init; } = new HashSet<string>();

    /// <summary>Fecha de expiración del token (UTC). Null para licencias perpetuas (tier Base).</summary>
    public DateTime? ExpiraUtc { get; init; }

    /// <summary>
    /// True si el token expiró pero aún opera dentro del grace period.
    /// La UI debe mostrar un aviso para renovar.
    /// </summary>
    public bool EnPeriodoGracia { get; init; }

    /// <summary>Mensaje legible del motivo si <see cref="EsValida"/> es false (para soporte/UI).</summary>
    public string? Motivo { get; init; }

    /// <summary>Consulta rápida de feature-gating por flag canónico.</summary>
    public bool TieneCaracteristica(string flag) => FeaturesHabilitadas.Contains(flag);

    /// <summary>Consulta de feature-gating tipada.</summary>
    public bool TieneCaracteristica(CaracteristicaLicencia caracteristica)
        => FeaturesHabilitadas.Contains(caracteristica.ToFlagName());

    /// <summary>Estado por defecto: tier Base sin features premium (fallback seguro).</summary>
    public static EstadoLicencia Base(string? motivo = null) => new()
    {
        EsValida = true,
        Tier = TierLicencia.Base,
        FeaturesHabilitadas = new HashSet<string>(),
        Motivo = motivo
    };
}
