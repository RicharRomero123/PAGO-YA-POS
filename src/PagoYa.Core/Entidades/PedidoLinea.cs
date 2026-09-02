using PagoYa.Core.Common;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Línea de una comanda de mesa (<see cref="Pedido"/>): un plato/bebida con su
/// cantidad, precio y la personalización ya aplicada en <see cref="Descripcion"/>
/// (nombre + modificadores) más una <see cref="Nota"/> para la cocina.
/// </summary>
public class PedidoLinea : EntidadBase
{
    /// <summary>Pedido/comanda al que pertenece.</summary>
    public Guid PedidoId { get; set; }

    /// <summary>Producto del catálogo (para descontar stock al cobrar). Empty si es ad-hoc.</summary>
    public Guid ProductoId { get; set; }

    /// <summary>Descripción de venta (nombre + modificadores elegidos), congelada.</summary>
    public string Descripcion { get; set; } = string.Empty;

    /// <summary>Nota para la cocina (ej. "sin cebolla"). Opcional.</summary>
    public string? Nota { get; set; }

    /// <summary>Cantidad pedida.</summary>
    public decimal Cantidad { get; set; } = 1;

    /// <summary>Precio unitario ya con modificadores sumados.</summary>
    public decimal PrecioUnitario { get; set; }

    /// <summary>Importe de la línea (cantidad × precio unitario).</summary>
    public decimal Importe { get; set; }

    /// <summary>True si esta línea ya se envió/imprimió en comanda a la cocina.</summary>
    public bool EnviadoCocina { get; set; }
}
