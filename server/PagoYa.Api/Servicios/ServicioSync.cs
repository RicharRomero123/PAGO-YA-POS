using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Servicios;

/// <summary>
/// Lógica de sincronización server-side: recibe el outbox de las cajas (push,
/// idempotente por evento) y sirve los cambios pendientes por cursor (pull),
/// aislados por licencia (tenant). No conoce HTTP.
/// </summary>
public sealed class ServicioSync
{
    /// <summary>Máximo de cambios devueltos por pull (el cliente reitera con el nuevo cursor).</summary>
    public const int MaxPorPull = 500;

    private readonly LicenciasDbContext _db;
    private readonly ILogger<ServicioSync> _log;

    public ServicioSync(LicenciasDbContext db, ILogger<ServicioSync> log)
    {
        _db = db;
        _log = log;
    }

    /// <summary>
    /// Registra los eventos del lote que aún no existan (idempotencia por
    /// (licencia, id de evento del cliente)) y devuelve TODOS los ids como aceptados.
    /// </summary>
    public async Task<SyncPushResponse> ProcesarPushAsync(Guid licenciaId, SyncPushRequest req, CancellationToken ct)
    {
        var ids = req.Eventos.Select(e => e.Id).ToList();
        if (ids.Count == 0)
            return new SyncPushResponse { Aceptados = ids };

        var existentes = await _db.EventosSync
            .Where(e => e.LicenciaId == licenciaId && ids.Contains(e.EventoIdCliente))
            .Select(e => e.EventoIdCliente)
            .ToListAsync(ct);
        var vistos = existentes.ToHashSet();

        var nuevos = 0;
        foreach (var e in req.Eventos)
        {
            if (!vistos.Add(e.Id)) continue; // duplicado (ya en BD o repetido en el lote)

            _db.EventosSync.Add(new EventoSync
            {
                LicenciaId = licenciaId,
                EventoIdCliente = e.Id,
                Entidad = e.Entidad,
                EntidadId = e.EntidadId,
                Operacion = e.Operacion,
                PayloadJson = e.PayloadJson,
                OrigenCajaId = e.OrigenCajaId,
                ActualizadoUtc = ExtraerActualizado(e.PayloadJson, e.CreadoUtc)
            });
            nuevos++;
        }

        if (nuevos > 0) await _db.SaveChangesAsync(ct);
        _log.LogInformation("Sync push licencia {Lic}: {Nuevos} nuevos de {Total}", licenciaId, nuevos, ids.Count);

        // Idempotente: aceptamos todo lo solicitado (lo previo ya estaba almacenado).
        return new SyncPushResponse { Aceptados = ids };
    }

    /// <summary>Devuelve los cambios de la licencia con secuencia mayor al cursor.</summary>
    public async Task<SyncPullResponse> ObtenerCambiosAsync(Guid licenciaId, string? cursor, CancellationToken ct)
    {
        var desde = long.TryParse(cursor, out var c) ? c : 0L;

        var eventos = await _db.EventosSync
            .Where(e => e.LicenciaId == licenciaId && e.Secuencia > desde)
            .OrderBy(e => e.Secuencia)
            .Take(MaxPorPull)
            .ToListAsync(ct);

        var cambios = eventos.Select(e => new CambioRemotoDto
        {
            Entidad = e.Entidad,
            EntidadId = e.EntidadId,
            Operacion = e.Operacion,
            PayloadJson = e.PayloadJson,
            ActualizadoUtc = e.ActualizadoUtc,
            OrigenCajaId = e.OrigenCajaId
        }).ToList();

        var nuevoCursor = eventos.Count > 0
            ? eventos[^1].Secuencia.ToString()
            : (cursor ?? "0");

        return new SyncPullResponse { Cambios = cambios, Cursor = nuevoCursor };
    }

    /// <summary>
    /// Extrae ActualizadoUtc del snapshot (para last-write-wins). El payload es la
    /// entidad serializada en PascalCase; si no trae el campo (ej. DELETE) usa el
    /// created del evento. Idéntico criterio al del transporte en memoria del cliente.
    /// </summary>
    private static DateTime ExtraerActualizado(string payloadJson, DateTime fallback)
    {
        try
        {
            using var doc = JsonDocument.Parse(payloadJson);
            if (doc.RootElement.TryGetProperty("ActualizadoUtc", out var prop) &&
                prop.TryGetDateTime(out var dt))
                return dt.ToUniversalTime();
        }
        catch (JsonException) { /* payload sin ese campo */ }
        return fallback;
    }
}
