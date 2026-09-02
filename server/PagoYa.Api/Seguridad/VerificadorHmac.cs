using System.Security.Cryptography;
using System.Text;

namespace PagoYa.Api.Seguridad;

/// <summary>
/// Verifica la firma HMAC-SHA256 que los proveedores de pago (pasarela) adjuntan
/// a sus webhooks para probar autenticidad. El secreto compartido vive en
/// configuración (user-secrets / env), nunca en el repo.
///
/// El proveedor firma el cuerpo crudo del request y envía el hex/base64 en una
/// cabecera (p.ej. X-PagoYa-Signature). Aquí recomputamos y comparamos en tiempo
/// constante.
/// </summary>
public static class VerificadorHmac
{
    public static bool Verificar(string secreto, string cuerpoCrudo, string? firmaRecibida)
    {
        if (string.IsNullOrEmpty(secreto) || string.IsNullOrEmpty(firmaRecibida))
            return false;

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secreto));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(cuerpoCrudo));
        var esperadoHex = Convert.ToHexString(hash).ToLowerInvariant();

        // Aceptamos hex (con o sin prefijo sha256=) o base64.
        var recibida = firmaRecibida.Trim();
        if (recibida.StartsWith("sha256=", StringComparison.OrdinalIgnoreCase))
            recibida = recibida["sha256=".Length..];

        if (ComparacionConstante(esperadoHex, recibida.ToLowerInvariant()))
            return true;

        var esperadoB64 = Convert.ToBase64String(hash);
        return ComparacionConstante(esperadoB64, recibida);
    }

    private static bool ComparacionConstante(string a, string b)
    {
        var ba = Encoding.UTF8.GetBytes(a);
        var bb = Encoding.UTF8.GetBytes(b);
        if (ba.Length != bb.Length) return false;
        return CryptographicOperations.FixedTimeEquals(ba, bb);
    }
}
