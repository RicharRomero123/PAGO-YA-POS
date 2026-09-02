using PagoYa.Core.Common;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Movimiento de inventario (kardex). Fuente de verdad de las variaciones de
/// stock de un <see cref="Producto"/>. Cada venta, compra o ajuste genera un
/// registro. El campo <see cref="Producto.StockActual"/> es solo un cache.
/// </summary>
public class Inventario : EntidadBase
{
    /// <summary>Producto afectado.</summary>
    public Guid ProductoId { get; set; }

    /// <summary>
    /// Cantidad del movimiento. Positiva para entradas (compra, ajuste +),
    /// negativa para salidas (venta, merma, ajuste -).
    /// </summary>
    public decimal Cantidad { get; set; }

    /// <summary>Stock resultante después de aplicar el movimiento (snapshot).</summary>
    public decimal StockResultante { get; set; }

    /// <summary>Motivo del movimiento (ej. "Venta V-000123", "Compra", "Ajuste").</summary>
    public string Motivo { get; set; } = string.Empty;

    /// <summary>Referencia opcional al documento origen (ej. Id de venta).</summary>
    public Guid? ReferenciaId { get; set; }

    /// <summary>Fecha/hora del movimiento.</summary>
    public DateTime FechaHora { get; set; } = DateTime.Now;
}
