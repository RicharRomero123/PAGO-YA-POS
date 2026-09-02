using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Usuario del POS (administrador o cajero). Cada uno inicia sesión con su
/// nombre de usuario y contraseña. La contraseña NUNCA se guarda en claro: se
/// almacena el hash PBKDF2 + salt (ver <see cref="Common.Passwords"/>).
///
/// Regla de negocio (tier Base): máximo 2 usuarios activos — 1 administrador y
/// 1 adicional. Crear más usuarios requiere licencia premium.
/// </summary>
public class Usuario : EntidadBase
{
    /// <summary>Nombre de usuario para el login (único, normalizado a minúsculas).</summary>
    public string NombreUsuario { get; set; } = string.Empty;

    /// <summary>Nombre completo para mostrar en la UI y en el arqueo de caja.</summary>
    public string NombreCompleto { get; set; } = string.Empty;

    /// <summary>Hash PBKDF2 (SHA-256) de la contraseña, en base64.</summary>
    public string PasswordHash { get; set; } = string.Empty;

    /// <summary>Salt aleatorio por usuario, en base64.</summary>
    public string PasswordSalt { get; set; } = string.Empty;

    /// <summary>Rol del usuario (permisos dentro del POS).</summary>
    public RolUsuario Rol { get; set; } = RolUsuario.Cajero;

    /// <summary>Usuario activo. Los desactivados no pueden iniciar sesión ni cuentan al límite.</summary>
    public bool Activo { get; set; } = true;

    /// <summary>Último inicio de sesión exitoso (UTC). Null si nunca ingresó.</summary>
    public DateTime? UltimoAccesoUtc { get; set; }
}
