using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Common;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Gestión de usuarios del POS (solo administrador). Aplica la regla de negocio
/// del tier: en Base solo puede haber 2 usuarios ACTIVOS (1 admin + 1 más);
/// crear más se desbloquea con licencia premium (gating por
/// <see cref="CaracteristicaLicencia.MultiSite"/>). Si el usuario intenta pasar
/// el límite, se muestra el upsell en vez de crear.
/// </summary>
public partial class UsuariosViewModel : ObservableObject
{
    /// <summary>Máximo de usuarios activos en tier Base (admin + 1).</summary>
    public const int LimiteBase = 2;

    private readonly IUsuarioRepository? _repo;
    private readonly ILicenseService? _licencia;
    private readonly SesionActual? _sesion;

    /// <summary>Navegación a la pantalla de planes/activación (la fija el shell).</summary>
    public Action? AbrirPlanes { get; set; }

    public ObservableCollection<UsuarioItem> Usuarios { get; } = new();

    public ObservableCollection<string> RolesDisponibles { get; } = new() { "Cajero", "Administrador" };

    // --- Formulario ---
    [ObservableProperty] private bool _editorVisible;
    [ObservableProperty] private string _formNombreCompleto = "";
    [ObservableProperty] private string _formNombreUsuario = "";
    [ObservableProperty] private string _formPassword = "";
    [ObservableProperty] private string _formRol = "Cajero";

    [ObservableProperty] private string _mensajeEstado = "";

    /// <summary>True si el plan permite usuarios ilimitados (premium).</summary>
    [ObservableProperty] private bool _esPremium;

    /// <summary>Aviso de límite/upsell visible cuando se topa el cupo en Base.</summary>
    [ObservableProperty] private bool _mostrarLimite;

    [ObservableProperty] private string _resumenCupo = "";

    /// <summary>Constructor de DISEÑO.</summary>
    public UsuariosViewModel()
    {
        Usuarios.Add(new UsuarioItem(Guid.NewGuid(), "María Quispe", "maria", "Administrador", true, true));
        Usuarios.Add(new UsuarioItem(Guid.NewGuid(), "José Cajero", "jose", "Cajero", true, false));
        ResumenCupo = "2 de 2 usuarios (plan Base)";
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public UsuariosViewModel(IUsuarioRepository repo, ILicenseService licencia, SesionActual sesion)
    {
        _repo = repo;
        _licencia = licencia;
        _sesion = sesion;
        EsPremium = licencia.TieneCaracteristica(CaracteristicaLicencia.MultiSite);
    }

    /// <summary>Carga la lista real de usuarios y actualiza el resumen de cupo.</summary>
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_repo is null) return;
        EsPremium = _licencia?.TieneCaracteristica(CaracteristicaLicencia.MultiSite) == true;

        var lista = await _repo.ListarAsync(ct);
        Usuarios.Clear();
        var actualId = _sesion?.Usuario?.Id;
        foreach (var u in lista)
            Usuarios.Add(new UsuarioItem(u.Id, u.NombreCompleto, u.NombreUsuario,
                RolTexto(u.Rol), u.Activo, u.Id == actualId));

        ActualizarCupo(await _repo.ContarActivosAsync(ct));
    }

    private void ActualizarCupo(int activos)
    {
        ResumenCupo = EsPremium
            ? $"{activos} usuarios (plan premium: ilimitados)"
            : $"{activos} de {LimiteBase} usuarios (plan Base)";
    }

    private bool PuedeAgregar(int activos) => EsPremium || activos < LimiteBase;

    [RelayCommand]
    private async Task NuevoUsuarioAsync()
    {
        if (_repo is null) return;
        MostrarLimite = false;
        MensajeEstado = "";

        var activos = await _repo.ContarActivosAsync();
        if (!PuedeAgregar(activos))
        {
            // Se topó el cupo del tier Base → upsell en vez de crear.
            MostrarLimite = true;
            MensajeEstado = "Alcanzaste el máximo de usuarios del plan Base. Mejora a un plan premium para agregar más cajeros.";
            return;
        }

        FormNombreCompleto = "";
        FormNombreUsuario = "";
        FormPassword = "";
        FormRol = "Cajero";
        EditorVisible = true;
    }

    [RelayCommand]
    private void CancelarEdicion() => EditorVisible = false;

    [RelayCommand]
    private void IrAPlanes() => AbrirPlanes?.Invoke();

    [RelayCommand]
    private async Task GuardarUsuarioAsync()
    {
        if (_repo is null) return;

        var usuario = FormNombreUsuario.Trim().ToLowerInvariant();
        if (usuario.Length < 3) { MensajeEstado = "El usuario debe tener al menos 3 caracteres."; return; }
        if (FormPassword.Length < 6) { MensajeEstado = "La contraseña debe tener al menos 6 caracteres."; return; }

        // Re-chequeo del cupo por si cambió entre abrir el formulario y guardar.
        var activos = await _repo.ContarActivosAsync();
        if (!PuedeAgregar(activos))
        {
            EditorVisible = false;
            MostrarLimite = true;
            MensajeEstado = "Alcanzaste el máximo de usuarios del plan Base.";
            return;
        }

        if (await _repo.ObtenerPorNombreAsync(usuario) is not null)
        {
            MensajeEstado = $"Ya existe un usuario «{usuario}».";
            return;
        }

        try
        {
            var salt = Passwords.NuevoSalt();
            var nuevo = new Usuario
            {
                NombreUsuario = usuario,
                NombreCompleto = string.IsNullOrWhiteSpace(FormNombreCompleto) ? usuario : FormNombreCompleto.Trim(),
                PasswordSalt = salt,
                PasswordHash = Passwords.Hash(FormPassword, salt),
                Rol = FormRol == "Administrador" ? RolUsuario.Administrador : RolUsuario.Cajero,
                Activo = true
            };
            await _repo.GuardarAsync(nuevo);
            EditorVisible = false;
            MensajeEstado = $"Usuario «{nuevo.NombreCompleto}» creado.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo crear: {ex.Message}"; }
    }

    [RelayCommand]
    private async Task DesactivarUsuarioAsync(UsuarioItem? item)
    {
        if (_repo is null || item is null) return;
        if (item.EsSesionActual) { MensajeEstado = "No puedes desactivar tu propia sesión."; return; }

        try
        {
            await _repo.DesactivarAsync(item.Id);
            MensajeEstado = $"Usuario «{item.NombreCompleto}» desactivado.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo desactivar: {ex.Message}"; }
    }

    private static string RolTexto(RolUsuario r) => r == RolUsuario.Administrador ? "Administrador" : "Cajero";
}

/// <summary>Fila de la tabla de usuarios.</summary>
public sealed record UsuarioItem(Guid Id, string NombreCompleto, string NombreUsuario,
    string Rol, bool Activo, bool EsSesionActual);
