namespace PagoYa.Core.Enums;

/// <summary>Estado de una estadía (registro de hospedaje) de una habitación.</summary>
public enum EstadoEstadia
{
    /// <summary>Huésped hospedado; aún no se hace check-out.</summary>
    Activa = 0,

    /// <summary>Check-out realizado y cobrado.</summary>
    Cerrada = 1,

    /// <summary>Anulada (no se cobró).</summary>
    Anulada = 2
}
