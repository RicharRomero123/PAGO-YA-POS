using System.Net.Http.Json;
using System.Text.Json;
using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Transporte HTTP/JSON real contra el backend de sincronización. Sube lotes a
/// <c>POST {UrlBase}/sync/push</c> y baja cambios de <c>GET {UrlBase}/sync/pull</c>,
/// autenticando con el token de licencia (Bearer). Queda LISTO para cuando el
/// backend exponga estos endpoints; hoy la composición usa el transporte simulado.
/// </summary>
public sealed class HttpSyncTransport : ISyncTransport
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly HttpClient _http;

    public HttpSyncTransport(HttpClient http, OpcionesSync opciones)
    {
        _http = http;
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
                return ResultadoLote.Falla($"push HTTP {(int)resp.StatusCode}");

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
        var url = string.IsNullOrEmpty(cursor) ? "sync/pull" : $"sync/pull?cursor={Uri.EscapeDataString(cursor)}";
        var cuerpo = await _http.GetFromJsonAsync<PullResponse>(url, Json, ct);
        return new PaqueteRemoto(cuerpo?.Cambios ?? new List<CambioRemoto>(), cuerpo?.Cursor ?? cursor ?? "0");
    }

    private sealed record PushResponse(List<Guid> Aceptados);
    private sealed record PullResponse(List<CambioRemoto> Cambios, string Cursor);
}
