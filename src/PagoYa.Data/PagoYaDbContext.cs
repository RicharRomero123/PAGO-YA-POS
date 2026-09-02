using System.Reflection;
using Microsoft.Data.Sqlite;

namespace PagoYa.Data;

/// <summary>
/// Punto central de acceso a la base de datos SQLite local. Gestiona la cadena
/// de conexión y la inicialización del esquema (ejecuta Esquema/esquema.sql,
/// embebido como recurso, en el primer arranque).
///
/// No es un DbContext de EF Core: es una fábrica ligera de <see cref="SqliteConnection"/>
/// pensada para usarse con Dapper. Nombre "DbContext" solo por familiaridad.
/// Implementación de detalle a completar por desktop-dev.
/// </summary>
public sealed class PagoYaDbContext
{
    private readonly string _connectionString;

    /// <param name="rutaArchivoDb">Ruta al archivo .db (ej. %APPDATA%/PagoYa/pagoya.db).</param>
    public PagoYaDbContext(string rutaArchivoDb)
    {
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = rutaArchivoDb,
            Mode = SqliteOpenMode.ReadWriteCreate,
            ForeignKeys = true
        }.ToString();
    }

    /// <summary>Abre una nueva conexión SQLite lista para usar con Dapper.</summary>
    public SqliteConnection CrearConexion()
    {
        var conexion = new SqliteConnection(_connectionString);
        conexion.Open();
        AplicarPragmas(conexion);
        return conexion;
    }

    /// <summary>
    /// Abre una nueva conexión SQLite de forma asíncrona (para I/O en el POS).
    /// El llamador es responsable de liberar la conexión (using await).
    /// </summary>
    public async Task<SqliteConnection> CrearConexionAsync(CancellationToken ct = default)
    {
        var conexion = new SqliteConnection(_connectionString);
        await conexion.OpenAsync(ct).ConfigureAwait(false);
        AplicarPragmas(conexion);
        return conexion;
    }

    /// <summary>
    /// Aplica los PRAGMAs por conexión. En SQLite, foreign_keys se activa por
    /// conexión (aunque el connection string ya lo pide, lo reforzamos) y WAL
    /// mejora la concurrencia lectura/escritura del POS. journal_mode es
    /// persistente a nivel de archivo, pero re-emitirlo es idempotente y barato.
    /// </summary>
    private static void AplicarPragmas(SqliteConnection conexion)
    {
        using var cmd = conexion.CreateCommand();
        cmd.CommandText = "PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;";
        cmd.ExecuteNonQuery();
    }

    /// <summary>
    /// Crea/actualiza el esquema ejecutando el script SQL embebido. Idempotente
    /// (usa CREATE TABLE IF NOT EXISTS). Llamar una vez al arranque.
    /// </summary>
    public void InicializarEsquema()
    {
        var sql = LeerScriptEsquemaEmbebido();
        using var conexion = CrearConexion();
        using (var comando = conexion.CreateCommand())
        {
            comando.CommandText = sql;
            comando.ExecuteNonQuery();
        }

        // Migraciones aditivas para BDs ya existentes (CREATE TABLE IF NOT EXISTS
        // no agrega columnas nuevas). Se añaden columnas solo si faltan.
        AsegurarColumna(conexion, "productos", "imagen_ruta", "TEXT NULL");
        AsegurarColumna(conexion, "productos", "proveedor_id", "TEXT NULL");
        // Descuento por producto: tipo (0 ninguno / 1 % / 2 oferta) + valor.
        AsegurarColumna(conexion, "productos", "tipo_descuento", "INTEGER NOT NULL DEFAULT 0");
        AsegurarColumna(conexion, "productos", "descuento_valor", "REAL NOT NULL DEFAULT 0");
        // Umbral de reposición + campos farmacéuticos (rubro farmacia/botica).
        AsegurarColumna(conexion, "productos", "stock_minimo", "REAL NOT NULL DEFAULT 0");
        AsegurarColumna(conexion, "productos", "fecha_vencimiento", "TEXT NULL");
        AsegurarColumna(conexion, "productos", "lote", "TEXT NULL");
        AsegurarColumna(conexion, "productos", "registro_sanitario", "TEXT NULL");
        AsegurarColumna(conexion, "productos", "principio_activo", "TEXT NULL");
        AsegurarColumna(conexion, "productos", "requiere_receta", "INTEGER NOT NULL DEFAULT 0");
        // Personalización (modificadores JSON) del rubro restaurante/comida.
        AsegurarColumna(conexion, "productos", "personalizacion_json", "TEXT NULL");
        AsegurarColumna(conexion, "habitaciones", "imagen_ruta", "TEXT NULL");
        AsegurarColumna(conexion, "habitaciones", "comodidades", "TEXT NULL");
    }

    /// <summary>Agrega una columna a una tabla si aún no existe (idempotente).</summary>
    private static void AsegurarColumna(SqliteConnection cx, string tabla, string columna, string definicion)
    {
        using (var check = cx.CreateCommand())
        {
            check.CommandText = $"SELECT COUNT(*) FROM pragma_table_info('{tabla}') WHERE name = @c";
            check.Parameters.AddWithValue("@c", columna);
            var existe = Convert.ToInt64(check.ExecuteScalar()) > 0;
            if (existe) return;
        }
        using var alter = cx.CreateCommand();
        alter.CommandText = $"ALTER TABLE {tabla} ADD COLUMN {columna} {definicion}";
        alter.ExecuteNonQuery();
    }

    /// <summary>Lee el contenido de Esquema/esquema.sql embebido en el ensamblado.</summary>
    private static string LeerScriptEsquemaEmbebido()
    {
        var asm = Assembly.GetExecutingAssembly();
        // El nombre del recurso incluye el default namespace del ensamblado.
        var nombreRecurso = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("esquema.sql", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("No se encontró el recurso embebido 'esquema.sql'.");

        using var stream = asm.GetManifestResourceStream(nombreRecurso)!;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
