namespace PagoYa.Core.Contratos;

/// <summary>
/// Catálogo de <b>feature flags</b> que la licencia puede habilitar. El gating
/// se hace por flag individual (no por tier) para máxima flexibilidad
/// comercial: un token podría, por ejemplo, habilitar <see cref="CloudSync"/>
/// sin <see cref="Invoicing"/>.
///
/// Los nombres string (ver <see cref="Flags"/>) son el contrato estable que
/// comparten el emisor (licensing-backend) y el validador (cliente). NO
/// renombrar sin coordinar ambos lados.
/// </summary>
public enum CaracteristicaLicencia
{
    /// <summary>Facturación electrónica SUNAT (Boletas/Facturas). Flag: "invoicing".</summary>
    Invoicing,

    /// <summary>Respaldo y sincronización en la nube. Flag: "cloud_sync".</summary>
    CloudSync,

    /// <summary>Operación multi-caja / multisede. Flag: "multi_site".</summary>
    MultiSite
}

/// <summary>
/// Nombres canónicos (string) de los feature flags tal como viajan dentro del
/// token de licencia firmado. Contrato compartido con licensing-backend.
/// </summary>
public static class Flags
{
    public const string Invoicing = "invoicing";
    public const string CloudSync = "cloud_sync";
    public const string MultiSite = "multi_site";

    /// <summary>Traduce el enum al nombre canónico del flag en el token.</summary>
    public static string ToFlagName(this CaracteristicaLicencia caracteristica) => caracteristica switch
    {
        CaracteristicaLicencia.Invoicing => Invoicing,
        CaracteristicaLicencia.CloudSync => CloudSync,
        CaracteristicaLicencia.MultiSite => MultiSite,
        _ => throw new ArgumentOutOfRangeException(nameof(caracteristica), caracteristica, null)
    };
}
