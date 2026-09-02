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
}
