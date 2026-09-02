using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Persistencia del módulo hotelero (rubro hotel/hostal): habitaciones, estadías
/// (check-in/check-out) y consumos cargados a la habitación. Implementa:
/// PagoYa.Data (SQLite: tablas 'habitaciones', 'estadias_habitacion',
/// 'consumos_habitacion').
/// </summary>
public interface IHotelRepository
{
    // --- Habitaciones (maestro) ---

    /// <summary>Lista las habitaciones (por defecto solo activas), ordenadas por piso y número.</summary>
    Task<IReadOnlyList<Habitacion>> ListarHabitacionesAsync(bool soloActivas = true, CancellationToken ct = default);

    /// <summary>Obtiene una habitación por Id, o null.</summary>
    Task<Habitacion?> ObtenerHabitacionAsync(Guid id, CancellationToken ct = default);

    /// <summary>Inserta o actualiza una habitación (upsert por Id).</summary>
    Task GuardarHabitacionAsync(Habitacion habitacion, CancellationToken ct = default);

    /// <summary>Marca una habitación como inactiva (no la borra).</summary>
    Task DesactivarHabitacionAsync(Guid id, CancellationToken ct = default);

    /// <summary>Cambia solo el estado operativo de la habitación (mapa de recepción).</summary>
    Task CambiarEstadoHabitacionAsync(Guid id, EstadoHabitacion estado, CancellationToken ct = default);

    // --- Estadías (check-in / check-out) ---

    /// <summary>Estadía activa de una habitación (el huésped actual), o null si está libre.</summary>
    Task<EstadiaHabitacion?> ObtenerEstadiaActivaAsync(Guid habitacionId, CancellationToken ct = default);

    /// <summary>Obtiene una estadía por Id, o null.</summary>
    Task<EstadiaHabitacion?> ObtenerEstadiaAsync(Guid estadiaId, CancellationToken ct = default);

    /// <summary>Inserta o actualiza una estadía (check-in crea; check-out la cierra).</summary>
    Task GuardarEstadiaAsync(EstadiaHabitacion estadia, CancellationToken ct = default);

    // --- Consumos cargados a la habitación ---

    /// <summary>Lista los consumos de una estadía, del más reciente al más antiguo.</summary>
    Task<IReadOnlyList<ConsumoHabitacion>> ListarConsumosAsync(Guid estadiaId, CancellationToken ct = default);

    /// <summary>Agrega un consumo a la cuenta de la estadía.</summary>
    Task AgregarConsumoAsync(ConsumoHabitacion consumo, CancellationToken ct = default);

    /// <summary>Quita un consumo de la cuenta.</summary>
    Task QuitarConsumoAsync(Guid consumoId, CancellationToken ct = default);

    /// <summary>Suma de los importes de consumo de la estadía.</summary>
    Task<decimal> TotalConsumosAsync(Guid estadiaId, CancellationToken ct = default);
}
