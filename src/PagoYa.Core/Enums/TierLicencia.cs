namespace PagoYa.Core.Enums;

/// <summary>
/// Niveles de licencia de PagoYa. El tier determina qué features (flags)
/// vienen habilitados por defecto en el token, pero el gating real se hace
/// por <c>feature flags</c> individuales (ver <see cref="Contratos.CaracteristicaLicencia"/>),
/// no por el tier directamente. El tier es informativo/comercial.
/// </summary>
public enum TierLicencia
{
    /// <summary>PagoYa Base — offline de por vida, 1 caja, notas de venta.</summary>
    Base = 0,

    /// <summary>PagoYa Cloud — respaldo en la nube, multi-caja / multisede.</summary>
    Cloud = 1,

    /// <summary>PagoYa Facturador Pro — Boletas/Facturas SUNAT ilimitadas.</summary>
    FacturadorPro = 2
}
