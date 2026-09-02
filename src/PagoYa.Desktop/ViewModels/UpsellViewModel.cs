using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Contenido del panel de <b>upsell</b> que se muestra cuando el cajero abre un
/// módulo bloqueado por licencia (Facturación, Cloud, Multisede). Debe verse
/// premium, no molesto: el negocio vive de convertir Base → Cloud → Facturador.
///
/// "Mejora tu plan" lleva a la pantalla de Configuración, donde el usuario copia
/// su HWID y pega el token de activación. El shell (MainWindowViewModel) inyecta
/// la navegación vía <see cref="AbrirActivacion"/>.
/// </summary>
public partial class UpsellViewModel : ObservableObject
{
    /// <summary>Callback de navegación a la activación de licencia. Lo set el shell.</summary>
    public Action? AbrirActivacion { get; set; }

    [ObservableProperty] private string _icono = "\U0001F512"; // 🔒
    [ObservableProperty] private string _titulo = "";
    [ObservableProperty] private string _tierRequerido = "";
    [ObservableProperty] private string _precio = "";
    [ObservableProperty] private string _gancho = "";
    [ObservableProperty] private string _beneficio1 = "";
    [ObservableProperty] private string _beneficio2 = "";
    [ObservableProperty] private string _beneficio3 = "";
    [ObservableProperty] private bool _visible;

    /// <summary>Carga el copy del upsell según el módulo bloqueado.</summary>
    public void Mostrar(ModuloNavegacion modulo)
    {
        Visible = true;
        TierRequerido = modulo.TierRequerido;

        switch (modulo.Clave)
        {
            case "facturacion":
                Icono = "\U0001F9FE"; // 🧾
                Titulo = "Emite Boletas y Facturas electrónicas";
                Precio = "Desde S/ 50 / mes";
                Gancho = "Vende formal y gana clientes empresa. Envío directo a SUNAT, sin certificados que configurar.";
                Beneficio1 = "Boletas y Facturas ilimitadas, válidas ante SUNAT.";
                Beneficio2 = "PDF del comprobante enviado por WhatsApp al instante.";
                Beneficio3 = "Incluye todo lo de Cloud (respaldo + multisede).";
                break;

            case "cloud":
                Icono = "☁"; // ☁
                Titulo = "Respalda tu negocio en la nube";
                Precio = "Desde S/ 25 / mes";
                Gancho = "Nunca pierdas tus ventas ni tu inventario. Consulta tu negocio desde el celular, estés donde estés.";
                Beneficio1 = "Respaldo automático: si se malogra la PC, tus datos están seguros.";
                Beneficio2 = "Reportes en tu celular, en tiempo real.";
                Beneficio3 = "Base para operar varias cajas o sedes.";
                break;

            case "multisede":
                Icono = "\U0001F3EA"; // 🏪
                Titulo = "Controla varias cajas y sedes";
                Precio = "Desde S/ 25 / mes";
                Gancho = "Crece sin perder el control. Consolida las ventas de todas tus tiendas en un solo lugar.";
                Beneficio1 = "Multi-caja y multisede sincronizadas.";
                Beneficio2 = "Inventario y ventas consolidados por sede.";
                Beneficio3 = "Incluye respaldo en la nube.";
                break;

            default:
                Icono = "\U0001F512";
                Titulo = "Función premium";
                Precio = "";
                Gancho = "Mejora tu plan para desbloquear esta función.";
                Beneficio1 = Beneficio2 = Beneficio3 = "";
                break;
        }
    }

    [RelayCommand]
    private void Cerrar() => Visible = false;

    /// <summary>Cierra el upsell y navega a Configuración para activar el token.</summary>
    [RelayCommand]
    private void MejorarPlan()
    {
        Visible = false;
        AbrirActivacion?.Invoke();
    }
}
