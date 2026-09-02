namespace PagoYa.Core.Enums;

/// <summary>
/// Estado operativo de una habitación en el mapa del hotel/hostal. Define el color
/// y las acciones disponibles (check-in solo si está Disponible, etc.).
/// </summary>
public enum EstadoHabitacion
{
    /// <summary>Libre y lista para recibir huésped (verde).</summary>
    Disponible = 0,

    /// <summary>Con huésped hospedado (rojo). Tiene una estadía activa.</summary>
    Ocupada = 1,

    /// <summary>En limpieza tras el check-out (ámbar). No se puede ocupar aún.</summary>
    Limpieza = 2,

    /// <summary>Fuera de servicio por mantenimiento (gris).</summary>
    Mantenimiento = 3,

    /// <summary>Reservada para un huésped por llegar (azul).</summary>
    Reservada = 4
}
