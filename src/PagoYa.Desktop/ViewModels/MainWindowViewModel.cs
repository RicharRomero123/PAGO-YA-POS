using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Desktop.Servicios;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// ViewModel del <b>shell</b> de PagoYa: menú lateral con el logo, navegación
/// entre pantallas y aplicación del feature-gating por licencia en la UI.
///
/// Lee el <see cref="EstadoLicencia"/> vigente desde <see cref="ILicenseService"/>
/// para decidir qué módulos aparecen bloqueados (candado + badge + upsell).
/// El gating de negocio real vive en CompositionRoot; aquí solo reflejamos su
/// resultado en la interfaz.
/// </summary>
public partial class MainWindowViewModel : ObservableObject
{
    private readonly ILicenseService _licencia;
    private readonly SesionActual _sesion;
    private readonly IConfiguracionStore _config;

    public ObservableCollection<ModuloNavegacion> Modulos { get; } = new();

    public UpsellViewModel Upsell { get; } = new();

    // Pantallas (una instancia; inyectadas por DI en runtime)
    public CobroRapidoViewModel Cobro { get; }
    public CajaViewModel Caja { get; }
    public InventarioViewModel Inventario { get; }
    public ReportesViewModel Reportes { get; }
    public ConfiguracionViewModel Configuracion { get; }
    public FacturacionViewModel Facturacion { get; }
    public NubeViewModel Nube { get; }
    public UsuariosViewModel Usuarios { get; }
    public ProveedoresViewModel Proveedores { get; }
    public HabitacionesViewModel Habitaciones { get; }
    public VencimientosViewModel Vencimientos { get; }
    public MesasViewModel Mesas { get; }

    /// <summary>True si el rubro del negocio es hotel/hostal (habilita el módulo de habitaciones).</summary>
    private bool _esHotel;

    /// <summary>True si el rubro del negocio es de comida (habilita el módulo de mesas + comandas).</summary>
    private bool _esComida;

    /// <summary>True si el rubro del negocio es farmacia/botica (habilita el módulo de vencimientos).</summary>
    private bool _esFarmacia;

    /// <summary>Nombre del usuario con sesión iniciada (pie del menú).</summary>
    [ObservableProperty] private string _usuarioActual = "";

    /// <summary>Rol del usuario actual (Administrador / Cajero).</summary>
    [ObservableProperty] private string _rolActual = "";

    /// <summary>La dispara el shell (App) para cerrar sesión y volver al login.</summary>
    public Action? CerrarSesionSolicitada { get; set; }

    /// <summary>Clave del módulo actualmente visible (para el ContentControl del shell).</summary>
    [ObservableProperty] private string _moduloActivo = "cobro";

    /// <summary>Resumen de licencia para el pie del menú lateral.</summary>
    [ObservableProperty] private string _resumenLicencia = "";

    /// <summary>Etiqueta de plan para el badge del menú (Base / Cloud / Facturador).</summary>
    [ObservableProperty] private string _planActual = "Base";

    /// <summary>True si el token está en periodo de gracia (aviso de renovación).</summary>
    [ObservableProperty] private bool _enPeriodoGracia;

    /// <summary>Nombre del negocio (encabezado del sidebar). Se lee de la config.</summary>
    [ObservableProperty] private string _nombreNegocio = "";

    /// <summary>URI pack del icono del rubro elegido (identidad del negocio en el sidebar).</summary>
    [ObservableProperty] private string _rubroIcono = IconosPos.RubroBodega;

    public MainWindowViewModel(
        ILicenseService licencia,
        SesionActual sesion,
        IConfiguracionStore config,
        CobroRapidoViewModel cobro,
        CajaViewModel caja,
        InventarioViewModel inventario,
        ReportesViewModel reportes,
        ConfiguracionViewModel configuracion,
        FacturacionViewModel facturacion,
        NubeViewModel nube,
        UsuariosViewModel usuarios,
        ProveedoresViewModel proveedores,
        HabitacionesViewModel habitaciones,
        VencimientosViewModel vencimientos,
        MesasViewModel mesas)
    {
        _licencia = licencia;
        _sesion = sesion;
        _config = config;
        Cobro = cobro;
        Caja = caja;
        Inventario = inventario;
        Reportes = reportes;
        Configuracion = configuracion;
        Facturacion = facturacion;
        Nube = nube;
        Usuarios = usuarios;
        Proveedores = proveedores;
        Habitaciones = habitaciones;
        Vencimientos = vencimientos;
        Mesas = mesas;

        // "Mejora tu plan" (upsell) lleva a Configuración, donde vive la activación.
        Upsell.AbrirActivacion = () => Navegar("configuracion");
        Usuarios.AbrirPlanes = () => Navegar("configuracion");

        UsuarioActual = _sesion.NombreMostrado;
        RolActual = _sesion.RolMostrado;

        CargarIdentidadNegocio();
        ConstruirMenu();
        ConstruirResumen();
    }

    /// <summary>
    /// Lee el nombre y el rubro del negocio para el encabezado del sidebar, de modo
    /// que el POS "se adapte" visualmente al giro elegido en el onboarding (bodega,
    /// farmacia, ferretería, restaurante…). Degrada a valores por defecto si falla.
    /// </summary>
    private void CargarIdentidadNegocio()
    {
        try
        {
            var cfg = _config.Leer();
            NombreNegocio = string.IsNullOrWhiteSpace(cfg?.NombreNegocio) ? "Mi negocio" : cfg!.NombreNegocio;
            RubroIcono = IconosPos.DeRubro(cfg?.Rubro);
            _esHotel = string.Equals(cfg?.Rubro, "hotel", StringComparison.OrdinalIgnoreCase);
            _esFarmacia = string.Equals(cfg?.Rubro, "farmacia", StringComparison.OrdinalIgnoreCase);
            _esComida = PlantillasRubro.EsRubroComida(cfg?.Rubro);
        }
        catch
        {
            NombreNegocio = "Mi negocio";
            RubroIcono = IconosPos.RubroBodega;
        }
    }

    /// <summary>Cierra la sesión del usuario actual (vuelve al login vía App).</summary>
    [RelayCommand]
    private void CerrarSesion() => CerrarSesionSolicitada?.Invoke();

    /// <summary>
    /// Carga inicial de datos reales de las pantallas (catálogo, caja, inventario).
    /// Se llama tras construir la ventana. Nunca lanza: si una pantalla falla al
    /// cargar, las demás siguen operativas.
    /// </summary>
    public async Task CargarDatosInicialesAsync()
    {
        try { await Cobro.CargarCatalogoAsync(); } catch { /* pantalla sigue usable */ }
        try { await Inventario.CargarAsync(); } catch { }
        try { await Caja.CargarAsync(); } catch { }
        try { await Reportes.CargarAsync(); } catch { }
    }

    private void ConstruirMenu()
    {
        var estado = _licencia.EstadoActual;
        bool tieneFacturacion = estado.TieneCaracteristica(CaracteristicaLicencia.Invoicing);
        bool tieneCloud = estado.TieneCaracteristica(CaracteristicaLicencia.CloudSync);
        bool tieneMultisede = estado.TieneCaracteristica(CaracteristicaLicencia.MultiSite);

        Modulos.Add(new ModuloNavegacion { Clave = "cobro", Titulo = "Cobrar", Icono = "\U0001F6D2", IconoImagen = IconosPos.Cobrar, Activo = true });

        // Módulo de mesas + comandas: solo visible para el rubro de comida.
        if (_esComida)
            Modulos.Add(new ModuloNavegacion { Clave = "mesas", Titulo = "Mesas", Icono = "\U0001F37D", IconoImagen = IconosPos.RubroRestaurante });

        // Módulo de recepción hotelera: solo visible para el rubro hotel/hostal.
        if (_esHotel)
            Modulos.Add(new ModuloNavegacion { Clave = "habitaciones", Titulo = "Habitaciones", Icono = "\U0001F6CF", IconoImagen = IconosPos.RubroHotel });

        // Módulo de vencimientos: solo visible para el rubro farmacia/botica.
        if (_esFarmacia)
            Modulos.Add(new ModuloNavegacion { Clave = "vencimientos", Titulo = "Vencimientos", Icono = "\U0001F4C5", IconoImagen = IconosPos.RubroFarmacia });

        Modulos.Add(new ModuloNavegacion { Clave = "caja", Titulo = "Caja", Icono = "\U0001F4B5", IconoImagen = IconosPos.Caja });
        Modulos.Add(new ModuloNavegacion { Clave = "inventario", Titulo = "Inventario", Icono = "\U0001F4E6", IconoImagen = IconosPos.Inventario });
        Modulos.Add(new ModuloNavegacion { Clave = "proveedores", Titulo = "Proveedores", Icono = "\U0001F69A", IconoImagen = IconosPos.Proveedores });
        Modulos.Add(new ModuloNavegacion { Clave = "reportes", Titulo = "Reportes", Icono = "\U0001F4CA", IconoImagen = IconosPos.Reportes });

        // --- Módulos premium: bloqueados si el flag no está activo ---
        Modulos.Add(new ModuloNavegacion
        {
            Clave = "facturacion", Titulo = "Facturación", Icono = "\U0001F9FE", IconoImagen = IconosPos.Facturacion,
            Bloqueado = !tieneFacturacion, TierRequerido = "Facturador"
        });
        Modulos.Add(new ModuloNavegacion
        {
            Clave = "cloud", Titulo = "Nube y respaldo", Icono = "☁", IconoImagen = IconosPos.Nube,
            Bloqueado = !tieneCloud, TierRequerido = "Cloud"
        });
        Modulos.Add(new ModuloNavegacion
        {
            Clave = "multisede", Titulo = "Multisede", Icono = "\U0001F3EA", IconoImagen = IconosPos.Multisede,
            Bloqueado = !tieneMultisede, TierRequerido = "Cloud"
        });

        // Gestión de usuarios: solo visible para administradores.
        if (_sesion.EsAdministrador)
            Modulos.Add(new ModuloNavegacion { Clave = "usuarios", Titulo = "Usuarios", Icono = "\U0001F465", IconoImagen = IconosPos.Usuarios });

        Modulos.Add(new ModuloNavegacion { Clave = "configuracion", Titulo = "Configuración", Icono = "⚙", IconoImagen = IconosPos.Configuracion });
    }

    private void ConstruirResumen()
    {
        var estado = _licencia.EstadoActual;
        PlanActual = estado.Tier switch
        {
            Core.Enums.TierLicencia.FacturadorPro => "Facturador Pro",
            Core.Enums.TierLicencia.Cloud => "Cloud",
            _ => "Base"
        };
        EnPeriodoGracia = estado.EnPeriodoGracia;
        var feats = estado.FeaturesHabilitadas.Count > 0
            ? string.Join(", ", estado.FeaturesHabilitadas)
            : "modo Base (offline)";
        ResumenLicencia = feats;
    }

    [RelayCommand]
    private void Navegar(string? clave)
    {
        if (string.IsNullOrEmpty(clave)) return;

        var modulo = Modulos.FirstOrDefault(m => m.Clave == clave);
        if (modulo is null) return;

        // Si está bloqueado por licencia, mostramos el upsell en vez de navegar.
        if (modulo.Bloqueado)
        {
            Upsell.Mostrar(modulo);
            return;
        }

        Upsell.Visible = false;
        foreach (var m in Modulos) m.Activo = m.Clave == clave;
        ModuloActivo = clave;

        // Al entrar a Reportes, recalcular con las ventas más recientes del día.
        if (clave == "reportes")
            _ = Reportes.CargarAsync();

        // Al entrar a Nube/Multisede, refrescar el conteo de pendientes por subir.
        if (clave is "cloud" or "multisede")
            _ = Nube.CargarAsync();

        // Al entrar a Usuarios, cargar la lista real y el cupo del plan.
        if (clave == "usuarios")
            _ = Usuarios.CargarAsync();

        // Al entrar a Proveedores, cargar la lista real.
        if (clave == "proveedores")
            _ = Proveedores.CargarAsync();

        // Al entrar a Habitaciones, refrescar el mapa de ocupación.
        if (clave == "habitaciones")
            _ = Habitaciones.CargarAsync();

        // Al entrar a Mesas, refrescar el mapa del salón y las cuentas abiertas.
        if (clave == "mesas")
            _ = Mesas.CargarAsync();

        // Al entrar a Vencimientos, reclasificar el catálogo por estado de vencimiento/stock.
        if (clave == "vencimientos")
            _ = Vencimientos.CargarAsync();
    }
}
