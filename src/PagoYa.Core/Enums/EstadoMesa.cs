namespace PagoYa.Core.Enums;

/// <summary>Estado operativo de una mesa en el mapa del salón (rubro restaurante).</summary>
public enum EstadoMesa
{
    /// <summary>Disponible para sentar clientes.</summary>
    Libre = 0,

    /// <summary>Con una cuenta/pedido abierto en curso.</summary>
    Ocupada = 1,

    /// <summary>Consumo cerrado, esperando el cobro.</summary>
    PorCobrar = 2,

    /// <summary>Reservada (no se puede ocupar).</summary>
    Reservada = 3,
}
