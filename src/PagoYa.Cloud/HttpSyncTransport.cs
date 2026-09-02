using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Transporte HTTP/JSON real contra el backend de sincronización. Sube lotes a
/// <c>POST {UrlBase}/sync/push</c> y baja cambios de
/// <c>GET {UrlBase}/sync/pull?cursor=&lt;n&gt;&amp;origen=&lt;origen_caja_id&gt;</c>,
/// autenticando con el token de licencia (Bearer).
///
/// <b>El parámetro <c>origen</c> no es opcional en la práctica.</b> Con él, el
/// backend aplica el filtro de eco y no nos devuelve los eventos que subimos
/// nosotros mismos (<c>server/README.md §7.1</c>). Sin él, el server intenta el
/// claim <c>device_prefix</c> del token y, como los tokens de escritorio en campo
/// no traen claims de dispositivo, no filtra: la caja se baja sus propias ventas
/// y las re-aplica, con el riesgo de que un snapshot viejo pise uno más nuevo.
/// El valor sale de <see cref="OpcionesSync.OrigenCajaId"/>, que es la MISMA
/// fuente que estampa <c>origen_caja_id</c> en los eventos que se suben.
///
/// <b>Errores: se ramifica por <c>codigo</c>, nunca por el texto.</b> El backend
/// devuelve <c>{ "error": "...", "codigo": "..." }</c> con un catálogo estable de
/// códigos (<c>server/README.md §10</c>, espejo en <see cref="CodigosErrorSync"/>).
/// El texto de <c>error</c> es para el usuario y se reescribe sin aviso.
///
/// <b>Nota sobre JSON:</b> el SOBRE del transporte (<c>eventos</c>,
/// <c>cambios</c>, <c>cursor</c>, <c>aceptados</c>) sí usa camelCase
/// (<see cref="JsonSerializerDefaults.Web"/>), porque así lo expone ASP.NET Core.
/// Eso NO aplica al <c>payloadJson</c> que viaja dentro: es una cadena opaca que
/// no se re-serializa aquí, y su contrato es PascalCase case-sensitive
/// (ver la nota de <c>PagoYa.Data.Repositorios.OutboxStore</c>).
/// </summary>
public sealed class HttpSyncTransport : ISyncTransport
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly HttpClient _http;
    private readonly string _origenCajaId;

    public HttpSyncTransport(HttpClient http, OpcionesSync opciones)
    {
        _http = http;
        _origenCajaId = (opciones.OrigenCajaId ?? string.Empty).Trim();

        if (!string.IsNullOrWhiteSpace(opciones.UrlBase))
            _http.BaseAddress = new Uri(opciones.UrlBase);
        if (!string.IsNullOrWhiteSpace(opciones.TokenLicencia))
            _http.DefaultRequestHeaders.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", opciones.TokenLicencia);
    }

    public async Task<ResultadoLote> EnviarLoteAsync(IReadOnlyList<EventoSyncLocal> lote, CancellationToken ct = default)
    {
        try
        {
            using var resp = await _http.PostAsJsonAsync("sync/push", new { eventos = lote }, Json, ct);
            if (!resp.IsSuccessStatusCode)
            {
                var err = await LeerErrorAsync(resp, ct);
                return ResultadoLote.Falla(
                    $"push HTTP {(int)resp.StatusCode}: {MensajeAccionable(err, (int)resp.StatusCode)}",
                    err.Codigo);
            }

            var cuerpo = await resp.Content.ReadFromJsonAsync<PushResponse>(Json, ct);
            return ResultadoLote.Exito((IReadOnlyCollection<Guid>?)cuerpo?.Aceptados ?? Array.Empty<Guid>());
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            return ResultadoLote.Falla($"push: {ex.Message}");
        }
    }

    public async Task<PaqueteRemoto> DescargarCambiosAsync(string? cursor, CancellationToken ct = default)
    {
        using var resp = await _http.GetAsync(ConstruirUrlPull(cursor), ct);
        if (!resp.IsSuccessStatusCode)
        {
            var err = await LeerErrorAsync(resp, ct);
            throw new SyncTransporteException(
                $"pull HTTP {(int)resp.StatusCode}: {MensajeAccionable(err, (int)resp.StatusCode)}",
                err.Codigo);
        }

        var cuerpo = await resp.Content.ReadFromJsonAsync<PullResponse>(Json, ct);
        return new PaqueteRemoto(cuerpo?.Cambios ?? new List<CambioRemoto>(), cuerpo?.Cursor ?? cursor ?? "0");
    }

    /// <summary>
    /// Arma <c>sync/pull</c> con <c>cursor</c> y <c>origen</c>. El <c>origen</c>
    /// se manda siempre que esté configurado: es lo que activa el filtro de eco.
    /// </summary>
    internal string ConstruirUrlPull(string? cursor)
    {
        var partes = new List<string>(2);
        if (!string.IsNullOrEmpty(cursor))
            partes.Add($"cursor={Uri.EscapeDataString(cursor)}");
        if (_origenCajaId.Length > 0)
            partes.Add($"origen={Uri.EscapeDataString(_origenCajaId)}");

        return partes.Count == 0 ? "sync/pull" : $"sync/pull?{string.Join("&", partes)}";
    }

    // ------------------------------------------------------- Errores del API ---

    /// <summary>
    /// Lee <c>{ "error", "codigo" }</c> de una respuesta de error. Falla suave:
    /// un cuerpo vacío, HTML de un proxy o JSON inválido devuelven ambos campos
    /// nulos y se decide por el status.
    /// </summary>
    private static async Task<ErrorApi> LeerErrorAsync(HttpResponseMessage resp, CancellationToken ct)
    {
        try
        {
            var e = await resp.Content.ReadFromJsonAsync<ErrorApi>(Json, ct);
            return e ?? new ErrorApi();
        }
        catch (Exception ex) when (ex is JsonException or HttpRequestException or NotSupportedException)
        {
            return new ErrorApi();
        }
    }

    /// <summary>
    /// Traduce el error del backend a un mensaje que le dice al usuario QUÉ HACER.
    /// La rama se decide por <c>codigo</c> (contrato estable); el status HTTP solo
    /// es el plan B para un backend anterior al catálogo de códigos.
    /// </summary>
    private static string MensajeAccionable(ErrorApi err, int status) => err.Codigo switch
    {
        CodigosErrorSync.SinFlagCloudSync =>
            "Tu plan no incluye respaldo en la nube. Mejora a PagoYa Cloud para sincronizar.",
        CodigosErrorSync.AsientoRevocado =>
            "Este equipo perdió su vínculo con la licencia. Vuelve a vincularlo desde Configuración.",
        CodigosErrorSync.TokenExpirado =>
            "La licencia venció. Renuévala para volver a sincronizar (el POS sigue operando offline).",
        CodigosErrorSync.TokenInvalido or
        CodigosErrorSync.TokenAusente or
        CodigosErrorSync.LicenciaNoIdentificada =>
            "La licencia de este equipo no es válida para la nube. Vuelve a activarla.",

        // Sin `codigo`: server anterior al catálogo o error aún sin clasificar.
        // Se degrada al status, sin adivinar por el texto.
        _ => string.IsNullOrWhiteSpace(err.Error)
            ? DescripcionPorStatus(status)
            : err.Error!
    };

    private static string DescripcionPorStatus(int status) => status switch
    {
        401 or 403 => "el backend rechazó la licencia de este equipo.",
        429 => "demasiadas peticiones; se reintentará más tarde.",
        >= 500 => "el servidor de PagoYa no está disponible; se reintentará.",
        _ => "el servidor rechazó la petición."
    };

    private sealed record PushResponse(List<Guid> Aceptados);
    private sealed record PullResponse(List<CambioRemoto> Cambios, string Cursor);

    /// <summary>Espejo del <c>ErrorResponse</c> del backend.</summary>
    private sealed class ErrorApi
    {
        [JsonPropertyName("error")] public string? Error { get; set; }
        [JsonPropertyName("codigo")] public string? Codigo { get; set; }
    }
}
