using System.ComponentModel.DataAnnotations;

namespace PagoYa.Api.Contratos;

// ===================== Autenticación del panel web =====================

/// <summary>Crear la cuenta de administrador (solo en el bootstrap inicial).</summary>
public sealed class RegistroAdminRequest
{
    [Required] public string Usuario { get; set; } = string.Empty;
    [Required] public string Password { get; set; } = string.Empty;
}

/// <summary>Inicio de sesión del panel.</summary>
public sealed class LoginAdminRequest
{
    [Required] public string Usuario { get; set; } = string.Empty;
    [Required] public string Password { get; set; } = string.Empty;
}

/// <summary>Respuesta de login/registro: token de sesión para el navegador.</summary>
public sealed class SesionResponse
{
    public string Token { get; set; } = string.Empty;
    public string Usuario { get; set; } = string.Empty;
    public DateTime ExpiraUtc { get; set; }
}

/// <summary>Estado del bootstrap: indica si aún falta crear la cuenta admin.</summary>
public sealed class SetupEstadoResponse
{
    /// <summary>True si no existe ninguna cuenta admin (mostrar registro en vez de login).</summary>
    public bool NecesitaSetup { get; set; }
}
