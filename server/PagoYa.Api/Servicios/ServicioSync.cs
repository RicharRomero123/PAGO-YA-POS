using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Servicios;

/// <summary>
/// Catálogo canónico de entidades sincronizables. Es el <b>contrato compartido</b>
/// entre el POS de escritorio (<c>src/PagoYa.Data/Repositorios/OutboxStore.cs</c>),
/// el móvil (<c>pagoya_core/lib/datos/</c>) y este backend: los tres deben usar
/// EXACTAMENTE estos nombres (snake_case, singular).
///
/// El server NO descarta eventos de entidades fuera del catálogo (perder datos del
/// cliente sería peor que aceptarlos): los almacena igual y los reporta en
/// <c>SyncPushResponse.EntidadesDesconocidas</c> para detectar desalineación.
/// </summary>
public static class EntidadesSync
{
    /// <summary>Entidades que el desktop ya consolidaba antes del móvil.</summary>
    public const string Producto = "producto";
    public const string Venta = "venta";
    public const string Caja = "caja";
    public const string MovimientoCaja = "movimiento_caja";
    public const string Inventario = "inventario";

    /// <summary>Comandas: el caso de uso estrella del móvil (mozo tomando pedidos).</summary>
    public const string Mesa = "mesa";
    public const string Pedido = "pedido";
    public const string PedidoLinea = "pedido_linea";

    /// <summary>Rubro hotel (ya emitidas por el desktop).</summary>
    public const string Habitacion = "habitacion";
    public const string EstadiaHabitacion = "estadia_habitacion";

    public static readonly IReadOnlySet<string> Catalogo = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        Producto, Venta, Caja, MovimientoCaja, Inventario,
        Mesa, Pedido, PedidoLinea,
        Habitacion, EstadiaHabitacion
    };

    public static bool EsConocida(string? entidad) =>
        !string.IsNullOrWhiteSpace(entidad) && Catalogo.Contains(entidad.Trim());
}

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
        var desconocidas = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in req.Eventos)
        {
            if (!EntidadesSync.EsConocida(e.Entidad))
                desconocidas.Add(e.Entidad);

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

        if (desconocidas.Count > 0)
            _log.LogWarning("Sync push licencia {Lic}: entidades fuera del catálogo: {Entidades}",
                licenciaId, string.Join(", ", desconocidas));

        // Idempotente: aceptamos todo lo solicitado (lo previo ya estaba almacenado).
        return new SyncPushResponse
        {
            Aceptados = ids,
            EntidadesDesconocidas = desconocidas.ToList()
        };
    }

    /// <summary>
    /// Devuelve los cambios de la licencia con secuencia mayor al cursor,
    /// <b>excluyendo los que subió el propio solicitante</b> (filtro de eco).
    ///
    /// <para><paramref name="origen"/> es el <c>origen_caja_id</c> del dispositivo que
    /// consulta —el mismo valor que estampa en los eventos que sube—. Sin él, con PC
    /// y móvil sobre la misma licencia, cada equipo se re-descargaba sus propias
    /// escrituras: tráfico duplicado y riesgo de que un LWW tardío pise un dato más
    /// nuevo. Si viene vacío se conserva el comportamiento histórico (sin filtrar),
    /// para no romper a los clientes de escritorio que aún no envían el parámetro.</para>
    ///
    /// <para>El cursor avanza sobre la ventana <b>sin filtrar</b>: los eventos propios
    /// se saltan definitivamente en vez de re-escanearse en cada pull. Por eso una
    /// página puede devolver menos de <see cref="MaxPorPull"/> cambios (o ninguno) y
    /// aun así mover el cursor hacia adelante.</para>
    ///
    /// <para><b>Cursor adelantado (auto-reparación):</b> si el cliente manda un cursor
    /// mayor que la secuencia máxima de su licencia —BD corrupta, restauración de un
    /// backup, tenant equivocado—, se le devuelve el máximo REAL en vez de repetirle
    /// el valor recibido. Devolverlo tal cual dejaba al dispositivo clavado para
    /// siempre en un cursor inalcanzable, sin forma de repararse solo. No se
    /// re-entregan eventos anteriores: solo se destraba el futuro.</para>
    /// </summary>
    public async Task<SyncPullResponse> ObtenerCambiosAsync(
        Guid licenciaId, string? cursor, string? origen, CancellationToken ct)
    {
        var desde = long.TryParse(cursor, out var c) && c > 0 ? c : 0L;

        var ventana = await _db.EventosSync
            .Where(e => e.LicenciaId == licenciaId && e.Secuencia > desde)
            .OrderBy(e => e.Secuencia)
            .Take(MaxPorPull)
            .ToListAsync(ct);

        var propio = origen?.Trim();
        var cambios = ventana
            .Where(e => string.IsNullOrEmpty(propio) ||
                        !string.Equals(e.OrigenCajaId, propio, StringComparison.OrdinalIgnoreCase))
            .Select(e => new CambioRemotoDto
            {
                Entidad = e.Entidad,
                EntidadId = e.EntidadId,
                Operacion = e.Operacion,
                PayloadJson = e.PayloadJson,
                ActualizadoUtc = e.ActualizadoUtc,
                OrigenCajaId = e.OrigenCajaId
            }).ToList();

        long nuevoCursor;
        if (ventana.Count > 0)
        {
            nuevoCursor = ventana[^1].Secuencia;
        }
        else
        {
            // Ventana vacía: o el cliente ya está al día, o su cursor quedó por
            // delante de la secuencia real. Acotamos al máximo de la licencia (0 si
            // aún no hay eventos) para que un cursor corrupto se auto-repare.
            var maxSecuencia = await _db.EventosSync
                .Where(e => e.LicenciaId == licenciaId)
                .MaxAsync(e => (long?)e.Secuencia, ct) ?? 0L;

            nuevoCursor = Math.Min(desde, maxSecuencia);

            if (desde > maxSecuencia)
                _log.LogWarning(
                    "Sync pull licencia {Lic}: cursor {Recibido} por delante de la secuencia máxima {Max}; " +
                    "se devuelve el máximo real.", licenciaId, desde, maxSecuencia);
        }

        return new SyncPullResponse
        {
            Cambios = cambios,
            Cursor = nuevoCursor.ToString(CultureInfo.InvariantCulture)
        };
    }

    /// <summary>Sobrecarga de compatibilidad: pull sin filtro de eco.</summary>
    public Task<SyncPullResponse> ObtenerCambiosAsync(Guid licenciaId, string? cursor, CancellationToken ct)
        => ObtenerCambiosAsync(licenciaId, cursor, null, ct);

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
