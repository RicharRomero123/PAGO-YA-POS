using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Servicio real de sincronización con la nube (outbox pattern). Se instancia
/// SOLO cuando la licencia habilita el flag "cloud_sync".
///
/// Ciclo de <see cref="SincronizarAsync"/>:
///   1. PUSH: lee el outbox pendiente por lotes y lo sube; marca los aceptados
///      como enviados (idempotente) y cuenta los intentos fallidos (dead-letter
///      al superar el máximo) para no bloquear la cola.
///   2. PULL: descarga los cambios remotos desde el cursor y los aplica localmente
///      con last-write-wins; avanza el cursor.
///
/// Es reanudable: lo enviado queda marcado, así que un corte a mitad no reenvía
/// ni pierde. El transporte se inyecta (HTTP real o simulado offline).
/// </summary>
public sealed class CloudSyncService : ISyncService
{
    private readonly IOutboxStore _outbox;
    private readonly ISyncTransport _transporte;
    private readonly OpcionesSync _opciones;

    public CloudSyncService(IOutboxStore outbox, ISyncTransport transporte, OpcionesSync? opciones = null)
    {
        _outbox = outbox;
        _transporte = transporte;
        _opciones = opciones ?? new OpcionesSync();
    }

    /// <inheritdoc />
    public bool SincronizacionHabilitada => true;

    /// <inheritdoc />
    public async Task<ResultadoSync> SincronizarAsync(CancellationToken ct = default)
    {
        try
        {
            var enviados = await SubirPendientesAsync(ct);
            var recibidos = await BajarCambiosAsync(ct);

            return new ResultadoSync
            {
                Exito = true,
                Enviados = enviados,
                Recibidos = recibidos,
                Mensaje = $"Sincronización completa: {enviados} enviados, {recibidos} recibidos."
            };
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new ResultadoSync { Exito = false, Mensaje = $"Error de sincronización: {ex.Message}" };
        }
    }

    /// <summary>PUSH: sube el outbox por lotes hasta vaciarlo o hasta un fallo de transporte.</summary>
    private async Task<int> SubirPendientesAsync(CancellationToken ct)
    {
        var enviados = 0;
        while (true)
        {
            ct.ThrowIfCancellationRequested();

            var lote = await _outbox.LeerPendientesAsync(_opciones.TamanoLote, ct);
            if (lote.Count == 0) break;

            var res = await _transporte.EnviarLoteAsync(lote, ct);
            if (!res.Ok)
            {
                // Fallo de transporte: cuenta el intento y corta (se reintenta luego).
                await _outbox.RegistrarFalloAsync(
                    lote.Select(e => e.Id).ToArray(), _opciones.MaxIntentos, ct);
                throw new SyncTransporteException(res.Error ?? "fallo de transporte en push");
            }

            var aceptados = new HashSet<Guid>(res.AceptadosIds);
            if (aceptados.Count > 0)
            {
                await _outbox.MarcarEnviadosAsync(res.AceptadosIds, ct);
                enviados += aceptados.Count;
            }

            // Rechazados por el backend (no aceptados): cuentan intento / dead-letter.
            var rechazados = lote.Where(e => !aceptados.Contains(e.Id)).Select(e => e.Id).ToArray();
            if (rechazados.Length > 0)
                await _outbox.RegistrarFalloAsync(rechazados, _opciones.MaxIntentos, ct);

            // Último lote (incompleto): no hay más pendientes que leer.
            if (lote.Count < _opciones.TamanoLote) break;
        }
        return enviados;
    }

    /// <summary>PULL: descarga cambios desde el cursor y los aplica con LWW.</summary>
    private async Task<int> BajarCambiosAsync(CancellationToken ct)
    {
        var cursor = await _outbox.LeerCursorAsync(ct);
        var paquete = await _transporte.DescargarCambiosAsync(cursor, ct);

        var recibidos = paquete.Cambios.Count == 0
            ? 0
            : await _outbox.AplicarCambiosRemotosAsync(paquete.Cambios, ct);

        await _outbox.GuardarCursorAsync(paquete.Cursor, ct);
        return recibidos;
    }
}

/// <summary>Fallo de transporte durante el push (se convierte en ResultadoSync fallido).</summary>
public sealed class SyncTransporteException : Exception
{
    public SyncTransporteException(string mensaje) : base(mensaje) { }
}
