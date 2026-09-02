namespace PagoYa.Core.Enums;

/// <summary>
/// Tipo de <see cref="Entidades.MovimientoCaja"/>: entradas y salidas de
/// efectivo distintas a las ventas (para el arqueo de caja).
/// </summary>
public enum TipoMovimientoCaja
{
    /// <summary>Monto inicial al abrir la caja (fondo).</summary>
    AperturaFondo = 0,

    /// <summary>Ingreso de efectivo (ej. aporte del dueño).</summary>
    Ingreso = 1,

    /// <summary>Salida de efectivo (ej. pago a proveedor, retiro).</summary>
    Egreso = 2,

    /// <summary>Retiro parcial de efectivo de la caja.</summary>
    Retiro = 3
}
