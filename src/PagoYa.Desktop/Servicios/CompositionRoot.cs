using System.IO;
using System.Net.Http;
using Microsoft.Extensions.DependencyInjection;
using PagoYa.Cloud;
using PagoYa.Core.Contratos;
using PagoYa.Data;
using PagoYa.Data.Repositorios;
using PagoYa.Desktop.Servicios.Impresion;
using PagoYa.Desktop.ViewModels;
using PagoYa.Invoicing.Sunat;
using PagoYa.Licensing;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Composición del grafo de dependencias y aplicación del <b>feature-gating</b>.
///
/// Aquí se materializa la regla de negocio clave de PagoYa: los módulos premium
/// (facturación, nube) se resuelven al motor REAL solo si la licencia habilita
/// su flag; de lo contrario se resuelve un <b>Null Object</b> que rechaza la
/// operación. El resto de la app depende siempre de la interfaz, sin saber si
/// hay licencia o no. El gating vive en la composición, no esparcido en el código.
/// </summary>
public static class CompositionRoot
{
    public static void Registrar(IServiceCollection services)
    {
        // --- Persistencia local (SQLite) ---
        // El .db vive en %LocalAppData%\PagoYa\pagoya.db (datos de máquina, no
        // roaming). Se crea la carpeta si no existe; el esquema se inicializa en
        // App.OnStartup vía PagoYaDbContext.InicializarEsquema().
        var rutaDb = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PagoYa", "pagoya.db");
        Directory.CreateDirectory(Path.GetDirectoryName(rutaDb)!);

        services.AddSingleton(new PagoYaDbContext(rutaDb));
        services.AddSingleton<IProductoRepository, ProductoRepository>();
        services.AddSingleton<IVentaRepository, VentaRepository>();
        services.AddSingleton<ICajaRepository, CajaRepository>();
        services.AddSingleton<IReportesRepository, ReportesRepository>();
        services.AddSingleton<IOutboxStore, OutboxStore>();
        services.AddSingleton<IUsuarioRepository, UsuarioRepository>();
        services.AddSingleton<IProveedorRepository, ProveedorRepository>();
        services.AddSingleton<IHotelRepository, HotelRepository>();
        services.AddSingleton<IMesaRepository, MesaRepository>();

        // Sesión del usuario logueado (la fija el login antes de abrir el shell).
        services.AddSingleton<SesionActual>();

        // --- Configuración persistente del negocio (JSON en %LocalAppData%) ---
        services.AddSingleton<IConfiguracionStore, ConfiguracionStoreArchivo>();

        // --- Impresión térmica ESC/POS ---
        // DatosNegocio se materializa desde la config guardada (o valores por
        // defecto la primera vez). Es un singleton MUTABLE: al guardar la pantalla
        // de Configuración se actualiza esta misma instancia, de modo que los
        // tickets reflejan los cambios sin reiniciar. NombreImpresora vacío/null
        // => usa la impresora predeterminada de Windows.
        services.AddSingleton(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguracionStore>().Leer() ?? new ConfiguracionNegocio();
            return new DatosNegocio
            {
                Nombre = cfg.NombreNegocio,
                Ruc = cfg.Ruc,
                Direccion = cfg.Direccion,
                Telefono = cfg.Telefono,
                PieTicket = cfg.PieTicket,
                NombreImpresora = string.IsNullOrWhiteSpace(cfg.NombreImpresora) ? null : cfg.NombreImpresora,
                ColumnasTicket = cfg.ColumnasTicket,
                AbrirCajonEnEfectivo = cfg.AbrirCajonEnEfectivo,
                LogoRuta = cfg.LogoRuta
            };
        });
        services.AddSingleton<ITicketPrinter, TicketPrinterEscPos>();
        services.AddSingleton<IVistaPreviaTicket, VistaPreviaTicket>();

        // --- Licenciamiento (validación local del token firmado) ---
        services.AddSingleton<IHardwareId, HardwareIdWindows>();
        services.AddSingleton<ILicenseStore, LicenseStoreArchivo>();
        services.AddSingleton<LicenseTokenValidator>();
        services.AddSingleton<ILicenseService, LicenseService>();

        // --- Módulos premium con FEATURE-GATING ---
        // Se registran como factory: al resolverse, consultan el estado de
        // licencia YA cargado (App.OnStartup llama CargarLicenciaLocal antes)
        // y devuelven el motor real o el Null Object según el flag.

        // Datos del emisor SUNAT desde la config persistida. Singleton compartido
        // por el motor de facturación y por la pantalla de Facturación (mostrar
        // RUC/serie/ambiente). Ambiente Simulado por defecto (firma + CDR local sin
        // credenciales SOL); al conectar certificado + PSE se cambia el ambiente.
        services.AddSingleton(sp =>
        {
            var cfg = sp.GetRequiredService<IConfiguracionStore>().Leer() ?? new ConfiguracionNegocio();
            return new OpcionesEmisor
            {
                Ruc = cfg.Ruc,
                RazonSocial = string.IsNullOrWhiteSpace(cfg.NombreNegocio) ? "PagoYa" : cfg.NombreNegocio,
                NombreComercial = cfg.NombreNegocio,
                Direccion = cfg.Direccion,
                Ambiente = AmbienteSunat.Simulado
            };
        });

        services.AddSingleton<IInvoiceEngine>(sp =>
        {
            var licencia = sp.GetRequiredService<ILicenseService>();
            if (!licencia.TieneCaracteristica(CaracteristicaLicencia.Invoicing))
                return new InvoiceEngineDeshabilitado();

            return new SunatInvoiceEngine(sp.GetRequiredService<OpcionesEmisor>());
        });

        services.AddSingleton<ISyncService>(sp =>
        {
            var licencia = sp.GetRequiredService<ILicenseService>();
            if (!licencia.TieneCaracteristica(CaracteristicaLicencia.CloudSync))
                return new SyncServiceDeshabilitado();

            var outbox = sp.GetRequiredService<IOutboxStore>();
            var cfg = sp.GetRequiredService<IConfiguracionStore>().Leer() ?? new ConfiguracionNegocio();
            var token = sp.GetRequiredService<ILicenseStore>().LeerToken();

            // Con URL de nube configurada + token de licencia => transporte HTTP real
            // (autentica con Bearer y sube/baja contra /sync). Sin ella, transporte
            // simulado: respaldo/consolidación local, sigue operando offline.
            if (!string.IsNullOrWhiteSpace(cfg.SyncUrlBase) && !string.IsNullOrWhiteSpace(token))
            {
                // OrigenCajaId sale de la config persistida — la MISMA fuente que
                // estampa `origen_caja_id` en los eventos que se suben. Tiene que
                // ser el mismo valor en ambos lados o el filtro de eco del backend
                // no filtra nada (server/README.md §7.1).
                var opciones = new OpcionesSync
                {
                    UrlBase = cfg.SyncUrlBase,
                    TokenLicencia = token,
                    OrigenCajaId = cfg.OrigenCajaId
                };
                return new CloudSyncService(outbox, new HttpSyncTransport(new HttpClient(), opciones), opciones);
            }

            return new CloudSyncService(outbox, new TransporteSyncEnMemoria(), new OpcionesSync());
        });

        // --- UI (ventana + view models) ---
        // Los VMs de pantalla se registran con sus dependencias (repos/servicios)
        // para usar los constructores de PRODUCCIÓN (no los de diseño).
        services.AddSingleton<RecepcionPosViewModel>();
        services.AddSingleton<MesasViewModel>();
        services.AddSingleton<CobroRapidoViewModel>();
        services.AddSingleton<CajaViewModel>();
        services.AddSingleton<InventarioViewModel>();
        services.AddSingleton<ReportesViewModel>();
        services.AddSingleton<ConfiguracionViewModel>();
        services.AddSingleton<FacturacionViewModel>();
        services.AddSingleton<NubeViewModel>();
        services.AddSingleton<UsuariosViewModel>();
        services.AddSingleton<ProveedoresViewModel>();
        services.AddSingleton<HabitacionesViewModel>();
        services.AddSingleton<VencimientosViewModel>();

        // Activación de licencia: ventana + VM (gate de arranque; una sola vez).
        services.AddTransient<ActivacionViewModel>();
        services.AddTransient<ActivacionWindow>();

        // Login: ventana + VM (transient; se usa una vez al arrancar).
        services.AddTransient<LoginViewModel>();
        services.AddTransient<LoginWindow>();

        services.AddSingleton<MainWindow>();
        services.AddSingleton<MainWindowViewModel>();
    }
}
