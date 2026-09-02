using System.Data;
using System.Text.Json;
using Dapper;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Helper para el <b>outbox pattern</b> (ver docs/ARQUITECTURA.md §4).
///
/// Cada escritura de negocio que deba sincronizarse a la nube registra aquí una
/// fila con el snapshot serializado (payload_json) de la entidad, en la MISMA
/// transacción que la escritura de negocio: así nunca hay una venta sin su
/// evento de outbox (consistencia transaccional).
///
/// En el tier Base la tabla existe pero <c>ISyncService</c> es un no-op, de modo
/// que las filas quedan 'pendientes' y se enviarán en cuanto se active Cloud.
/// </summary>
internal static class OutboxHelper
{
    private static readonly JsonSerializerOptions OpcionesJson = new()
    {
        WriteIndented = false
    };

    /// <summary>
    /// Inserta un evento de outbox dentro de la transacción indicada. Debe
    /// llamarse antes del commit de la escritura de negocio asociada.
    /// </summary>
    public static async Task RegistrarAsync(
        IDbConnection cx,
        IDbTransaction tx,
        string entidad,
        Guid entidadId,
        string operacion,
        object payload,
        string origenCajaId,
        CancellationToken ct)
    {
        const string sql = """
            INSERT INTO outbox_sync
                (id, entidad, entidad_id, operacion, payload_json, estado, intentos,
                 origen_caja_id, created_utc, enviado_utc)
            VALUES
                (@id, @entidad, @entidad_id, @operacion, @payload_json, 0, 0,
                 @origen_caja_id, @created_utc, NULL)
            """;

        await cx.ExecuteAsync(new CommandDefinition(sql, new
        {
            id = Guid.NewGuid().ToString(),
            entidad,
            entidad_id = entidadId.ToString(),
            operacion,
            payload_json = JsonSerializer.Serialize(payload, payload.GetType(), OpcionesJson),
            origen_caja_id = origenCajaId,
            created_utc = DateTime.UtcNow.ToString("o")
        }, tx, cancellationToken: ct));
    }
}
