using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IUsuarioRepository"/>. Tabla
/// 'usuarios'. El login del POS es offline: se valida contra el hash PBKDF2
/// guardado aquí (ver <see cref="PagoYa.Core.Common.Passwords"/>).
/// </summary>
public sealed class UsuarioRepository : IUsuarioRepository
{
    private readonly PagoYaDbContext _db;

    public UsuarioRepository(PagoYaDbContext db) => _db = db;

    private const string SelectUsuario = """
        SELECT id, nombre_usuario, nombre_completo, password_hash, password_salt,
               rol, activo, ultimo_acceso_utc, origen_caja_id, created_utc, updated_utc
        FROM usuarios
        """;

    /// <inheritdoc />
    public async Task<bool> ExisteAlgunoAsync(CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var n = await cx.ExecuteScalarAsync<long>(new CommandDefinition(
            "SELECT COUNT(*) FROM usuarios", cancellationToken: ct));
        return n > 0;
    }

    /// <inheritdoc />
    public async Task<int> ContarActivosAsync(CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var n = await cx.ExecuteScalarAsync<long>(new CommandDefinition(
            "SELECT COUNT(*) FROM usuarios WHERE activo = 1", cancellationToken: ct));
        return (int)n;
    }

    /// <inheritdoc />
    public async Task<Usuario?> ObtenerPorNombreAsync(string nombreUsuario, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaUsuario>(new CommandDefinition(
            $"{SelectUsuario} WHERE nombre_usuario = @n",
            new { n = (nombreUsuario ?? "").Trim().ToLowerInvariant() }, cancellationToken: ct));
        return fila?.A();
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<Usuario>> ListarAsync(CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaUsuario>(new CommandDefinition(
            $"{SelectUsuario} ORDER BY rol ASC, nombre_completo ASC", cancellationToken: ct));
        return filas.Select(f => f.A()).ToList();
    }

    /// <inheritdoc />
    public async Task GuardarAsync(Usuario u, CancellationToken ct = default)
    {
        u.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO usuarios
                (id, nombre_usuario, nombre_completo, password_hash, password_salt,
                 rol, activo, ultimo_acceso_utc, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @NombreUsuario, @NombreCompleto, @PasswordHash, @PasswordSalt,
                 @Rol, @Activo, @UltimoAcceso, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                nombre_usuario    = excluded.nombre_usuario,
                nombre_completo   = excluded.nombre_completo,
                password_hash     = excluded.password_hash,
                password_salt     = excluded.password_salt,
                rol               = excluded.rol,
                activo            = excluded.activo,
                ultimo_acceso_utc = excluded.ultimo_acceso_utc,
                updated_utc       = excluded.updated_utc
            """,
            new
            {
                Id = u.Id.ToString(),
                NombreUsuario = (u.NombreUsuario ?? "").Trim().ToLowerInvariant(),
                u.NombreCompleto,
                u.PasswordHash,
                u.PasswordSalt,
                Rol = (int)u.Rol,
                Activo = u.Activo ? 1 : 0,
                UltimoAcceso = u.UltimoAccesoUtc?.ToString("o"),
                u.OrigenCajaId,
                CreadoUtc = u.CreadoUtc.ToString("o"),
                ActualizadoUtc = u.ActualizadoUtc.ToString("o")
            }, cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task DesactivarAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE usuarios SET activo = 0, updated_utc = @u WHERE id = @id",
            new { id = id.ToString(), u = DateTime.UtcNow.ToString("o") }, cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task RegistrarAccesoAsync(Guid id, DateTime cuandoUtc, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE usuarios SET ultimo_acceso_utc = @c WHERE id = @id",
            new { id = id.ToString(), c = cuandoUtc.ToString("o") }, cancellationToken: ct));
    }

    /// <summary>Fila cruda de 'usuarios' para mapear con Dapper.</summary>
    private sealed class FilaUsuario
    {
        public string id { get; set; } = "";
        public string nombre_usuario { get; set; } = "";
        public string nombre_completo { get; set; } = "";
        public string password_hash { get; set; } = "";
        public string password_salt { get; set; } = "";
        public long rol { get; set; }
        public long activo { get; set; }
        public string? ultimo_acceso_utc { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public Usuario A() => new()
        {
            Id = Guid.Parse(id),
            NombreUsuario = nombre_usuario,
            NombreCompleto = nombre_completo,
            PasswordHash = password_hash,
            PasswordSalt = password_salt,
            Rol = (RolUsuario)rol,
            Activo = activo != 0,
            UltimoAccesoUtc = string.IsNullOrEmpty(ultimo_acceso_utc) ? null : DateTime.Parse(ultimo_acceso_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
            OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
        };
    }
}
