using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Gestión de proveedores (distribuidores/mayoristas). CRUD contra
/// <see cref="IProveedorRepository"/>. Los productos del inventario se enlazan a
/// un proveedor para saber a quién reabastecer.
/// </summary>
public partial class ProveedoresViewModel : ObservableObject
{
    private readonly IProveedorRepository? _repo;

    public ObservableCollection<ProveedorItem> Proveedores { get; } = new();

    [ObservableProperty] private bool _editorVisible;
    [ObservableProperty] private Guid _editandoId;
    [ObservableProperty] private string _formNombre = "";
    [ObservableProperty] private string _formRuc = "";
    [ObservableProperty] private string _formContacto = "";
    [ObservableProperty] private string _formTelefono = "";
    [ObservableProperty] private string _formDireccion = "";
    [ObservableProperty] private string _formNotas = "";
    [ObservableProperty] private string _mensajeEstado = "";
    [ObservableProperty] private bool _vacio;

    /// <summary>Constructor de DISEÑO.</summary>
    public ProveedoresViewModel()
    {
        Proveedores.Add(new ProveedorItem(Guid.NewGuid(), "Distribuidora Andina", "20601234567", "Luis Pérez", "987 654 321", "Rep. lunes y jueves"));
        Proveedores.Add(new ProveedorItem(Guid.NewGuid(), "Backus (cervezas)", "20100113610", "Pedido app", "01 311 3000", ""));
        Proveedores.Add(new ProveedorItem(Guid.NewGuid(), "Gloria S.A.", "20100190797", "Ventas mayorista", "01 470 7170", ""));
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public ProveedoresViewModel(IProveedorRepository repo) => _repo = repo;

    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_repo is null) return;
        var lista = await _repo.ListarAsync(true, ct);
        Proveedores.Clear();
        foreach (var p in lista)
            Proveedores.Add(new ProveedorItem(p.Id, p.Nombre, p.Ruc, p.Contacto, p.Telefono, p.Notas));
        Vacio = Proveedores.Count == 0;
    }

    [RelayCommand]
    private void NuevoProveedor()
    {
        EditandoId = Guid.Empty;
        FormNombre = FormRuc = FormContacto = FormTelefono = FormDireccion = FormNotas = "";
        EditorVisible = true;
    }

    [RelayCommand]
    private void EditarProveedor(ProveedorItem? item)
    {
        if (item is null) return;
        EditandoId = item.Id;
        FormNombre = item.Nombre;
        FormRuc = item.Ruc ?? "";
        FormContacto = item.Contacto ?? "";
        FormTelefono = item.Telefono ?? "";
        FormDireccion = "";
        FormNotas = item.Notas ?? "";
        EditorVisible = true;
    }

    [RelayCommand]
    private void CancelarEdicion() => EditorVisible = false;

    [RelayCommand]
    private async Task GuardarProveedorAsync()
    {
        if (_repo is null) return;
        if (string.IsNullOrWhiteSpace(FormNombre)) { MensajeEstado = "El nombre es obligatorio."; return; }
        try
        {
            var prov = new Proveedor
            {
                Id = EditandoId == Guid.Empty ? Guid.NewGuid() : EditandoId,
                Nombre = FormNombre.Trim(),
                Ruc = Vacio2(FormRuc),
                Contacto = Vacio2(FormContacto),
                Telefono = Vacio2(FormTelefono),
                Direccion = Vacio2(FormDireccion),
                Notas = Vacio2(FormNotas),
                Activo = true
            };
            await _repo.GuardarAsync(prov);
            EditorVisible = false;
            MensajeEstado = $"Proveedor «{prov.Nombre}» guardado.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo guardar: {ex.Message}"; }
    }

    [RelayCommand]
    private async Task EliminarProveedorAsync(ProveedorItem? item)
    {
        if (_repo is null || item is null) return;
        try
        {
            await _repo.DesactivarAsync(item.Id);
            MensajeEstado = $"Proveedor «{item.Nombre}» eliminado.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo eliminar: {ex.Message}"; }
    }

    private static string? Vacio2(string s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

/// <summary>Fila de la tabla de proveedores.</summary>
public sealed record ProveedorItem(Guid Id, string Nombre, string? Ruc, string? Contacto, string? Telefono, string? Notas);
