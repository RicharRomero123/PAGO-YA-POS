namespace PagoYa.Core.Enums;

/// <summary>
/// Rol de un usuario del POS. Determina qué puede hacer dentro del programa.
/// En el tier Base solo se permiten 2 usuarios (1 administrador + 1 adicional);
/// más usuarios requieren licencia premium (ver gating por MultiSite).
/// </summary>
public enum RolUsuario
{
    /// <summary>Dueño/administrador: acceso total, gestiona usuarios y configuración.</summary>
    Administrador = 0,

    /// <summary>Cajero/empleado: opera ventas y caja; sin acceso a gestión de usuarios.</summary>
    Cajero = 1
}
