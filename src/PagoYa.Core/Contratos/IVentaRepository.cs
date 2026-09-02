using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Repositorio de <see cref="Venta"/> (con su detalle). Implementa: desktop-dev.
/// </summary>
public interface IVentaRepository
{
    /// <summary>Obtiene una venta con sus detalles, o null si no existe.</summary>
    Task<Venta?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>
    /// Registra una venta completa (cabecera + detalles) de forma atómica.
    /// La implementación debe usar una transacción y actualizar inventario.
    /// </summary>
    Task RegistrarAsync(Venta venta, CancellationToken ct = default);

    /// <summary>Lista las ventas de una sesión de caja.</summary>
    Task<IReadOnlyList<Venta>> ListarPorCajaAsync(Guid cajaId, CancellationToken ct = default);

    /// <summary>Anula una venta (borrado lógico + reversa de inventario).</summary>
    Task AnularAsync(Guid id, CancellationToken ct = default);
}
