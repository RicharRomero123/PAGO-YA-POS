using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Habitación del hotel/hostal. Es el "producto" del rubro hotelero: se registra
/// una vez (número, piso, tipo y tarifas) y luego cambia de <see cref="Estado"/>
/// según el mapa de recepción. Soporta tarifa por noche y por hora (hostal del paso).
/// </summary>
public class Habitacion : EntidadBase
{
    /// <summary>Número/nombre visible de la habitación (ej. "101", "Suite A").</summary>
    public string Numero { get; set; } = string.Empty;

    /// <summary>Piso donde está (para agrupar el mapa). 0 si no aplica.</summary>
    public int Piso { get; set; }

    /// <summary>Tipo de habitación (simple, doble, matrimonial, suite…).</summary>
    public TipoHabitacion Tipo { get; set; } = TipoHabitacion.Simple;

    /// <summary>Tarifa por noche en soles.</summary>
    public decimal PrecioNoche { get; set; }

    /// <summary>Tarifa por hora en soles (hostal del paso). 0 si no ofrece por hora.</summary>
    public decimal PrecioHora { get; set; }

    /// <summary>Capacidad de personas (informativo).</summary>
    public int Capacidad { get; set; } = 1;

    /// <summary>Estado operativo actual (mapa de recepción).</summary>
    public EstadoHabitacion Estado { get; set; } = EstadoHabitacion.Disponible;

    /// <summary>Notas de la habitación (características, observaciones).</summary>
    public string? Notas { get; set; }

    /// <summary>Ruta local a la foto de la habitación (en %LocalAppData%\PagoYa\img). Null si no tiene.</summary>
    public string? ImagenRuta { get; set; }

    /// <summary>
    /// Comodidades/adicionales de la habitación (TV Smart, Jacuzzi, etc.), unidas
    /// por '|'. Se eligen de una lista predefinida al crear/editar el cuarto.
    /// </summary>
    public string? Comodidades { get; set; }

    /// <summary>Lista de comodidades (parsea <see cref="Comodidades"/>).</summary>
    public IReadOnlyList<string> ComodidadesLista =>
        string.IsNullOrWhiteSpace(Comodidades)
            ? Array.Empty<string>()
            : Comodidades.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    /// <summary>Habitación activa/visible en el mapa.</summary>
    public bool Activa { get; set; } = true;

    /// <summary>True si ofrece tarifa por hora (hostal del paso).</summary>
    public bool OfreceHora => PrecioHora > 0m;
}
