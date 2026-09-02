namespace PagoYa.Core.Contratos;

/// <summary>
/// Servicio de sincronización con la nube (respaldo, multi-caja, reportes
/// móviles). Implementa el <b>outbox pattern</b>: las escrituras locales se
/// registran en una tabla outbox y este servicio las envía a la nube de forma
/// eventual, resolviendo conflictos por last-write-wins usando UUID + timestamps.
///
/// FEATURE-GATED: solo activo con el flag "cloud_sync". Sin él se usa el
/// patrón Null Object (no-op) para que el core no dependa de la nube.
///
/// Implementa: licensing-backend / cloud-dev (PagoYa.Cloud).
/// </summary>
public interface ISyncService
{
    /// <summary>True si la sincronización está habilitada por la licencia.</summary>
    bool SincronizacionHabilitada { get; }

    /// <summary>
    /// Envía a la nube los cambios pendientes en el outbox local y descarga
    /// los cambios remotos aplicables. Idempotente y reanudable.
    /// </summary>
    /// <param name="ct">Token de cancelación.</param>
    /// <returns>Resumen de la sincronización.</returns>
    Task<ResultadoSync> SincronizarAsync(CancellationToken ct = default);
}

/// <summary>Resumen del resultado de un ciclo de sincronización.</summary>
public sealed class ResultadoSync
{
    /// <summary>True si el ciclo terminó sin errores.</summary>
    public bool Exito { get; init; }

    /// <summary>Cantidad de registros enviados a la nube.</summary>
    public int Enviados { get; init; }

    /// <summary>Cantidad de registros recibidos de la nube.</summary>
    public int Recibidos { get; init; }

    /// <summary>Mensaje legible (para soporte).</summary>
    public string? Mensaje { get; init; }

    /// <summary>
    /// Código de error machine-readable devuelto por el backend, cuando lo hubo
    /// (catálogo estable en <c>server/README.md §10</c>; p. ej.
    /// <c>sin_flag_cloud_sync</c> → upsell, <c>asiento_revocado</c> → volver a
    /// vincular el equipo). Null si el ciclo fue bien, si el fallo fue de red o
    /// si el backend es anterior al catálogo.
    ///
    /// La UI debe ramificar por este campo, <b>nunca</b> por el texto de
    /// <see cref="Mensaje"/>, que se reescribe y algún día se traduce.
    /// </summary>
    public string? CodigoError { get; init; }

    /// <summary>Resultado que indica que la sync no está habilitada por licencia.</summary>
    public static ResultadoSync NoHabilitado() => new()
    {
        Exito = false,
        Mensaje = "El respaldo en la nube requiere el plan PagoYa Cloud."
    };
}
