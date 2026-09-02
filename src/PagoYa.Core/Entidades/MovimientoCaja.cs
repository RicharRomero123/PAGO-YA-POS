using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Movimiento de efectivo en una sesión de <see cref="Caja"/> distinto a una
/// venta: fondo de apertura, ingresos, egresos o retiros. Alimenta el arqueo.
/// </summary>
public class MovimientoCaja : EntidadBase
{
    /// <summary>Sesión de caja a la que pertenece el movimiento.</summary>
    public Guid CajaId { get; set; }

    /// <summary>Tipo de movimiento (apertura/ingreso/egreso/retiro).</summary>
    public TipoMovimientoCaja Tipo { get; set; }

    /// <summary>Monto del movimiento en soles (siempre positivo; el signo lo da el Tipo).</summary>
    public decimal Monto { get; set; }

    /// <summary>Concepto/motivo (ej. "Pago proveedor gaseosas").</summary>
    public string Concepto { get; set; } = string.Empty;

    /// <summary>Fecha/hora del movimiento.</summary>
    public DateTime FechaHora { get; set; } = DateTime.Now;
}
