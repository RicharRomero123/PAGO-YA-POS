using PagoYa.Core.Common;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Línea de detalle de una <see cref="Venta"/>: un producto, cantidad y
/// precios. Se guarda el nombre/precio "congelado" al momento de la venta
/// para que reportes históricos no cambien si el catálogo se edita luego.
/// </summary>
public class DetalleVenta : EntidadBase
{
    /// <summary>Venta a la que pertenece esta línea.</summary>
    public Guid VentaId { get; set; }

    /// <summary>Producto vendido.</summary>
    public Guid ProductoId { get; set; }

    /// <summary>Descripción congelada del producto al momento de la venta.</summary>
    public string DescripcionProducto { get; set; } = string.Empty;

    /// <summary>Cantidad vendida (permite decimales para KG, etc.).</summary>
    public decimal Cantidad { get; set; }

    /// <summary>Precio unitario aplicado (congelado).</summary>
    public decimal PrecioUnitario { get; set; }

    /// <summary>Descuento aplicado a la línea (monto en soles).</summary>
    public decimal Descuento { get; set; }

    /// <summary>Importe de la línea = Cantidad * PrecioUnitario - Descuento.</summary>
    public decimal Importe { get; set; }
}
