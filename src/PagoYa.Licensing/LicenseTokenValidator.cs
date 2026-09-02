using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PagoYa.Licensing;

/// <summary>
/// Valida criptográficamente un token de licencia PagoYa. Verifica la firma
/// RSA-2048 (RSASSA-PKCS1-v1_5 + SHA-256) contra la clave pública embebida y
/// deserializa el payload a <see cref="LicenseToken"/>.
///
/// Formato del token: <c>base64url(payload_json).base64url(firma)</c>.
///
/// Este validador es puro (sin estado, sin HWID/expiración): esas reglas de
/// negocio las aplica <see cref="LicenseService"/>. Aquí solo se responde:
/// ¿la firma es auténtica y el payload es parseable?
/// </summary>
public sealed class LicenseTokenValidator
{
    private readonly string _pemPublicKey;

    /// <summary>Usa la clave pública embebida por defecto.</summary>
    public LicenseTokenValidator() : this(ClavePublicaEmbebida.PemPublicKey) { }

    /// <summary>Permite inyectar una clave pública (útil para tests).</summary>
    public LicenseTokenValidator(string pemPublicKey) => _pemPublicKey = pemPublicKey;

    /// <summary>
    /// Verifica la firma y parsea el payload.
    /// </summary>
    /// <param name="tokenFirmado">Token en formato payload.firma (base64url).</param>
    /// <param name="token">Payload deserializado si la firma es válida.</param>
    /// <param name="error">Motivo del fallo si retorna false.</param>
    /// <returns>True si la firma es auténtica y el payload es válido.</returns>
    public bool TryValidar(string tokenFirmado, out LicenseToken? token, out string? error)
    {
        token = null;
        error = null;

        if (string.IsNullOrWhiteSpace(tokenFirmado))
        {
            error = "Token vacío.";
            return false;
        }

        var partes = tokenFirmado.Split('.');
        if (partes.Length != 2)
        {
            error = "Formato de token inválido (se esperaba payload.firma).";
            return false;
        }

        byte[] payloadBytes;
        byte[] firmaBytes;
        try
        {
            payloadBytes = DecodeBase64Url(partes[0]);
            firmaBytes = DecodeBase64Url(partes[1]);
        }
        catch (FormatException)
        {
            error = "Codificación base64url inválida.";
            return false;
        }

        // Verificación de la firma RSA-2048 sobre los BYTES del payload.
        try
        {
            using var rsa = RSA.Create();
            rsa.ImportFromPem(_pemPublicKey);

            var firmaValida = rsa.VerifyData(
                payloadBytes,
                firmaBytes,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);

            if (!firmaValida)
            {
                error = "Firma del token no válida (posible manipulación o clave incorrecta).";
                return false;
            }
        }
        catch (Exception ex) when (ex is CryptographicException or ArgumentException)
        {
            // Con el placeholder PEM esto ocurrirá hasta que licensing-backend
            // embeba la clave real. Se trata como fallo de validación seguro.
            error = $"No se pudo verificar la firma: {ex.Message}";
            return false;
        }

        // Deserialización del payload firmado.
        try
        {
            var json = Encoding.UTF8.GetString(payloadBytes);
            token = JsonSerializer.Deserialize<LicenseToken>(json);
        }
        catch (JsonException)
        {
            error = "El payload del token no es JSON válido.";
            return false;
        }

        if (token is null)
        {
            error = "El payload del token está vacío.";
            return false;
        }

        return true;
    }

    /// <summary>Decodifica una cadena base64url (RFC 4648, sin padding) a bytes.</summary>
    private static byte[] DecodeBase64Url(string input)
    {
        var s = input.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }
}
