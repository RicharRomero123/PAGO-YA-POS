using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Common;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Pantalla inicial del POS: en el PRIMER arranque crea la cuenta de
/// administrador (setup); después pide iniciar sesión. Al autenticar, fija la
/// <see cref="SesionActual"/> e invoca <see cref="LoginExitoso"/> para que la
/// ventana de login se cierre y arranque el shell principal.
/// </summary>
public partial class LoginViewModel : ObservableObject
{
    private readonly IUsuarioRepository? _usuarios;
    private readonly SesionActual? _sesion;
    private readonly IConfiguracionStore? _config;

    /// <summary>Callback que la ventana de login usa para cerrarse tras autenticar.</summary>
    public Action? LoginExitoso { get; set; }

    /// <summary>Rubros disponibles para el paso de onboarding.</summary>
    public IReadOnlyList<RubroInfo> Rubros => PlantillasRubro.Todos;

    /// <summary>True cuando toca elegir el rubro del negocio (tras crear el admin).</summary>
    [ObservableProperty] private bool _pedirRubro;

    /// <summary>True = crear cuenta admin (bootstrap); False = iniciar sesión.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(TituloAccion))]
    [NotifyPropertyChangedFor(nameof(EsSetup))]
    private bool _modoSetup;

    [ObservableProperty] private string _nombreCompleto = "";
    [ObservableProperty] private string _nombreUsuario = "";
    [ObservableProperty] private string _password = "";
    [ObservableProperty] private string _passwordConfirmar = "";
    [ObservableProperty] private string _mensajeError = "";
    [ObservableProperty] private bool _ocupado;

    public bool EsSetup => ModoSetup;
    public string TituloAccion => ModoSetup ? "Crear cuenta" : "Entrar";

    /// <summary>Constructor de DISEÑO (para el diseñador de la ventana de login).</summary>
    public LoginViewModel()
    {
        ModoSetup = true;
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public LoginViewModel(IUsuarioRepository usuarios, SesionActual sesion, IConfiguracionStore config)
    {
        _usuarios = usuarios;
        _sesion = sesion;
        _config = config;
    }

    /// <summary>Decide setup vs login según si ya existe algún usuario. Llamar al abrir.</summary>
    public async Task InicializarAsync()
    {
        if (_usuarios is null) return;
        try { ModoSetup = !await _usuarios.ExisteAlgunoAsync(); }
        catch { ModoSetup = false; }
    }

    [RelayCommand]
    private async Task EntrarAsync()
    {
        if (_usuarios is null || _sesion is null) return;
        MensajeError = "";

        if (ModoSetup) await CrearAdminAsync();
        else await IniciarSesionAsync();
    }

    private async Task CrearAdminAsync()
    {
        var usuario = NombreUsuario.Trim().ToLowerInvariant();
        if (usuario.Length < 3) { MensajeError = "El usuario debe tener al menos 3 caracteres."; return; }
        if (Password.Length < 6) { MensajeError = "La contraseña debe tener al menos 6 caracteres."; return; }
        if (Password != PasswordConfirmar) { MensajeError = "Las contraseñas no coinciden."; return; }

        Ocupado = true;
        try
        {
            // Doble verificación anti-carrera: si ya existe alguien, no recrear admin.
            if (await _usuarios!.ExisteAlgunoAsync())
            {
                ModoSetup = false;
                MensajeError = "Ya existe una cuenta. Inicia sesión.";
                return;
            }

            var salt = Passwords.NuevoSalt();
            var admin = new Usuario
            {
                NombreUsuario = usuario,
                NombreCompleto = string.IsNullOrWhiteSpace(NombreCompleto) ? "Administrador" : NombreCompleto.Trim(),
                PasswordSalt = salt,
                PasswordHash = Passwords.Hash(Password, salt),
                Rol = RolUsuario.Administrador,
                Activo = true
            };
            await _usuarios.GuardarAsync(admin);
            admin.UltimoAccesoUtc = DateTime.UtcNow;
            await _usuarios.RegistrarAccesoAsync(admin.Id, admin.UltimoAccesoUtc.Value);

            _sesion!.Establecer(admin);
            // Siguiente paso del onboarding: elegir el rubro del negocio.
            PedirRubro = true;
        }
        catch (Exception ex) { MensajeError = $"No se pudo crear la cuenta: {ex.Message}"; }
        finally { Ocupado = false; }
    }

    /// <summary>Guarda el rubro elegido, precarga su plantilla y entra al POS.</summary>
    [RelayCommand]
    private void ElegirRubro(string? clave)
    {
        if (string.IsNullOrWhiteSpace(clave)) clave = "bodega";

        // Persistimos el rubro en la config (la plantilla se siembra en App.OnStartup
        // leyendo este valor). Si aún no hay config, creamos una con lo mínimo.
        try
        {
            var cfg = _config?.Leer() ?? new ConfiguracionNegocio();
            cfg.Rubro = clave!;
            cfg.PieTicket = PlantillasRubro.PieTicket(clave!);
            _config?.Guardar(cfg);
        }
        catch { /* si falla, se seguirá con el rubro por defecto */ }

        LoginExitoso?.Invoke();
    }

    private async Task IniciarSesionAsync()
    {
        if (string.IsNullOrWhiteSpace(NombreUsuario) || string.IsNullOrWhiteSpace(Password))
        {
            MensajeError = "Ingresa tu usuario y contraseña.";
            return;
        }

        Ocupado = true;
        try
        {
            // El usuario se guarda en minúsculas al crear la cuenta; normalizamos el
            // login para no fallar por el autocapitalizado del teclado/autocompletado.
            var u = await _usuarios!.ObtenerPorNombreAsync(NombreUsuario.Trim().ToLowerInvariant());
            if (u is null || !u.Activo || !Passwords.Verificar(Password, u.PasswordHash, u.PasswordSalt))
            {
                MensajeError = "Usuario o contraseña incorrectos.";
                return;
            }

            u.UltimoAccesoUtc = DateTime.UtcNow;
            await _usuarios.RegistrarAccesoAsync(u.Id, u.UltimoAccesoUtc.Value);
            _sesion!.Establecer(u);
            LoginExitoso?.Invoke();
        }
        catch (Exception ex) { MensajeError = $"No se pudo iniciar sesión: {ex.Message}"; }
        finally { Ocupado = false; }
    }
}
