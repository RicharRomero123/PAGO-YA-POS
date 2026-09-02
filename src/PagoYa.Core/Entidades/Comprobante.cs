using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Comprobante emitido por una <see cref="Venta"/>. Puede ser una nota de
/// venta interna (tier Base) o un comprobante electrónico SUNAT (Boleta/
/// Factura, tier Facturador Pro). Los campos de facturación electrónica
/// (hash, CDR, estado SUNAT) solo se llenan cuando el flag <c>invoicing</c>
/// está habilitado por la licencia.
/// </summary>
public class Comprobante : EntidadBase
{
    /// <summary>Venta que originó el comprobante.</summary>
    public Guid VentaId { get; set; }

    /// <summary>Tipo (NotaVenta / Boleta / Factura).</summary>
    public TipoComprobante Tipo { get; set; } = TipoComprobante.NotaVenta;

    /// <summary>Serie del comprobante (ej. "B001", "F001", "NV01").</summary>
    public string Serie { get; set; } = string.Empty;

    /// <summary>Correlativo dentro de la serie (ej. 123).</summary>
    public int Correlativo { get; set; }

    /// <summary>RUC/DNI del cliente. Opcional para boletas de bajo monto.</summary>
    public string? DocumentoCliente { get; set; }

    /// <summary>Nombre o razón social del cliente.</summary>
    public string? NombreCliente { get; set; }

    /// <summary>Importe total del comprobante.</summary>
    public decimal Total { get; set; }

    // --- Campos de facturación electrónica SUNAT (solo con flag "invoicing") ---
    // TODO(sunat-facturacion): poblar estos campos desde IInvoiceEngine.

    /// <summary>Hash del XML firmado (DigestValue). Null si no es comprobante electrónico.</summary>
    public string? HashXml { get; set; }

    /// <summary>Estado ante SUNAT/OSE (ej. "PENDIENTE", "ACEPTADO", "RECHAZADO").</summary>
    public string? EstadoSunat { get; set; }

    /// <summary>Código de respuesta del CDR (Constancia de Recepción). Null si no aplica.</summary>
    public string? CodigoCdr { get; set; }

    /// <summary>Ruta local del XML firmado (UBL 2.1). Null si no aplica.</summary>
    public string? RutaXml { get; set; }

    /// <summary>Ruta local del PDF/ticket generado. Null si no aplica.</summary>
    public string? RutaPdf { get; set; }
}
