namespace PagoYa.Core.Contratos;

/// <summary>
/// Acceso al <b>outbox</b> local y a la aplicación de cambios remotos, para el
/// motor de sincronización (<see cref="ISyncService"/>). Se abstrae aquí para que
/// PagoYa.Cloud no dependa de la capa de datos; lo implementa PagoYa.Data sobre
/// SQLite (tabla <c>outbox_sync</c> + cursor en <c>meta</c>).
/// </summary>
public interface IOutboxStore
{
    /// <summary>Lee hasta <paramref name="max"/> eventos pendientes (estado=0), más antiguos primero.</summary>
    Task<IReadOnlyList<EventoSyncLocal>> LeerPendientesAsync(int max, CancellationToken ct = default);

    /// <summary>Marca eventos como enviados (estado=1, enviado_utc=now). Idempotente.</summary>
    Task MarcarEnviadosAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct = default);

    /// <summary>
    /// Registra un intento fallido: incrementa 'intentos'. Al superar
    /// <paramref name="maxIntentos"/> mueve el evento a estado=2 (dead-letter) para
    /// que no bloquee la cola; por debajo lo deja pendiente para reintento.
    /// </summary>
    Task RegistrarFalloAsync(IReadOnlyCollection<Guid> ids, int maxIntentos, CancellationToken ct = default);

    /// <summary>
    /// Aplica cambios remotos a las tablas locales con resolución
    /// <b>last-write-wins</b> (por <c>updated_utc</c>). Devuelve cuántos se aplicaron.
    /// </summary>
    Task<int> AplicarCambiosRemotosAsync(IReadOnlyList<CambioRemoto> cambios, CancellationToken ct = default);

    /// <summary>Cursor de la última sincronización de bajada (o null si nunca sincronizó).</summary>
    Task<string?> LeerCursorAsync(CancellationToken ct = default);

    /// <summary>Persiste el cursor de bajada tras aplicar los cambios remotos.</summary>
    Task GuardarCursorAsync(string cursor, CancellationToken ct = default);
}

/// <summary>Evento pendiente del outbox local listo para subir a la nube.</summary>
public sealed record EventoSyncLocal(
    Guid Id,
    string Entidad,
    Guid EntidadId,
    string Operacion,
    string PayloadJson,
    int Intentos,
    string OrigenCajaId,
    DateTime CreadoUtc);

/// <summary>
/// Cambio descargado de la nube para aplicar localmente. <see cref="ActualizadoUtc"/>
/// es la marca para el last-write-wins; <see cref="PayloadJson"/> es el snapshot
/// serializado de la entidad (mismo formato que escribe el outbox).
/// </summary>
public sealed record CambioRemoto(
    string Entidad,
    Guid EntidadId,
    string Operacion,
    string PayloadJson,
    DateTime ActualizadoUtc,
    string OrigenCajaId);
