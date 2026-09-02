using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Productos "de sistema" con Id fijo que NO se muestran en el catálogo pero
/// existen en la tabla productos para satisfacer la llave foránea de
/// detalle_ventas. Se usan para conceptos que no son artículos de inventario,
/// como el hospedaje de una habitación cobrado al hacer check-out.
/// </summary>
public static class ProductosEspeciales
{
    /// <summary>Id fijo del producto oculto "Hospedaje" (línea de alquiler en la venta).</summary>
    public static readonly Guid HospedajeId = new("11111111-1111-4111-8111-111111111111");

    /// <summary>Construye/actualiza el producto oculto de hospedaje (inactivo, sin stock).</summary>
    public static Producto Hospedaje() => new()
    {
        Id = HospedajeId,
        Codigo = "HOSPEDAJE",
        Nombre = "Hospedaje",
        Descripcion = "Habitaciones",
        PrecioVenta = 0m,
        PrecioIncluyeIgv = true,
        UnidadMedida = "ZZ",
        StockActual = 0m,
        ControlaStock = false, // nunca mueve inventario
        Activo = false          // oculto del catálogo y del inventario
    };
}
