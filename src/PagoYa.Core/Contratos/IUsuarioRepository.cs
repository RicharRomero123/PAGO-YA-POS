using PagoYa.Core.Entidades;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Persistencia de los usuarios locales del POS (login offline). Implementa:
/// desktop-dev / PagoYa.Data (SQLite tabla 'usuarios').
/// </summary>
public interface IUsuarioRepository
{
    /// <summary>¿Existe al menos un usuario? False en el primer arranque (mostrar setup).</summary>
    Task<bool> ExisteAlgunoAsync(CancellationToken ct = default);

    /// <summary>Cantidad de usuarios ACTIVOS (para el límite del tier Base).</summary>
    Task<int> ContarActivosAsync(CancellationToken ct = default);

    /// <summary>Busca un usuario por su nombre de login (case-insensitive). Null si no existe.</summary>
    Task<Usuario?> ObtenerPorNombreAsync(string nombreUsuario, CancellationToken ct = default);

    /// <summary>Lista todos los usuarios (activos e inactivos), para la gestión.</summary>
    Task<IReadOnlyList<Usuario>> ListarAsync(CancellationToken ct = default);

    /// <summary>Inserta o actualiza un usuario (upsert por Id).</summary>
    Task GuardarAsync(Usuario usuario, CancellationToken ct = default);

    /// <summary>Marca un usuario como inactivo (no borra: preserva historial).</summary>
    Task DesactivarAsync(Guid id, CancellationToken ct = default);

    /// <summary>Actualiza la marca de último acceso tras un login exitoso.</summary>
    Task RegistrarAccesoAsync(Guid id, DateTime cuandoUtc, CancellationToken ct = default);
}
