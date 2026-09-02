namespace PagoYa.Core.Enums;

/// <summary>Estado de una sesión de <see cref="Entidades.Caja"/> (arqueo).</summary>
public enum EstadoCaja
{
    /// <summary>Caja abierta: acepta ventas y movimientos.</summary>
    Abierta = 0,

    /// <summary>Caja cerrada: sesión finalizada tras el arqueo.</summary>
    Cerrada = 1
}
