namespace PagoYa.Core.Enums;

/// <summary>
/// Tipo de comprobante emitido en una venta.
/// Los códigos numéricos siguen el Catálogo 01 de SUNAT (tipo de documento).
/// </summary>
public enum TipoComprobante
{
    /// <summary>
    /// Nota de venta / ticket interno. NO es un comprobante electrónico SUNAT.
    /// Disponible en el tier Base (sin facturación electrónica).
    /// </summary>
    NotaVenta = 0,

    /// <summary>Boleta de venta electrónica. Catálogo 01 SUNAT = "03".</summary>
    Boleta = 3,

    /// <summary>Factura electrónica. Catálogo 01 SUNAT = "01".</summary>
    Factura = 1
}
