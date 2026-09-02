using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Backend de sincronización SIMULADO en memoria. Acepta los lotes subidos y los
/// devuelve como cambios remotos descargables (útil para consolidar dos cajas en
/// pruebas y para operar en modo demo/offline). NO persiste entre reinicios.
///
/// El cursor es el índice incremental del registro global de cambios.
/// </summary>
public sealed class TransporteSyncEnMemoria : ISyncTransport
{
    private readonly List<CambioRemoto> _registro = new();
    private readonly ConcurrentDictionary<Guid, byte> _aceptados = new();
    private readonly object _candado = new();

    /// <summary>Origen a excluir en la bajada (no me devuelvo mis propios cambios).</summary>
    public string? ExcluirOrigen { get; set; }

    public Task<ResultadoLote> EnviarLoteAsync(IReadOnlyList<EventoSyncLocal> lote, CancellationToken ct = default)
    {
        var ids = new List<Guid>(lote.Count);
        lock (_candado)
        {
            foreach (var e in lote)
            {
                // Idempotencia: un evento ya aceptado no se re-registra.
                if (_aceptados.TryAdd(e.Id, 0))
                    _registro.Add(new CambioRemoto(e.Entidad, e.EntidadId, e.Operacion,
                        e.PayloadJson, ExtraerActualizado(e), e.OrigenCajaId));
                ids.Add(e.Id);
            }
        }
        return Task.FromResult(ResultadoLote.Exito(ids));
    }

    public Task<PaqueteRemoto> DescargarCambiosAsync(string? cursor, CancellationToken ct = default)
    {
        var desde = int.TryParse(cursor, NumberStyles.Integer, CultureInfo.InvariantCulture, out var c) ? c : 0;
        List<CambioRemoto> nuevos;
        int total;
        lock (_candado)
        {
            total = _registro.Count;
            nuevos = _registro
                .Skip(desde)
                .Where(x => ExcluirOrigen is null || !string.Equals(x.OrigenCajaId, ExcluirOrigen, StringComparison.OrdinalIgnoreCase))
                .ToList();
        }
        return Task.FromResult(new PaqueteRemoto(nuevos, total.ToString(CultureInfo.InvariantCulture)));
    }

    /// <summary>Extrae ActualizadoUtc del snapshot (para LWW); si no está, usa el created del evento.</summary>
    private static DateTime ExtraerActualizado(EventoSyncLocal e)
    {
        try
        {
            using var doc = JsonDocument.Parse(e.PayloadJson);
            if (doc.RootElement.TryGetProperty("ActualizadoUtc", out var prop) &&
                prop.TryGetDateTime(out var dt))
                return dt.ToUniversalTime();
        }
        catch (JsonException) { /* payload sin ese campo (ej. DELETE) */ }
        return e.CreadoUtc;
    }
}
