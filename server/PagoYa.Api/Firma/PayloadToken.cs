using System.Text.Json.Serialization;

namespace PagoYa.Api.Firma;

/// <summary>
/// Payload del token de licencia. Es el ESPEJO EXACTO de
/// <c>PagoYa.Licensing.LicenseToken</c> del cliente (mismos nombres JSON
/// snake_case). Ver docs/LICENSE-TOKEN.md §4. NO renombrar sin coordinar.
///
/// La firma RSA se calcula sobre los bytes UTF-8 de este objeto serializado.
/// </summary>
public sealed class PayloadToken
{
    [JsonPropertyName("license_id")]
    public string LicenseId { get; set; } = string.Empty;

    [JsonPropertyName("tier")]
    public string Tier { get; set; } = "base";

    [JsonPropertyName("features")]
    public string[] Features { get; set; } = Array.Empty<string>();

    [JsonPropertyName("hwid")]
    public string Hwid { get; set; } = string.Empty;

    [JsonPropertyName("iat")]
    public long Iat { get; set; }

    [JsonPropertyName("exp")]
    public long Exp { get; set; }

    [JsonPropertyName("sub")]
    public string? Sub { get; set; }

    /// <summary>
    /// (Opcional, aditivo) Id del ASIENTO cuando el token se emitió por
    /// <c>POST /devices</c>. Identifica al dispositivo secundario para revocarlo
    /// y para el filtro de eco del pull. Ver docs/LICENSE-TOKEN.md §4.1.
    ///
    /// <b>Compatibilidad:</b> se omite del JSON cuando es null (el emisor serializa
    /// con <c>WhenWritingNull</c>), así que los tokens de <c>/activate</c> siguen
    /// siendo byte a byte los de siempre y los clientes en campo —que deserializan
    /// ignorando propiedades desconocidas— aceptan sin cambios los que sí lo traen.
    /// </summary>
    [JsonPropertyName("device_id")]
    public string? DeviceId { get; set; }

    /// <summary>
    /// (Opcional, aditivo) Prefijo asignado por el server a este dispositivo
    /// (<c>C01</c>, <c>M01</c>). Es el valor que el cliente usa como
    /// <c>origen_caja_id</c> y como prefijo de correlativos
    /// (<c>&lt;prefijo&gt;-&lt;correlativo&gt;</c>). Se omite si es null.
    /// </summary>
    [JsonPropertyName("device_prefix")]
    public string? DevicePrefix { get; set; }
}
