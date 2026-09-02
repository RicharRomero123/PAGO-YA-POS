using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PagoYa.Api.Firma;

/// <summary>
/// Emisor de tokens de licencia. Firma el payload con RSA-2048
/// (RSASSA-PKCS1-v1_5 + SHA-256) y produce EXACTAMENTE el formato que valida el
/// cliente (<c>PagoYa.Licensing.LicenseTokenValidator</c>):
///
///     base64url(payload_json) "." base64url(firma_rsa)
///
/// - La firma se calcula sobre los BYTES CRUDOS del payload (no sobre el base64url).
/// - base64url = base64 estándar con '+'→'-', '/'→'_', sin padding '='.
///
/// La clave privada se carga desde configuración (user-secrets / variable de
/// entorno / archivo fuera de git). NUNCA se registra en logs.
/// </summary>
public sealed class EmisorTokens
{
    // Opciones de serialización deterministas. El cliente deserializa con
    // opciones por defecto (case-sensitive sobre los JsonPropertyName), así que
    // basta con respetar los nombres snake_case del contrato.
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        // Emitimos "sub" aunque sea null? El contrato lo marca opcional; el
        // cliente lo acepta como nullable. Lo omitimos si es null para un token
        // más limpio; esto NO afecta la validación de firma (se firma lo emitido).
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly OpcionesFirma _opciones;

    public EmisorTokens(OpcionesFirma opciones) => _opciones = opciones;

    /// <summary>
    /// Firma el payload y devuelve el token en formato payload.firma (base64url).
    /// </summary>
    public string Emitir(PayloadToken payload)
    {
        var json = JsonSerializer.Serialize(payload, JsonOpts);
        var payloadBytes = Encoding.UTF8.GetBytes(json);

        using var rsa = CargarClavePrivada();
        var firma = rsa.SignData(
            payloadBytes,
            HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);

        return $"{Base64Url.Encode(payloadBytes)}.{Base64Url.Encode(firma)}";
    }

    /// <summary>
    /// Carga la clave privada RSA desde PEM en configuración o desde un archivo.
    /// Prioridad: PEM inline (user-secret / env) > ruta de archivo.
    /// </summary>
    private RSA CargarClavePrivada()
    {
        var rsa = RSA.Create();

        if (!string.IsNullOrWhiteSpace(_opciones.PrivateKeyPem))
        {
            rsa.ImportFromPem(_opciones.PrivateKeyPem);
            return rsa;
        }

        if (!string.IsNullOrWhiteSpace(_opciones.PrivateKeyPath) && File.Exists(_opciones.PrivateKeyPath))
        {
            var pem = File.ReadAllText(_opciones.PrivateKeyPath);
            rsa.ImportFromPem(pem);
            return rsa;
        }

        rsa.Dispose();
        throw new InvalidOperationException(
            "No hay clave privada RSA configurada. Defina Firma:PrivateKeyPem (user-secrets/env) " +
            "o Firma:PrivateKeyPath. Genere una con: dotnet run -- gen-keys (ver README).");
    }
}

/// <summary>Opciones de firma (bind desde la sección "Firma" de configuración).</summary>
public sealed class OpcionesFirma
{
    /// <summary>Clave privada RSA-2048 en PEM (PKCS#8). Preferir user-secrets/env.</summary>
    public string? PrivateKeyPem { get; set; }

    /// <summary>Ruta a un archivo PEM con la clave privada (alternativa fuera de git).</summary>
    public string? PrivateKeyPath { get; set; }
}

/// <summary>Codificación base64url (RFC 4648, sin padding) — idéntica a la del cliente.</summary>
public static class Base64Url
{
    public static string Encode(byte[] bytes)
        => Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
}
