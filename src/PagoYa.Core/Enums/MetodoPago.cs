namespace PagoYa.Core.Enums;

/// <summary>
/// Método de pago usado por el cliente en una venta. Relevante para el
/// arqueo de caja y (a futuro) para reportes de conciliación.
/// </summary>
public enum MetodoPago
{
    /// <summary>Efectivo en soles (PEN).</summary>
    Efectivo = 0,

    /// <summary>Tarjeta de crédito o débito (POS bancario).</summary>
    Tarjeta = 1,

    /// <summary>Billetera digital: Yape, Plin, etc.</summary>
    BilleteraDigital = 2,

    /// <summary>Transferencia bancaria.</summary>
    Transferencia = 3,

    /// <summary>Venta a crédito / fiado.</summary>
    Credito = 4
}
