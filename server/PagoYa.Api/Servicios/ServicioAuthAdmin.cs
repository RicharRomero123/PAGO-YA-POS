using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Servicios;

/// <summary>
/// Autenticación del panel web de administración: bootstrap de la cuenta admin,
/// login (con hash PBKDF2) y validación de sesiones opacas. Reemplaza el uso
/// manual de la API key por una cuenta con usuario/contraseña que crea el propio
/// vendedor la primera vez que abre la web.
/// </summary>
public sealed class ServicioAuthAdmin
{
    // PBKDF2-SHA256. 100k iteraciones = coste razonable en 2025 para frenar fuerza bruta.
    private const int Iteraciones = 100_000;
    private const int TamanoSalt = 16;   // 128 bits
    private const int TamanoHash = 32;   // 256 bits
    private static readonly TimeSpan DuracionSesion = TimeSpan.FromHours(12);

    private readonly LicenciasDbContext _db;
    private readonly ILogger<ServicioAuthAdmin> _log;

    public ServicioAuthAdmin(LicenciasDbContext db, ILogger<ServicioAuthAdmin> log)
    {
        _db = db;
        _log = log;
    }

    /// <summary>True si aún no existe ninguna cuenta admin (mostrar registro).</summary>
    public async Task<bool> NecesitaSetupAsync(CancellationToken ct)
        => !await _db.AdminUsuarios.AnyAsync(ct);

    /// <summary>
    /// Crea la cuenta admin inicial. Solo permitido si NO existe ninguna todavía
    /// (bootstrap). Devuelve una sesión ya iniciada para entrar directo.
    /// </summary>
    public async Task<Resultado<SesionResponse>> RegistrarAsync(RegistroAdminRequest req, CancellationToken ct)
    {
        var usuario = (req.Usuario ?? "").Trim().ToLowerInvariant();
        if (usuario.Length < 3)
            return Resultado<SesionResponse>.Falla("El usuario debe tener al menos 3 caracteres.", 400);
        if ((req.Password ?? "").Length < 8)
            return Resultado<SesionResponse>.Falla("La contraseña debe tener al menos 8 caracteres.", 400);

        if (await _db.AdminUsuarios.AnyAsync(ct))
            return Resultado<SesionResponse>.Falla("La cuenta de administrador ya existe. Inicia sesión.", 409);

        var salt = RandomNumberGenerator.GetBytes(TamanoSalt);
        var hash = DerivarHash(req.Password!, salt);

        var admin = new AdminUsuario
        {
            Usuario = usuario,
            PasswordSalt = Convert.ToBase64String(salt),
            PasswordHash = Convert.ToBase64String(hash),
            Rol = "admin"
        };
        _db.AdminUsuarios.Add(admin);
        await _db.SaveChangesAsync(ct);
        _log.LogInformation("Cuenta admin creada: {Usuario}", usuario);

        return Resultado<SesionResponse>.Exito(await CrearSesionAsync(admin, ct));
    }

    /// <summary>Valida credenciales y emite una sesión. Mensaje genérico ante fallo.</summary>
    public async Task<Resultado<SesionResponse>> LoginAsync(LoginAdminRequest req, CancellationToken ct)
    {
        var usuario = (req.Usuario ?? "").Trim().ToLowerInvariant();
        var admin = await _db.AdminUsuarios.FirstOrDefaultAsync(u => u.Usuario == usuario, ct);

        // Comparación en tiempo (casi) constante: si no existe el usuario, igual
        // derivamos un hash falso para no filtrar la existencia por el tiempo.
        var saltRef = admin is not null
            ? Convert.FromBase64String(admin.PasswordSalt)
            : new byte[TamanoSalt];
        var hashCalc = DerivarHash(req.Password ?? "", saltRef);
        var hashOk = admin is not null &&
                     CryptographicOperations.FixedTimeEquals(
                         hashCalc, Convert.FromBase64String(admin.PasswordHash));

        if (admin is null || !hashOk)
        {
            _log.LogWarning("Login admin fallido para {Usuario}", usuario);
            return Resultado<SesionResponse>.Falla("Usuario o contraseña incorrectos.", 401);
        }

        admin.UltimoAccesoUtc = DateTime.UtcNow;
        var sesion = await CrearSesionAsync(admin, ct);
        return Resultado<SesionResponse>.Exito(sesion);
    }

    /// <summary>Valida un token de sesión; devuelve el usuario si sigue vigente.</summary>
    public async Task<bool> ValidarSesionAsync(string? token, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(token)) return false;
        var s = await _db.AdminSesiones.AsNoTracking().FirstOrDefaultAsync(x => x.Token == token, ct);
        return s is not null && s.ExpiraUtc > DateTime.UtcNow;
    }

    /// <summary>Cierra la sesión (elimina el token). Idempotente.</summary>
    public async Task CerrarSesionAsync(string? token, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(token)) return;
        var s = await _db.AdminSesiones.FirstOrDefaultAsync(x => x.Token == token, ct);
        if (s is not null)
        {
            _db.AdminSesiones.Remove(s);
            await _db.SaveChangesAsync(ct);
        }
    }

    private async Task<SesionResponse> CrearSesionAsync(AdminUsuario admin, CancellationToken ct)
    {
        // Purga oportunista de sesiones vencidas para no acumular basura.
        var vencidas = await _db.AdminSesiones.Where(x => x.ExpiraUtc <= DateTime.UtcNow).ToListAsync(ct);
        if (vencidas.Count > 0) _db.AdminSesiones.RemoveRange(vencidas);

        var sesion = new AdminSesion
        {
            Token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .Replace('+', '-').Replace('/', '_').TrimEnd('='),
            UsuarioId = admin.Id,
            CreadoUtc = DateTime.UtcNow,
            ExpiraUtc = DateTime.UtcNow.Add(DuracionSesion)
        };
        _db.AdminSesiones.Add(sesion);
        await _db.SaveChangesAsync(ct);

        return new SesionResponse
        {
            Token = sesion.Token,
            Usuario = admin.Usuario,
            ExpiraUtc = sesion.ExpiraUtc
        };
    }

    private static byte[] DerivarHash(string password, byte[] salt)
        => Rfc2898DeriveBytes.Pbkdf2(password, salt, Iteraciones, HashAlgorithmName.SHA256, TamanoHash);
}
