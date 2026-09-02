using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;

namespace PagoYa.Data.Repositorios;

/// <summary>Implementación SQLite (Dapper) de <see cref="IProveedorRepository"/>. Tabla 'proveedores'.</summary>
public sealed class ProveedorRepository : IProveedorRepository
{
    private readonly PagoYaDbContext _db;

    public ProveedorRepository(PagoYaDbContext db) => _db = db;

    private const string SelectBase = """
        SELECT id, nombre, ruc, contacto, telefono, direccion, notas, activo,
               origen_caja_id, created_utc, updated_utc
        FROM proveedores
        """;

    /// <inheritdoc />
    public async Task<IReadOnlyList<Proveedor>> ListarAsync(bool soloActivos = true, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var sql = soloActivos
            ? $"{SelectBase} WHERE activo = 1 ORDER BY nombre COLLATE NOCASE"
            : $"{SelectBase} ORDER BY nombre COLLATE NOCASE";
        var filas = await cx.QueryAsync<FilaProveedor>(new CommandDefinition(sql, cancellationToken: ct));
        return filas.Select(f => f.A()).ToList();
    }

    /// <inheritdoc />
    public async Task<Proveedor?> ObtenerPorIdAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaProveedor>(new CommandDefinition(
            $"{SelectBase} WHERE id = @id", new { id = id.ToString() }, cancellationToken: ct));
        return fila?.A();
    }

    /// <inheritdoc />
    public async Task GuardarAsync(Proveedor p, CancellationToken ct = default)
    {
        p.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO proveedores
                (id, nombre, ruc, contacto, telefono, direccion, notas, activo,
                 origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Nombre, @Ruc, @Contacto, @Telefono, @Direccion, @Notas, @Activo,
                 @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                nombre      = excluded.nombre,
                ruc         = excluded.ruc,
                contacto    = excluded.contacto,
                telefono    = excluded.telefono,
                direccion   = excluded.direccion,
                notas       = excluded.notas,
                activo      = excluded.activo,
                updated_utc = excluded.updated_utc
            """,
            new
            {
                Id = p.Id.ToString(),
                p.Nombre,
                p.Ruc,
                p.Contacto,
                p.Telefono,
                p.Direccion,
                p.Notas,
                Activo = p.Activo ? 1 : 0,
                p.OrigenCajaId,
                CreadoUtc = p.CreadoUtc.ToString("o"),
                ActualizadoUtc = p.ActualizadoUtc.ToString("o")
            }, cancellationToken: ct));
    }

    /// <inheritdoc />
    public async Task DesactivarAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE proveedores SET activo = 0, updated_utc = @u WHERE id = @id",
            new { id = id.ToString(), u = DateTime.UtcNow.ToString("o") }, cancellationToken: ct));
    }

    private sealed class FilaProveedor
    {
        public string id { get; set; } = "";
        public string nombre { get; set; } = "";
        public string? ruc { get; set; }
        public string? contacto { get; set; }
        public string? telefono { get; set; }
        public string? direccion { get; set; }
        public string? notas { get; set; }
        public long activo { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public Proveedor A() => new()
        {
            Id = Guid.Parse(id),
            Nombre = nombre,
            Ruc = ruc,
            Contacto = contacto,
            Telefono = telefono,
            Direccion = direccion,
            Notas = notas,
            Activo = activo != 0,
            OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, System.Globalization.DateTimeStyles.RoundtripKind),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, System.Globalization.DateTimeStyles.RoundtripKind)
        };
    }
}
