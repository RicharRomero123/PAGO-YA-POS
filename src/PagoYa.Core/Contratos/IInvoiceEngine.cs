using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Motor de facturación electrónica SUNAT. Convierte una <see cref="Venta"/> en
/// un comprobante electrónico (UBL 2.1), lo firma y lo envía a SUNAT/OSE o a un
/// PSE intermedio (Nubefact/ApisPeru).
///
/// FEATURE-GATED: solo se instancia el motor real cuando el flag "invoicing"
/// está habilitado en la licencia. En caso contrario se usa el patrón Null
/// Object (<see cref="IInvoiceEngine"/> nulo) que rechaza la emisión.
///
/// Implementa: sunat-facturacion (PagoYa.Invoicing.Sunat).
/// </summary>
public interface IInvoiceEngine
{
    /// <summary>True si este motor puede emitir comprobantes electrónicos (licencia activa).</summary>
    bool PuedeEmitir { get; }

    /// <summary>
    /// Emite un comprobante electrónico (Boleta/Factura) a partir de una venta.
    /// Genera el XML UBL 2.1, lo firma y lo transmite.
    /// </summary>
    /// <param name="venta">Venta a facturar.</param>
    /// <param name="ct">Token de cancelación.</param>
    /// <returns>Resultado con estado SUNAT, CDR y rutas de artefactos.</returns>
    Task<ResultadoEmision> EmitirComprobanteAsync(Venta venta, CancellationToken ct = default);
}

/// <summary>Resultado de intentar emitir un comprobante electrónico.</summary>
public sealed class ResultadoEmision
{
    /// <summary>True si SUNAT/OSE aceptó el comprobante.</summary>
    public bool Aceptado { get; init; }

    /// <summary>Comprobante generado (con hash, serie, correlativo). Null si falló antes de crearlo.</summary>
    public Comprobante? Comprobante { get; init; }

    /// <summary>Código de respuesta CDR de SUNAT.</summary>
    public string? CodigoCdr { get; init; }

    /// <summary>Mensaje legible (éxito o motivo de rechazo, para soporte por WhatsApp).</summary>
    public string? Mensaje { get; init; }

    /// <summary>Resultado que indica que la facturación no está habilitada por licencia.</summary>
    public static ResultadoEmision NoHabilitado() => new()
    {
        Aceptado = false,
        Mensaje = "La facturación electrónica requiere el plan PagoYa Facturador Pro."
    };
}
