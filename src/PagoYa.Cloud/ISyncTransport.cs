using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Canal de transporte hacia el backend de sincronización. Abstrae el HTTP/JSON
/// para poder probar el motor sin red (ver <see cref="TransporteSyncEnMemoria"/>)
/// y cambiar el backend sin tocar <see cref="CloudSyncService"/>.
/// </summary>
public interface ISyncTransport
{
    /// <summary>
    /// Sube un lote de eventos del outbox. Devuelve qué ids aceptó el backend
    /// (idempotente: reenviar un id ya aceptado debe volver a aceptarlo).
    /// </summary>
    Task<ResultadoLote> EnviarLoteAsync(IReadOnlyList<EventoSyncLocal> lote, CancellationToken ct = default);

    /// <summary>
    /// Descarga los cambios remotos posteriores a <paramref name="cursor"/> (null =
    /// desde el inicio) y devuelve el nuevo cursor para la próxima bajada.
    /// </summary>
    Task<PaqueteRemoto> DescargarCambiosAsync(string? cursor, CancellationToken ct = default);
}

/// <summary>Resultado de subir un lote: ids aceptados o error de transporte.</summary>
public sealed record ResultadoLote(bool Ok, IReadOnlyCollection<Guid> AceptadosIds, string? Error)
{
    public static ResultadoLote Exito(IReadOnlyCollection<Guid> ids) => new(true, ids, null);
    public static ResultadoLote Falla(string error) => new(false, Array.Empty<Guid>(), error);
}

/// <summary>Cambios remotos descargados + cursor para la siguiente bajada.</summary>
public sealed record PaqueteRemoto(IReadOnlyList<CambioRemoto> Cambios, string Cursor);

/// <summary>Parámetros del ciclo de sincronización.</summary>
public sealed class OpcionesSync
{
    /// <summary>Máximo de eventos por lote de subida.</summary>
    public int TamanoLote { get; set; } = 100;

    /// <summary>Intentos máximos por evento antes de moverlo a dead-letter.</summary>
    public int MaxIntentos { get; set; } = 5;

    /// <summary>URL base del backend de sync (para el transporte HTTP).</summary>
    public string? UrlBase { get; set; }

    /// <summary>Token/clave para autenticar la sincronización con el backend.</summary>
    public string? TokenLicencia { get; set; }
}
