using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Patrón <b>Null Object</b> de <see cref="ISyncService"/>. Se inyecta cuando la
/// licencia NO habilita "cloud_sync". Es un no-op: no sincroniza nada y reporta
/// que la función requiere el plan Cloud. Mantiene el core desacoplado de la nube.
/// </summary>
public sealed class SyncServiceDeshabilitado : ISyncService
{
    /// <inheritdoc />
    public bool SincronizacionHabilitada => false;

    /// <inheritdoc />
    public Task<ResultadoSync> SincronizarAsync(CancellationToken ct = default)
        => Task.FromResult(ResultadoSync.NoHabilitado());
}
