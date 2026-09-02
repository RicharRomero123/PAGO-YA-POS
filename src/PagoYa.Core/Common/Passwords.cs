using System.Security.Cryptography;

namespace PagoYa.Core.Common;

/// <summary>
/// Utilidades de hashing de contraseñas para los usuarios locales del POS.
/// Usa PBKDF2 (Rfc2898) con SHA-256, sin dependencias externas. El mismo criterio
/// que el panel web (server), para que la seguridad sea consistente en ambos lados.
/// </summary>
public static class Passwords
{
    private const int Iteraciones = 100_000; // coste razonable contra fuerza bruta
    private const int TamanoSalt = 16;        // 128 bits
    private const int TamanoHash = 32;        // 256 bits

    /// <summary>Genera un salt aleatorio nuevo (base64).</summary>
    public static string NuevoSalt() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(TamanoSalt));

    /// <summary>Deriva el hash (base64) de una contraseña con el salt dado (base64).</summary>
    public static string Hash(string password, string saltBase64)
    {
        var salt = Convert.FromBase64String(saltBase64);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iteraciones, HashAlgorithmName.SHA256, TamanoHash);
        return Convert.ToBase64String(hash);
    }

    /// <summary>
    /// Verifica una contraseña contra el hash+salt almacenados, en tiempo constante
    /// para no filtrar información por el tiempo de comparación.
    /// </summary>
    public static bool Verificar(string password, string hashBase64, string saltBase64)
    {
        try
        {
            var esperado = Convert.FromBase64String(hashBase64);
            var salt = Convert.FromBase64String(saltBase64);
            var calculado = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iteraciones, HashAlgorithmName.SHA256, esperado.Length);
            return CryptographicOperations.FixedTimeEquals(calculado, esperado);
        }
        catch (FormatException)
        {
            return false; // hash/salt corruptos
        }
    }
}
