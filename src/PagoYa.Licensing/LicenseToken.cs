using System.Text.Json.Serialization;

namespace PagoYa.Licensing;

/// <summary>
/// Modelo del <b>payload</b> del token de licencia de PagoYa. Este es el
/// CONTRATO compartido entre el emisor (licensing-backend, que lo firma con la
/// clave privada RSA-2048) y el cliente (que lo valida con la clave pública).
///
/// El token completo que viaja al cliente tiene el formato:
///     BASE64URL(payload_json) + "." + BASE64URL(firma_rsa)
/// Ver docs/LICENSE-TOKEN.md para el esquema formal.
///
/// Los nombres JSON (snake_case) son parte del contrato: NO renombrar sin
/// coordinar con licensing-backend.
/// </summary>
public sealed class LicenseToken
{
    /// <summary>Identificador único de la licencia emitida (para revocación/soporte).</summary>
    [JsonPropertyName("license_id")]
    public string LicenseId { get; set; } = string.Empty;

    /// <summary>Tier comercial: "base" | "cloud" | "facturador".</summary>
    [JsonPropertyName("tier")]
    public string Tier { get; set; } = "base";

    /// <summary>
    /// Feature flags habilitados. Valores canónicos: "invoicing", "cloud_sync",
    /// "multi_site" (ver PagoYa.Core.Contratos.Flags).
    /// </summary>
    [JsonPropertyName("features")]
    public string[] Features { get; set; } = Array.Empty<string>();

    /// <summary>HWID vinculado (hash del hardware). Vacío = licencia no atada a máquina.</summary>
    [JsonPropertyName("hwid")]
    public string Hwid { get; set; } = string.Empty;

    /// <summary>Issued-at: fecha de emisión (Unix epoch en segundos, UTC).</summary>
    [JsonPropertyName("iat")]
    public long Iat { get; set; }

    /// <summary>
    /// Expiration: fecha de expiración (Unix epoch en segundos, UTC).
    /// 0 = sin expiración (licencia perpetua, típica del tier Base).
    /// </summary>
    [JsonPropertyName("exp")]
    public long Exp { get; set; }

    /// <summary>RUC/identificador del negocio dueño de la licencia (informativo).</summary>
    [JsonPropertyName("sub")]
    public string? Sub { get; set; }

    // --- Helpers de conveniencia (no serializados) ---

    /// <summary>Fecha de emisión como DateTime UTC.</summary>
    [JsonIgnore]
    public DateTime EmitidoUtc => DateTimeOffset.FromUnixTimeSeconds(Iat).UtcDateTime;

    /// <summary>Fecha de expiración como DateTime UTC, o null si es perpetua (exp == 0).</summary>
    [JsonIgnore]
    public DateTime? ExpiraUtc => Exp == 0 ? null : DateTimeOffset.FromUnixTimeSeconds(Exp).UtcDateTime;

    /// <summary>True si la licencia es perpetua (sin expiración).</summary>
    [JsonIgnore]
    public bool EsPerpetua => Exp == 0;
}
