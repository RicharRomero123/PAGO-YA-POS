namespace PagoYa.Core.Enums;

/// <summary>Estado de una comanda/cuenta de mesa (rubro restaurante).</summary>
public enum EstadoPedido
{
    /// <summary>Abierta: se le agregan platos y se envían a cocina.</summary>
    Abierta = 0,

    /// <summary>Cobrada: se generó la venta y la mesa quedó libre.</summary>
    Cobrada = 1,

    /// <summary>Anulada: se descartó sin cobrar.</summary>
    Anulada = 2,
}
