namespace PagoYa.Api.Dominio;

/// <summary>
/// Cuenta de administrador del panel web (el vendedor). Se crea en el primer
/// arranque (bootstrap) desde la propia web. La contraseña NUNCA se guarda en
/// claro: se almacena el hash PBKDF2 + salt. Es la identidad para emitir y
/// gestionar licencias desde el navegador (sustituye a la API key manual).
/// </summary>
public sealed class AdminUsuario
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>Nombre de usuario para el login (único, normalizado a minúsculas).</summary>
    public string Usuario { get; set; } = string.Empty;

    /// <summary>Hash PBKDF2 (SHA-256) de la contraseña, en base64.</summary>
    public string PasswordHash { get; set; } = string.Empty;

    /// <summary>Salt aleatorio por usuario, en base64.</summary>
    public string PasswordSalt { get; set; } = string.Empty;

    /// <summary>Rol: "admin" (dueño). Reservado para futuros roles del panel.</summary>
    public string Rol { get; set; } = "admin";

    public DateTime CreadoUtc { get; set; } = DateTime.UtcNow;
    public DateTime? UltimoAccesoUtc { get; set; }
}

/// <summary>
/// Sesión activa del panel web. El login emite un token opaco (GUID) que el
/// navegador guarda y envía en cada petición admin (cabecera X-Admin-Token). Se
/// valida contra esta tabla (existe + no expirada); el logout la elimina.
/// </summary>
public sealed class AdminSesion
{
    /// <summary>Token opaco de sesión (secreto que porta el navegador). PK.</summary>
    public string Token { get; set; } = string.Empty;

    public Guid UsuarioId { get; set; }

    public DateTime CreadoUtc { get; set; } = DateTime.UtcNow;

    /// <summary>Expiración de la sesión. Tras ella, exige volver a iniciar sesión.</summary>
    public DateTime ExpiraUtc { get; set; } = DateTime.UtcNow.AddHours(12);
}
