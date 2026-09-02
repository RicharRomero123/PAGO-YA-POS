using CommunityToolkit.Mvvm.ComponentModel;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Entrada del menú lateral. Puede estar <b>bloqueada</b> por licencia; en ese
/// caso se muestra con candado + badge de tier y, al pulsarla, dispara el upsell.
/// </summary>
public partial class ModuloNavegacion : ObservableObject
{
    public string Clave { get; init; } = "";
    public string Titulo { get; init; } = "";

    /// <summary>Emoji de respaldo (se conserva por compatibilidad; el sidebar usa <see cref="IconoImagen"/>).</summary>
    public string Icono { get; init; } = "•";

    /// <summary>URI pack del icono PNG del módulo (Assets/Iconos). Ver <see cref="Servicios.IconosPos"/>.</summary>
    public string IconoImagen { get; init; } = "";

    /// <summary>True si el feature está bloqueado (licencia no habilita el flag).</summary>
    public bool Bloqueado { get; init; }

    /// <summary>Tier necesario para desbloquear (texto para el badge). Ej. "Cloud", "Facturador".</summary>
    public string TierRequerido { get; init; } = "";

    [ObservableProperty]
    private bool _activo;
}
