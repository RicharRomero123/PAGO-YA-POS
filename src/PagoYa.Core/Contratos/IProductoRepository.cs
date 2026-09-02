using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Repositorio de <see cref="Producto"/>. Abstrae la persistencia local
/// (SQLite) del resto de la app. Implementa: desktop-dev (PagoYa.Data).
/// </summary>
public interface IProductoRepository
{
    /// <summary>Obtiene un producto por su Id, o null si no existe.</summary>
    Task<Producto?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Busca un producto por su código de barras/SKU (búsqueda rápida en el POS).</summary>
    Task<Producto?> ObtenerPorCodigoAsync(string codigo, CancellationToken ct = default);

    /// <summary>Lista productos activos, con filtro opcional por texto (nombre/código).</summary>
    Task<IReadOnlyList<Producto>> BuscarAsync(string? filtro = null, CancellationToken ct = default);

    /// <summary>Inserta o actualiza un producto (upsert).</summary>
    Task GuardarAsync(Producto producto, CancellationToken ct = default);

    /// <summary>Marca un producto como inactivo (borrado lógico).</summary>
    Task DesactivarAsync(Guid id, CancellationToken ct = default);
}
