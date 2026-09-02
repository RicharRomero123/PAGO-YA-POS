using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Desktop.Servicios;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Módulo de <b>Vencimientos</b> (rubro farmacia/botica): panel de control de
/// medicamentos vencidos, próximos a vencer y con stock bajo para reposición.
///
/// Clasifica el catálogo en secciones (vencidos / ≤30 d / ≤60 d / stock bajo) con
/// contadores para badges, y permite avisar al proveedor por WhatsApp para reponer.
///
/// Runtime: usa <see cref="IProductoRepository"/> + <see cref="IProveedorRepository"/>.
/// Diseño: el constructor sin parámetros siembra mock para el diseñador.
/// </summary>
public partial class VencimientosViewModel : ObservableObject
{
    private readonly IProductoRepository? _productos;
    private readonly IProveedorRepository? _proveedores;
    private readonly IConfiguracionStore? _config;
    private readonly string _nombreNegocio;

    /// <summary>Vencidos (no deben venderse; retirar del anaquel).</summary>
    public ObservableCollection<VencimientoItemVM> Vencidos { get; } = new();

    /// <summary>Por vencer dentro de 30 días (aún vendibles; priorizar rotación).</summary>
    public ObservableCollection<VencimientoItemVM> PorVencer30 { get; } = new();

    /// <summary>Por vencer entre 31 y 60 días (vigilar).</summary>
    public ObservableCollection<VencimientoItemVM> PorVencer60 { get; } = new();

    /// <summary>Stock bajo / reposición (independiente del vencimiento).</summary>
    public ObservableCollection<VencimientoItemVM> Reposicion { get; } = new();

    // Contadores para los badges de cada sección.
    [ObservableProperty] private int _totalVencidos;
    [ObservableProperty] private int _totalPorVencer30;
    [ObservableProperty] private int _totalPorVencer60;
    [ObservableProperty] private int _totalReposicion;

    /// <summary>True si no hay ninguna alerta (todo en orden).</summary>
    [ObservableProperty] private bool _sinAlertas;

    [ObservableProperty] private string _mensajeEstado = "";

    /// <summary>Constructor de DISEÑO: siembra mock. No toca BD.</summary>
    public VencimientosViewModel()
    {
        _nombreNegocio = "Botica";
        Vencidos.Add(VencimientoItemVM.Mock("Ibuprofeno 400mg", "Analgésicos", -3, 40, 5, "Lote A12", "Droguería Sur"));
        PorVencer30.Add(VencimientoItemVM.Mock("Paracetamol 500mg", "Analgésicos", 18, 12, 12, "Lote P08", "Distribuidora Central"));
        PorVencer30.Add(VencimientoItemVM.Mock("Loratadina 10mg", "Antialérgicos", 27, 4, 10, "Lote L33", null));
        PorVencer60.Add(VencimientoItemVM.Mock("Amoxicilina 500mg", "Antibióticos", 52, 30, 12, "Lote M77", "Droguería Sur"));
        Reposicion.Add(VencimientoItemVM.Mock("Vitamina C 1g", "Suplementos", 200, 3, 8, null, "Distribuidora Central"));
        RecalcularContadores();
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public VencimientosViewModel(IProductoRepository productos, IProveedorRepository proveedores, IConfiguracionStore config)
    {
        _productos = productos;
        _proveedores = proveedores;
        _config = config;
        var nombre = config.Leer()?.NombreNegocio;
        _nombreNegocio = string.IsNullOrWhiteSpace(nombre) ? "Botica" : nombre!;
    }

    /// <summary>
    /// Lee todos los productos, resuelve su proveedor y los clasifica por estado de
    /// vencimiento / stock. Ordena por días para vencer ascendente (lo más urgente arriba).
    /// </summary>
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_productos is null) return;

        // Mapa id→proveedor para resolver nombre/teléfono sin N consultas.
        var proveedores = _proveedores is null
            ? new Dictionary<Guid, Proveedor>()
            : (await _proveedores.ListarAsync(false, ct)).ToDictionary(p => p.Id, p => p);

        var lista = await _productos.BuscarAsync(null, ct);

        Vencidos.Clear();
        PorVencer30.Clear();
        PorVencer60.Clear();
        Reposicion.Clear();

        // Ordenar por urgencia (días para vencer ascendente; sin fecha al final).
        foreach (var p in lista.OrderBy(p => p.DiasParaVencer ?? int.MaxValue))
        {
            Proveedor? prov = p.ProveedorId is { } pid && proveedores.TryGetValue(pid, out var pr) ? pr : null;
            var item = VencimientoItemVM.Desde(p, prov);

            if (p.EstaVencido) Vencidos.Add(item);
            else if (p.PorVencer(30)) PorVencer30.Add(item);
            else if (p.DiasParaVencer is >= 31 and <= 60) PorVencer60.Add(item);

            // Stock bajo es una sección independiente (un producto puede estar por vencer Y con stock bajo).
            if (p.StockBajo) Reposicion.Add(item);
        }

        RecalcularContadores();
    }

    private void RecalcularContadores()
    {
        TotalVencidos = Vencidos.Count;
        TotalPorVencer30 = PorVencer30.Count;
        TotalPorVencer60 = PorVencer60.Count;
        TotalReposicion = Reposicion.Count;
        SinAlertas = TotalVencidos == 0 && TotalPorVencer30 == 0 && TotalPorVencer60 == 0 && TotalReposicion == 0;
    }

    /// <summary>
    /// Abre WhatsApp (wa.me) con un mensaje pre-armado para pedir reposición al
    /// proveedor del producto. Perú: prefijo país 51. Si el proveedor no tiene
    /// teléfono, avisa por estado.
    /// </summary>
    [RelayCommand]
    private void AvisarProveedor(VencimientoItemVM? item)
    {
        if (item is null) return;
        if (string.IsNullOrWhiteSpace(item.ProveedorTelefono))
        {
            MensajeEstado = string.IsNullOrWhiteSpace(item.ProveedorNombre)
                ? $"«{item.Nombre}» no tiene proveedor asignado. Asígnalo en Inventario."
                : $"El proveedor «{item.ProveedorNombre}» no tiene teléfono/WhatsApp registrado.";
            return;
        }

        try
        {
            var telefono = SoloDigitos(item.ProveedorTelefono!);
            // Si el número no trae código de país (9 dígitos móvil Perú), anteponer 51.
            if (telefono.Length == 9) telefono = "51" + telefono;

            var mensaje = ArmarMensaje(item);
            var url = $"https://wa.me/{telefono}?text={Uri.EscapeDataString(mensaje)}";
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
            MensajeEstado = $"Abriendo WhatsApp para {item.ProveedorNombre}…";
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo abrir WhatsApp: {ex.Message}";
        }
    }

    /// <summary>Arma el mensaje de reposición sugerido para el proveedor.</summary>
    private string ArmarMensaje(VencimientoItemVM item)
    {
        var sb = new StringBuilder();
        sb.Append($"Hola {item.ProveedorNombre}, soy de {_nombreNegocio}. ");
        sb.Append($"Necesito reponer {item.Nombre}");
        if (!string.IsNullOrWhiteSpace(item.Lote)) sb.Append($" (lote {item.Lote}");
        if (item.TieneVencimiento)
            sb.Append(string.IsNullOrWhiteSpace(item.Lote)
                ? $" (vence {item.FechaVencimientoTexto}"
                : $", vence {item.FechaVencimientoTexto}");
        if (!string.IsNullOrWhiteSpace(item.Lote) || item.TieneVencimiento) sb.Append(')');
        sb.Append(". ¿Disponibilidad y precio?");
        return sb.ToString();
    }

    private static string SoloDigitos(string s)
    {
        var sb = new StringBuilder();
        foreach (var c in s) if (char.IsDigit(c)) sb.Append(c);
        return sb.ToString();
    }
}

/// <summary>Fila del panel de vencimientos/reposición (respaldada por un producto real).</summary>
public sealed class VencimientoItemVM
{
    public Guid Id { get; init; }
    public string Nombre { get; init; } = "";
    public string Categoria { get; init; } = "";
    public decimal Stock { get; init; }
    public decimal StockMinimo { get; init; }
    public DateTime? FechaVencimiento { get; init; }
    public int? DiasParaVencer { get; init; }
    public string? Lote { get; init; }
    public string? ProveedorNombre { get; init; }
    public string? ProveedorTelefono { get; init; }

    public bool TieneVencimiento => FechaVencimiento is not null;
    public string FechaVencimientoTexto => FechaVencimiento?.ToString("dd/MM/yyyy") ?? "—";

    public string StockTexto => FormatoNum(Stock);
    public string ProveedorTexto => string.IsNullOrWhiteSpace(ProveedorNombre) ? "Sin proveedor" : ProveedorNombre!;
    public bool TieneProveedorConTelefono => !string.IsNullOrWhiteSpace(ProveedorTelefono);
    public string LoteTexto => string.IsNullOrWhiteSpace(Lote) ? "" : $"Lote {Lote}";
    public bool TieneLote => !string.IsNullOrWhiteSpace(Lote);

    /// <summary>Texto del estado temporal: "Venció hace N d" / "Vence en N d" / "Sin fecha".</summary>
    public string DiasTexto => DiasParaVencer switch
    {
        null => "Sin fecha de vencimiento",
        < 0 => $"Venció hace {-DiasParaVencer.Value} d",
        0 => "Vence hoy",
        _ => $"Vence en {DiasParaVencer.Value} d"
    };

    private static string FormatoNum(decimal s) =>
        s == Math.Truncate(s) ? ((long)s).ToString() : s.ToString("0.###");

    public static VencimientoItemVM Desde(Producto p, Proveedor? prov) => new()
    {
        Id = p.Id,
        Nombre = p.Nombre,
        Categoria = string.IsNullOrWhiteSpace(p.Descripcion) ? "General" : p.Descripcion!,
        Stock = p.StockActual,
        StockMinimo = p.StockMinimo,
        FechaVencimiento = p.FechaVencimiento,
        DiasParaVencer = p.DiasParaVencer,
        Lote = p.Lote,
        ProveedorNombre = prov?.Nombre,
        ProveedorTelefono = prov?.Telefono
    };

    public static VencimientoItemVM Mock(string nombre, string categoria, int dias, decimal stock, decimal minimo,
        string? lote, string? proveedor) => new()
    {
        Id = Guid.NewGuid(),
        Nombre = nombre,
        Categoria = categoria,
        Stock = stock,
        StockMinimo = minimo,
        FechaVencimiento = DateTime.Today.AddDays(dias),
        DiasParaVencer = dias,
        Lote = lote,
        ProveedorNombre = proveedor,
        ProveedorTelefono = proveedor is null ? null : "987654321"
    };
}
