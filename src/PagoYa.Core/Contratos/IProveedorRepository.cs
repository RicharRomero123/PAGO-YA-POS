using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>Persistencia de proveedores. Implementa: PagoYa.Data (SQLite tabla 'proveedores').</summary>
public interface IProveedorRepository
{
    /// <summary>Lista proveedores (por defecto solo activos), ordenados por nombre.</summary>
    Task<IReadOnlyList<Proveedor>> ListarAsync(bool soloActivos = true, CancellationToken ct = default);

    /// <summary>Obtiene un proveedor por Id, o null.</summary>
    Task<Proveedor?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Inserta o actualiza un proveedor (upsert por Id).</summary>
    Task GuardarAsync(Proveedor proveedor, CancellationToken ct = default);

    /// <summary>Marca un proveedor como inactivo (no borra).</summary>
    Task DesactivarAsync(Guid id, CancellationToken ct = default);
}
