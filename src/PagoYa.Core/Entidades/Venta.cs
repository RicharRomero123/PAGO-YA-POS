using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Cabecera de una venta (transacción de cobro) realizada en el POS.
/// El detalle vive en <see cref="Detalles"/> (<see cref="DetalleVenta"/>).
/// Una venta pertenece a una sesión de <see cref="Caja"/>.
/// </summary>
public class Venta : EntidadBase
{
    /// <summary>Número correlativo legible por caja (ej. "V-000123"). No es la PK.</summary>
    public string Numero { get; set; } = string.Empty;

    /// <summary>Sesión de caja en la que se registró la venta.</summary>
    public Guid CajaId { get; set; }

    /// <summary>Fecha/hora local de la venta (para el ticket y reportes).</summary>
    public DateTime FechaHora { get; set; } = DateTime.Now;

    /// <summary>Método de pago principal empleado.</summary>
    public MetodoPago MetodoPago { get; set; } = MetodoPago.Efectivo;

    /// <summary>Estado del ciclo de vida (Completada / Anulada).</summary>
    public EstadoVenta Estado { get; set; } = EstadoVenta.Completada;

    /// <summary>Suma de subtotales sin IGV (valor de venta).</summary>
    public decimal SubTotal { get; set; }

    /// <summary>Monto de IGV (18%) de la venta.</summary>
    public decimal Igv { get; set; }

    /// <summary>Total a pagar (SubTotal + IGV - descuentos).</summary>
    public decimal Total { get; set; }

    /// <summary>Efectivo recibido (para calcular vuelto). Opcional.</summary>
    public decimal? MontoRecibido { get; set; }

    /// <summary>
    /// Comprobante asociado si se emitió uno (Boleta/Factura/NotaVenta).
    /// Null hasta que se genere el comprobante. Ver <see cref="Comprobante"/>.
    /// </summary>
    public Guid? ComprobanteId { get; set; }

    /// <summary>Líneas de la venta.</summary>
    public List<DetalleVenta> Detalles { get; set; } = new();
}
