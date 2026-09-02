using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PagoYa.Api.Firma;

/// <summary>
/// Verifica un token de licencia firmado (el mismo que emite <see cref="EmisorTokens"/>)
/// para autenticar las peticiones de sincronización. Comprueba la firma RSA con la
/// clave del server, la vigencia (<c>exp</c>) y que el token habilite el flag pedido
/// (p. ej. <c>cloud_sync</c>). No consulta la BD: es verificación criptográfica pura.
/// </summary>
public sealed class VerificadorToken
{
    private readonly OpcionesFirma _opciones;

    public VerificadorToken(OpcionesFirma opciones) => _opciones = opciones;

    /// <summary>
    /// Verifica firma + expiración del token y devuelve su payload. No valida flags
    /// (eso lo decide el llamador con <see cref="ExigeFeature"/>).
    /// </summary>
    public bool TryVerificar(string? token, out PayloadToken? payload, out string? error)
    {
        payload = null;
        error = null;

        if (string.IsNullOrWhiteSpace(token))
        {
            error = "Token ausente.";
            return false;
        }

        var partes = token.Split('.');
        if (partes.Length != 2)
        {
            error = "Formato de token inválido.";
            return false;
        }

        byte[] payloadBytes, firmaBytes;
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

        try
        {
            using var rsa = CargarClave();
            if (!rsa.VerifyData(payloadBytes, firmaBytes, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
            {
                error = "Firma del token no válida.";
                return false;
            }
        }
        catch (Exception ex) when (ex is CryptographicException or ArgumentException or InvalidOperationException)
        {
            error = $"No se pudo verificar la firma: {ex.Message}";
            return false;
        }

        try
        {
            payload = JsonSerializer.Deserialize<PayloadToken>(Encoding.UTF8.GetString(payloadBytes));
        }
        catch (JsonException)
        {
            error = "Payload del token no es JSON válido.";
            return false;
        }

        if (payload is null)
        {
            error = "Payload del token vacío.";
            return false;
        }

        // Expiración (0 = perpetua).
        if (payload.Exp != 0 && DateTimeOffset.FromUnixTimeSeconds(payload.Exp) < DateTimeOffset.UtcNow)
        {
            error = "El token de licencia expiró.";
            return false;
        }

        return true;
    }

    /// <summary>True si el payload habilita el feature indicado (ej. "cloud_sync").</summary>
    public static bool ExigeFeature(PayloadToken payload, string feature) =>
        payload.Features.Contains(feature, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Carga la clave RSA desde la configuración de firma. La clave privada también
    /// sirve para verificar; en un despliegue con verificación separada bastaría la pública.
    /// </summary>
    private RSA CargarClave()
    {
        var rsa = RSA.Create();
        if (!string.IsNullOrWhiteSpace(_opciones.PrivateKeyPem))
        {
            rsa.ImportFromPem(_opciones.PrivateKeyPem);
            return rsa;
        }
        if (!string.IsNullOrWhiteSpace(_opciones.PrivateKeyPath) && File.Exists(_opciones.PrivateKeyPath))
        {
            rsa.ImportFromPem(File.ReadAllText(_opciones.PrivateKeyPath));
            return rsa;
        }
        rsa.Dispose();
        throw new InvalidOperationException("No hay clave RSA configurada para verificar tokens.");
    }

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
