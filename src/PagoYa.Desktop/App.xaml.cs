using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using PagoYa.Core.Contratos;
using PagoYa.Data;
using PagoYa.Desktop.Servicios;
using PagoYa.Desktop.ViewModels;

namespace PagoYa.Desktop;

/// <summary>
/// Punto de entrada WPF y <b>composition root</b> de PagoYa.
///
/// Aquí ocurre el arranque MVVM:
///   1. Se construye el contenedor de DI (Microsoft.Extensions.DependencyInjection).
///   2. Se valida la licencia local (ILicenseService.CargarLicenciaLocal()).
///   3. Se aplica el FEATURE-GATING: según los flags del token se registran los
///      motores reales (SunatInvoiceEngine / CloudSyncService) o sus Null Object.
///   4. Se resuelve y muestra la ventana principal con su ViewModel.
/// </summary>
public partial class App : Application
{
    private IServiceProvider? _servicios;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Evita que el cierre del diálogo de login apague la app antes de abrir
        // el shell (con OnLastWindowClose habría cero ventanas por un instante).
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        var services = new ServiceCollection();
        CompositionRoot.Registrar(services);
        _servicios = services.BuildServiceProvider();

        // Inicializar el esquema SQLite (crea %LocalAppData%\PagoYa\pagoya.db si
        // no existe). Idempotente (CREATE TABLE IF NOT EXISTS).
        var db = _servicios.GetRequiredService<PagoYaDbContext>();
        db.InicializarEsquema();

        // Cargar y validar la licencia ANTES de resolver los servicios premium,
        // para que el feature-gating (ver CompositionRoot) tenga el estado correcto.
        var licencia = _servicios.GetRequiredService<ILicenseService>();
        var estadoLicencia = licencia.CargarLicenciaLocal();

        // 0) GATE DE ACTIVACIÓN (modelo "Base exige licencia"): si no hay un token
        //    auténtico instalado para ESTA máquina, el programa no opera. Se muestra
        //    la pantalla de activación (HWID + pegar token). Sin activar => se cierra.
        if (!estadoLicencia.EstaActivada)
        {
            var activacion = _servicios.GetRequiredService<ActivacionWindow>();
            if (activacion.ShowDialog() != true)
            {
                Shutdown();
                return;
            }
        }

        // 1) Acceso: primer arranque crea la cuenta admin; después pide login.
        //    Solo si autentica se abre el shell (fija SesionActual).
        var login = _servicios.GetRequiredService<LoginWindow>();
        var autenticado = login.ShowDialog() == true;
        if (!autenticado)
        {
            Shutdown();
            return;
        }

        // 2) Shell principal (ya con la sesión establecida).
        var ventana = _servicios.GetRequiredService<MainWindow>();
        var vm = _servicios.GetRequiredService<MainWindowViewModel>();
        vm.CerrarSesionSolicitada = ReiniciarParaCambiarUsuario;
        ventana.DataContext = vm;
        MainWindow = ventana;
        // Con el shell visible, el cierre de la ventana principal sí termina la app.
        ShutdownMode = ShutdownMode.OnMainWindowClose;
        ventana.Show();

        // Seed de demo (si la BD está vacía) + carga inicial de datos reales en
        // las pantallas. Se hace tras Show() para no retrasar el arranque de la UI.
        _ = InicializarDatosAsync(vm);
    }

    /// <summary>
    /// Cierra sesión reiniciando el proceso: la forma más simple y robusta de
    /// volver al login sin arrastrar estado de los ViewModels singleton.
    /// </summary>
    private void ReiniciarParaCambiarUsuario()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exe))
                System.Diagnostics.Process.Start(exe);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PagoYa] Reinicio falló: {ex}");
        }
        Shutdown();
    }

    /// <summary>
    /// Siembra la demo si la BD está vacía y carga los datos reales en las
    /// pantallas. Nunca propaga excepciones al arranque (la app degrada a vacío).
    /// </summary>
    private async Task InicializarDatosAsync(MainWindowViewModel vm)
    {
        try
        {
            var productos = _servicios!.GetRequiredService<IProductoRepository>();
            var cajas = _servicios!.GetRequiredService<ICajaRepository>();
            var cfg = _servicios!.GetRequiredService<IConfiguracionStore>().Leer();
            var rubro = string.IsNullOrWhiteSpace(cfg?.Rubro) ? "bodega" : cfg!.Rubro;
            var hotel = _servicios!.GetRequiredService<IHotelRepository>();
            var mesas = _servicios!.GetRequiredService<IMesaRepository>();
            await SeedDemo.EjecutarSiVacioAsync(productos, cajas, rubro, hotel, mesas);
            await vm.CargarDatosInicialesAsync();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PagoYa] Init datos falló: {ex}");
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        (_servicios as IDisposable)?.Dispose();
        base.OnExit(e);
    }
}
