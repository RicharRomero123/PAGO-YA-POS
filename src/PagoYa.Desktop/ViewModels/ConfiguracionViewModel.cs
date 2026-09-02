using System.Collections.ObjectModel;
using System.Drawing.Printing;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios;
using PagoYa.Desktop.Servicios.Impresion;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Configuración del POS: datos del negocio (encabezan el ticket), impresora
/// térmica y ancho de papel. PERSISTE en <see cref="IConfiguracionStore"/> y, al
/// guardar, actualiza el singleton <see cref="DatosNegocio"/> en vivo para que la
/// impresión refleje los cambios sin reiniciar. También muestra el plan/licencia
/// vigente (solo lectura) leído de <see cref="ILicenseService"/>.
/// </summary>
public partial class ConfiguracionViewModel : ObservableObject
{
    /// <summary>Etiqueta para "usar la impresora predeterminada de Windows".</summary>
    public const string ImpresoraPredeterminada = "(Predeterminada del sistema)";

    private readonly IConfiguracionStore? _store;
    private readonly DatosNegocio? _datosNegocio;
    private readonly ITicketPrinter? _printer;
    private readonly ILicenseService? _licencia;

    // --- Negocio ---
    [ObservableProperty] private string _nombreNegocio = "Bodega Doña Rosa";

    /// <summary>Rubro del negocio (clave). Determina textos del ticket y plantillas.</summary>
    [ObservableProperty] private string _rubroClave = "bodega";

    /// <summary>Lista de rubros para el selector.</summary>
    public IReadOnlyList<RubroInfo> Rubros => PlantillasRubro.Todos;

    [ObservableProperty] private string _ruc = "20512345678";
    [ObservableProperty] private string _direccion = "Av. Los Próceres 145, San Juan de Lurigancho";
    [ObservableProperty] private string _telefono = "01 555 5555";
    [ObservableProperty] private string _pieTicket = "¡Gracias por su compra!";

    /// <summary>Ruta local del logo del negocio (para la vista previa del ticket).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(TieneLogo))]
    private string? _logoRuta;

    public bool TieneLogo => !string.IsNullOrWhiteSpace(LogoRuta);

    // --- Impresora ---
    public ObservableCollection<string> ImpresorasDisponibles { get; } = new();
    public ObservableCollection<string> OpcionesAncho { get; } = new() { "58 mm", "80 mm" };
    [ObservableProperty] private string _impresoraSeleccionada = ImpresoraPredeterminada;
    [ObservableProperty] private string _anchoPapel = "80 mm";

    /// <summary>Si la impresora abre el cajón al cobrar en efectivo (ESC/POS).</summary>
    [ObservableProperty] private bool _abrirCajonEnEfectivo = true;

    // --- Nube (respaldo / multi-caja) ---
    /// <summary>
    /// URL base del backend de sincronización (ej. https://api.pagoya.pe). La fija
    /// soporte al activar el plan Cloud; vacía = respaldo local/offline. Cambiarla
    /// exige reiniciar (el transporte se elige al arrancar en CompositionRoot).
    /// </summary>
    [ObservableProperty] private string _syncUrlBase = "";

    // --- Estado de la pantalla ---
    [ObservableProperty] private string _mensajeEstado = "";

    // --- Licencia (real) ---
    [ObservableProperty] private string _planActual = "PagoYa Base";
    [ObservableProperty] private string _detalleLicencia = "";
    [ObservableProperty] private bool _enPeriodoGracia;

    /// <summary>HWID de este equipo: el usuario lo envía para que le emitan un token atado a su PC.</summary>
    [ObservableProperty] private string _hwid = "";

    /// <summary>Token que el usuario pega para activar/mejorar su plan.</summary>
    [ObservableProperty] private string _tokenLicencia = "";

    [ObservableProperty] private string _mensajeLicencia = "";

    /// <summary>True tras una activación válida: hay que reiniciar para cargar los módulos premium.</summary>
    [ObservableProperty] private bool _requiereReinicio;

    /// <summary>Constructor de DISEÑO: valores mock, no toca disco.</summary>
    public ConfiguracionViewModel()
    {
        ImpresorasDisponibles.Add(ImpresoraPredeterminada);
        ImpresorasDisponibles.Add("EPSON TM-T20III (USB)");
        ImpresoraSeleccionada = "EPSON TM-T20III (USB)";
        Hwid = "A1B2-C3D4-E5F6-7890";
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public ConfiguracionViewModel(
        IConfiguracionStore store,
        DatosNegocio datosNegocio,
        ITicketPrinter printer,
        ILicenseService licencia,
        IHardwareId hardwareId)
    {
        _store = store;
        _datosNegocio = datosNegocio;
        _printer = printer;
        _licencia = licencia;

        CargarImpresoras();
        CargarConfig();
        CargarLicencia();

        try { Hwid = hardwareId.ObtenerHwid(); }
        catch { Hwid = "(no disponible)"; }
    }

    /// <summary>Enumera las impresoras instaladas en Windows (+ opción predeterminada).</summary>
    private void CargarImpresoras()
    {
        ImpresorasDisponibles.Add(ImpresoraPredeterminada);
        try
        {
            foreach (string nombre in PrinterSettings.InstalledPrinters)
                ImpresorasDisponibles.Add(nombre);
        }
        catch
        {
            // Sin subsistema de impresión (headless): solo queda la predeterminada.
        }
    }

    /// <summary>Carga la configuración persistida en los campos del formulario.</summary>
    private void CargarConfig()
    {
        var cfg = _store!.Leer();
        if (cfg is null) return; // primera ejecución: se quedan los valores por defecto

        NombreNegocio = cfg.NombreNegocio;
        RubroClave = string.IsNullOrWhiteSpace(cfg.Rubro) ? "bodega" : cfg.Rubro;
        LogoRuta = cfg.LogoRuta;
        Ruc = cfg.Ruc;
        Direccion = cfg.Direccion;
        Telefono = cfg.Telefono;
        PieTicket = cfg.PieTicket;
        AnchoPapel = cfg.AnchoPapelMm <= 58 ? "58 mm" : "80 mm";
        AbrirCajonEnEfectivo = cfg.AbrirCajonEnEfectivo;
        SyncUrlBase = cfg.SyncUrlBase ?? "";

        ImpresoraSeleccionada = string.IsNullOrWhiteSpace(cfg.NombreImpresora)
            ? ImpresoraPredeterminada
            : cfg.NombreImpresora!;

        // Si la impresora guardada ya no está instalada, la ofrecemos igual para
        // no perder el ajuste del usuario (podría reconectarla luego).
        if (ImpresoraSeleccionada != ImpresoraPredeterminada
            && !ImpresorasDisponibles.Contains(ImpresoraSeleccionada))
            ImpresorasDisponibles.Add(ImpresoraSeleccionada);
    }

    private void CargarLicencia()
    {
        if (_licencia is null) return;

        var estado = _licencia.EstadoActual;
        PlanActual = estado.Tier switch
        {
            TierLicencia.FacturadorPro => "PagoYa Facturador Pro",
            TierLicencia.Cloud => "PagoYa Cloud",
            _ => "PagoYa Base"
        };
        EnPeriodoGracia = estado.EnPeriodoGracia;
        var feats = estado.FeaturesHabilitadas.Count > 0
            ? string.Join(", ", estado.FeaturesHabilitadas)
            : "ninguna (modo Base)";
        DetalleLicencia = $"Características activas: {feats}. {estado.Motivo}".Trim();
    }

    /// <summary>Copia el HWID al portapapeles para que el usuario lo envíe por WhatsApp.</summary>
    [RelayCommand]
    private void CopiarHwid()
    {
        try
        {
            System.Windows.Clipboard.SetText(Hwid);
            MensajeLicencia = "HWID copiado. Envíalo para que te generen tu licencia.";
        }
        catch
        {
            MensajeLicencia = "No se pudo copiar el HWID.";
        }
    }

    /// <summary>Valida y persiste el token pegado; instruye reiniciar si desbloquea premium.</summary>
    [RelayCommand]
    private void ActivarLicencia()
    {
        if (_licencia is null) return;

        var token = TokenLicencia?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(token))
        {
            MensajeLicencia = "Pega el token de licencia que recibiste.";
            return;
        }

        var estado = _licencia.ActivarLicencia(token);
        CargarLicencia();

        if (estado.EsValida && estado.Tier != TierLicencia.Base)
        {
            RequiereReinicio = true;
            TokenLicencia = "";
            MensajeLicencia = $"¡Licencia {PlanActual} activada! Reinicia PagoYa para habilitar los módulos premium.";
        }
        else
        {
            RequiereReinicio = false;
            MensajeLicencia = $"No se pudo activar: {estado.Motivo}";
        }
    }

    /// <summary>
    /// Guarda el HWID en un archivo de texto (para copiarlo a una USB y enviarlo
    /// desde otro equipo). Útil en cajas SIN internet.
    /// </summary>
    [RelayCommand]
    private void GuardarHwidArchivo()
    {
        var dlg = new SaveFileDialog
        {
            Title = "Guardar mi código de equipo (HWID)",
            Filter = "Texto (*.txt)|*.txt",
            FileName = "mi-hwid-pagoya.txt"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            File.WriteAllText(dlg.FileName, Hwid);
            MensajeLicencia = "Código guardado. Cópialo a una USB y envíalo para generar tu licencia.";
        }
        catch (Exception ex)
        {
            MensajeLicencia = $"No se pudo guardar el archivo: {ex.Message}";
        }
    }

    /// <summary>
    /// Importa el token desde un archivo (.lic/.txt) que llegó por USB y lo activa,
    /// sin tener que escribir a mano el token largo. Útil en cajas SIN internet.
    /// </summary>
    [RelayCommand]
    private void ImportarLicenciaArchivo()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Importar licencia desde archivo",
            Filter = "Licencia PagoYa (*.lic;*.txt)|*.lic;*.txt|Todos los archivos (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var contenido = File.ReadAllText(dlg.FileName).Trim();
            if (string.IsNullOrWhiteSpace(contenido))
            {
                MensajeLicencia = "El archivo está vacío.";
                return;
            }
            TokenLicencia = contenido;
            ActivarLicencia(); // valida y activa igual que el token pegado
        }
        catch (Exception ex)
        {
            MensajeLicencia = $"No se pudo leer el archivo: {ex.Message}";
        }
    }

    /// <summary>Persiste la config y actualiza el singleton DatosNegocio en vivo.</summary>
    [RelayCommand]
    private void Guardar()
    {
        if (_store is null) return;

        if (string.IsNullOrWhiteSpace(NombreNegocio))
        {
            MensajeEstado = "El nombre del negocio es obligatorio.";
            return;
        }

        var cfg = new ConfiguracionNegocio
        {
            NombreNegocio = NombreNegocio.Trim(),
            Rubro = string.IsNullOrWhiteSpace(RubroClave) ? "bodega" : RubroClave,
            Ruc = Ruc.Trim(),
            Direccion = Direccion.Trim(),
            Telefono = Telefono.Trim(),
            PieTicket = string.IsNullOrWhiteSpace(PieTicket) ? "¡Gracias por su compra!" : PieTicket.Trim(),
            NombreImpresora = ImpresoraSeleccionada == ImpresoraPredeterminada ? null : ImpresoraSeleccionada,
            AnchoPapelMm = AnchoPapel.StartsWith("58") ? 58 : 80,
            AbrirCajonEnEfectivo = AbrirCajonEnEfectivo,
            LogoRuta = LogoRuta,
            SyncUrlBase = string.IsNullOrWhiteSpace(SyncUrlBase) ? null : SyncUrlBase.Trim(),
            // Preservamos la preferencia de modo táctil (se activa desde la pantalla de cobro).
            ModoTactil = _store.Leer()?.ModoTactil ?? false
        };

        try
        {
            _store.Guardar(cfg);
            AplicarAlNegocioVivo(cfg);
            MensajeEstado = "Configuración guardada. Los próximos tickets usarán estos datos.";
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo guardar: {ex.Message}";
        }
    }

    /// <summary>Vuelca la config recién guardada al DatosNegocio compartido con el printer.</summary>
    private void AplicarAlNegocioVivo(ConfiguracionNegocio cfg)
    {
        if (_datosNegocio is null) return;
        _datosNegocio.Nombre = cfg.NombreNegocio;
        _datosNegocio.Ruc = cfg.Ruc;
        _datosNegocio.Direccion = cfg.Direccion;
        _datosNegocio.Telefono = cfg.Telefono;
        _datosNegocio.PieTicket = cfg.PieTicket;
        _datosNegocio.NombreImpresora = cfg.NombreImpresora;
        _datosNegocio.ColumnasTicket = cfg.ColumnasTicket;
        _datosNegocio.AbrirCajonEnEfectivo = cfg.AbrirCajonEnEfectivo;
        _datosNegocio.LogoRuta = cfg.LogoRuta;
    }

    /// <summary>Elige un logo y lo copia a la carpeta local del negocio.</summary>
    [RelayCommand]
    private void CargarLogo()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Elegir logo del negocio",
            Filter = "Imágenes (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var carpeta = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PagoYa", "img");
            Directory.CreateDirectory(carpeta);
            var destino = Path.Combine(carpeta, $"logo_{Guid.NewGuid():N}{Path.GetExtension(dlg.FileName)}");
            File.Copy(dlg.FileName, destino, overwrite: true);
            LogoRuta = destino;
            MensajeEstado = "Logo cargado. Guarda los cambios para aplicarlo.";
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo cargar el logo: {ex.Message}"; }
    }

    [RelayCommand]
    private void QuitarLogo() => LogoRuta = null;

    /// <summary>Envía el pulso de apertura al cajón para probar el conector físico.</summary>
    [RelayCommand]
    private async Task ProbarCajonAsync()
    {
        if (_printer is null)
        {
            MensajeEstado = "Impresión no disponible en este entorno.";
            return;
        }
        MensajeEstado = "Enviando pulso al cajón…";
        var resultado = await _printer.AbrirCajonAsync();
        MensajeEstado = resultado.Exito
            ? "Pulso enviado. El cajón debería abrirse."
            : $"No se pudo abrir el cajón: {resultado.Mensaje}";
    }

    /// <summary>Imprime un ticket de prueba con los datos actuales (no persiste nada).</summary>
    [RelayCommand]
    private async Task ImprimirPruebaAsync()
    {
        if (_printer is null || _datosNegocio is null)
        {
            MensajeEstado = "Impresión no disponible en este entorno.";
            return;
        }

        // Aplicamos los valores del formulario (aunque no se haya guardado) para
        // que la prueba refleje lo que el usuario está viendo en pantalla.
        AplicarAlNegocioVivo(new ConfiguracionNegocio
        {
            NombreNegocio = string.IsNullOrWhiteSpace(NombreNegocio) ? "PagoYa" : NombreNegocio.Trim(),
            Ruc = Ruc.Trim(),
            Direccion = Direccion.Trim(),
            Telefono = Telefono.Trim(),
            PieTicket = string.IsNullOrWhiteSpace(PieTicket) ? "¡Gracias por su compra!" : PieTicket.Trim(),
            NombreImpresora = ImpresoraSeleccionada == ImpresoraPredeterminada ? null : ImpresoraSeleccionada,
            AnchoPapelMm = AnchoPapel.StartsWith("58") ? 58 : 80,
            AbrirCajonEnEfectivo = AbrirCajonEnEfectivo,
            LogoRuta = LogoRuta
        });

        MensajeEstado = "Enviando página de prueba…";
        var resultado = await _printer.ImprimirTicketVentaAsync(VentaDePrueba());
        MensajeEstado = resultado.Exito
            ? "Página de prueba enviada a la impresora."
            : $"No se pudo imprimir: {resultado.Mensaje}";
    }

    /// <summary>Venta ficticia para la prueba de impresión.</summary>
    private static Venta VentaDePrueba()
    {
        var venta = new Venta
        {
            Numero = "PRUEBA-0001",
            FechaHora = DateTime.Now,
            MetodoPago = MetodoPago.Efectivo,
            SubTotal = 8.47m,
            Igv = 1.53m,
            Total = 10.00m,
            MontoRecibido = 20.00m
        };
        venta.Detalles.Add(new DetalleVenta
        {
            DescripcionProducto = "Producto de prueba",
            Cantidad = 2,
            PrecioUnitario = 5.00m,
            Importe = 10.00m
        });
        return venta;
    }
}
