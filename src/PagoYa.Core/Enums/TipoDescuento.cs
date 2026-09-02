namespace PagoYa.Core.Enums;

/// <summary>
/// Cómo se define el descuento de un producto. Elegido por producto en el
/// inventario; el precio efectivo lo calcula <see cref="Entidades.Producto.PrecioFinal"/>.
/// </summary>
public enum TipoDescuento
{
    /// <summary>Sin descuento: se vende al precio normal.</summary>
    Ninguno = 0,

    /// <summary>Descuento porcentual (0–100). Ej. 15 = -15% sobre el precio normal.</summary>
    Porcentaje = 1,

    /// <summary>Precio de oferta fijo en soles. Reemplaza al precio normal si es menor.</summary>
    Oferta = 2
}
