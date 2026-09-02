using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Repositorio de sesiones de <see cref="Caja"/> y sus
/// <see cref="MovimientoCaja"/>. Implementa: desktop-dev.
/// </summary>
public interface ICajaRepository
{
    /// <summary>Obtiene la sesión de caja actualmente abierta, o null si no hay ninguna.</summary>
    Task<Caja?> ObtenerCajaAbiertaAsync(CancellationToken ct = default);

    /// <summary>Obtiene una sesión de caja por Id.</summary>
    Task<Caja?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Abre una nueva sesión de caja con su fondo inicial.</summary>
    Task AbrirCajaAsync(Caja caja, CancellationToken ct = default);

    /// <summary>Cierra la sesión de caja (registra arqueo y diferencia).</summary>
    Task CerrarCajaAsync(Caja caja, CancellationToken ct = default);

    /// <summary>Registra un movimiento de efectivo en la caja.</summary>
    Task RegistrarMovimientoAsync(MovimientoCaja movimiento, CancellationToken ct = default);

    /// <summary>Lista los movimientos de una sesión de caja.</summary>
    Task<IReadOnlyList<MovimientoCaja>> ListarMovimientosAsync(Guid cajaId, CancellationToken ct = default);

    /// <summary>
    /// Lista las sesiones de caja cuya fecha de apertura (local) cae en el rango
    /// [desde, hasta] inclusive, más recientes primero. Para el historial.
    /// </summary>
    Task<IReadOnlyList<Caja>> ListarSesionesAsync(DateOnly desde, DateOnly hasta, CancellationToken ct = default);
}
