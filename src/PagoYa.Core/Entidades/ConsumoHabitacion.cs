using PagoYa.Core.Common;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Consumo cargado a la cuenta de una habitación durante la estadía (minibar,
/// lavandería, restaurante…). Puede referenciar un producto del inventario o ser
/// un cargo manual. Se suma al total del check-out.
/// </summary>
public class ConsumoHabitacion : EntidadBase
{
    /// <summary>Estadía a la que se carga el consumo.</summary>
    public Guid EstadiaId { get; set; }

    /// <summary>Producto del inventario consumido (null si es un cargo manual).</summary>
    public Guid? ProductoId { get; set; }

    /// <summary>Descripción del consumo (congelada; ej. "Agua mineral").</summary>
    public string Descripcion { get; set; } = string.Empty;

    /// <summary>Cantidad consumida.</summary>
    public decimal Cantidad { get; set; } = 1;

    /// <summary>Precio unitario al momento del consumo.</summary>
    public decimal PrecioUnitario { get; set; }

    /// <summary>Importe de la línea (cantidad × precio unitario).</summary>
    public decimal Importe => decimal.Round(Cantidad * PrecioUnitario, 2);

    /// <summary>Momento del consumo (UTC).</summary>
    public DateTime FechaHoraUtc { get; set; } = DateTime.UtcNow;
}
