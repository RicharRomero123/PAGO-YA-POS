using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Sesión del usuario que inició sesión en el POS. Singleton mutable: lo fija el
/// login antes de abrir la ventana principal, y el resto de la app lo consulta
/// para saber quién opera (arqueo de caja, permisos de gestión de usuarios).
/// </summary>
public sealed class SesionActual
{
    /// <summary>Usuario con sesión iniciada. Null hasta que alguien entra.</summary>
    public Usuario? Usuario { get; private set; }

    /// <summary>True si el usuario actual es administrador (puede gestionar usuarios).</summary>
    public bool EsAdministrador => Usuario?.Rol == RolUsuario.Administrador;

    /// <summary>Nombre a mostrar en la UI (completo o, en su defecto, el de login).</summary>
    public string NombreMostrado =>
        !string.IsNullOrWhiteSpace(Usuario?.NombreCompleto) ? Usuario!.NombreCompleto
        : Usuario?.NombreUsuario ?? "Invitado";

    /// <summary>Etiqueta del rol para la UI.</summary>
    public string RolMostrado => Usuario?.Rol switch
    {
        RolUsuario.Administrador => "Administrador",
        RolUsuario.Cajero => "Cajero",
        _ => ""
    };

    public void Establecer(Usuario usuario) => Usuario = usuario;

    public void Cerrar() => Usuario = null;
}
