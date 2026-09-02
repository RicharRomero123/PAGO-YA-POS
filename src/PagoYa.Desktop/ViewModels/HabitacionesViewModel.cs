using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Administración del catálogo de habitaciones (rubro hotel/hostal): crear, editar
/// y eliminar cuartos, <b>agrupados por piso</b>. NO se alquila aquí — el alquiler
/// (check-in/out) se hace desde Cobrar (ver <see cref="RecepcionPosViewModel"/>).
/// </summary>
public partial class HabitacionesViewModel : ObservableObject
{
    private readonly IHotelRepository? _hotel;

    private readonly ObservableCollection<HabitacionCardVM> _habitaciones = new();

    /// <summary>Vista del catálogo agrupada por piso.</summary>
    public ICollectionView HabitacionesView { get; }

    public IReadOnlyList<string> TiposHabitacion { get; } =
        new[] { "Simple", "Doble", "Matrimonial", "Triple", "Suite", "Familiar" };

    /// <summary>Comodidades predefinidas (chips) que se marcan en el editor.</summary>
    public ObservableCollection<ComodidadOpcion> ComodidadesEditor { get; } = new();

    [ObservableProperty] private string _mensajeEstado = "";
    [ObservableProperty] private int _totalHabitaciones;

    // --- Editor ---
    [ObservableProperty] private bool _editorVisible;
    [ObservableProperty] private Guid _editandoId;
    private EstadoHabitacion _editandoEstado = EstadoHabitacion.Disponible;
    [ObservableProperty] private string _edNumero = "";
    [ObservableProperty] private int _edPiso = 1;
    [ObservableProperty] private int _edTipoIndex;
    [ObservableProperty] private decimal _edPrecioNoche;
    [ObservableProperty] private decimal _edPrecioHora;
    [ObservableProperty] private int _edCapacidad = 1;
    [ObservableProperty] private string _edNotas = "";
    [ObservableProperty] private string _tituloEditor = "Nueva habitación";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(EdTieneImagen))]
    private string? _edImagenRuta;

    public bool EdTieneImagen => !string.IsNullOrWhiteSpace(EdImagenRuta);

    /// <summary>Constructor de DISEÑO.</summary>
    public HabitacionesViewModel()
    {
        _habitaciones.Add(HabitacionCardVM.Mock("101", 1, "Simple", EstadoHabitacion.Disponible, 60, 20));
        _habitaciones.Add(HabitacionCardVM.Mock("102", 1, "Matrimonial", EstadoHabitacion.Ocupada, 80, 25, "Juan Pérez"));
        _habitaciones.Add(HabitacionCardVM.Mock("201", 2, "Suite", EstadoHabitacion.Disponible, 150, 0));
        HabitacionesView = CrearVistaAgrupada();
        TotalHabitaciones = _habitaciones.Count;
        CargarComodidades();
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public HabitacionesViewModel(IHotelRepository hotel)
    {
        _hotel = hotel;
        HabitacionesView = CrearVistaAgrupada();
        CargarComodidades();
    }

    private void CargarComodidades()
    {
        foreach (var c in HotelComodidades.Predefinidas)
            ComodidadesEditor.Add(new ComodidadOpcion(c));
    }

    /// <summary>Marca los chips según las comodidades ya guardadas (o las limpia).</summary>
    private void AplicarComodidades(IReadOnlyList<string> seleccionadas)
    {
        foreach (var c in ComodidadesEditor)
            c.Seleccionada = seleccionadas.Contains(c.Nombre);
    }

    private ICollectionView CrearVistaAgrupada()
    {
        var v = CollectionViewSource.GetDefaultView(_habitaciones);
        v.GroupDescriptions.Add(new PropertyGroupDescription(nameof(HabitacionCardVM.Piso)));
        v.SortDescriptions.Add(new SortDescription(nameof(HabitacionCardVM.Piso), ListSortDirection.Ascending));
        v.SortDescriptions.Add(new SortDescription(nameof(HabitacionCardVM.Numero), ListSortDirection.Ascending));
        return v;
    }

    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_hotel is null) return;
        _habitaciones.Clear();
        foreach (var h in await _hotel.ListarHabitacionesAsync(true, ct))
            _habitaciones.Add(HabitacionCardVM.Desde(h, null));
        TotalHabitaciones = _habitaciones.Count;
        HabitacionesView.Refresh();
    }

    [RelayCommand]
    private void NuevaHabitacion()
    {
        TituloEditor = "Nueva habitación";
        EditandoId = Guid.Empty;
        _editandoEstado = EstadoHabitacion.Disponible;
        EdNumero = ""; EdPiso = 1; EdTipoIndex = 0;
        EdPrecioNoche = 0; EdPrecioHora = 0; EdCapacidad = 1; EdNotas = "";
        EdImagenRuta = null;
        AplicarComodidades(Array.Empty<string>());
        EditorVisible = true;
    }

    [RelayCommand]
    private void EditarHabitacion(HabitacionCardVM? card)
    {
        if (card is null) return;
        TituloEditor = $"Editar habitación {card.Numero}";
        EditandoId = card.Id;
        _editandoEstado = card.Estado;
        EdNumero = card.Numero;
        EdPiso = card.Piso;
        EdTipoIndex = (int)card.Tipo;
        EdPrecioNoche = card.PrecioNoche;
        EdPrecioHora = card.PrecioHora;
        EdCapacidad = card.Capacidad;
        EdNotas = card.Notas ?? "";
        EdImagenRuta = card.ImagenRuta;
        AplicarComodidades(card.ComodidadesLista);
        EditorVisible = true;
    }

    [RelayCommand]
    private void CancelarEditor() => EditorVisible = false;

    /// <summary>Abre un selector de imagen y copia la foto elegida a la carpeta local del negocio.</summary>
    [RelayCommand]
    private void CargarFoto()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Elegir foto de la habitación",
            Filter = "Imágenes (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var carpeta = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PagoYa", "img");
            Directory.CreateDirectory(carpeta);
            var destino = Path.Combine(carpeta, $"hab_{Guid.NewGuid():N}{Path.GetExtension(dlg.FileName)}");
            File.Copy(dlg.FileName, destino, overwrite: true);
            EdImagenRuta = destino;
            MensajeEstado = "Foto cargada.";
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo cargar la foto: {ex.Message}"; }
    }

    [RelayCommand]
    private void QuitarFoto() => EdImagenRuta = null;

    [RelayCommand]
    private async Task GuardarHabitacion()
    {
        if (_hotel is null) { EditorVisible = false; return; }
        if (string.IsNullOrWhiteSpace(EdNumero)) { MensajeEstado = "El número de habitación es obligatorio."; return; }
        try
        {
            var hab = new Habitacion
            {
                Id = EditandoId == Guid.Empty ? Guid.NewGuid() : EditandoId,
                Numero = EdNumero.Trim(),
                Piso = EdPiso,
                Tipo = (TipoHabitacion)EdTipoIndex,
                PrecioNoche = EdPrecioNoche,
                PrecioHora = EdPrecioHora,
                Capacidad = EdCapacidad < 1 ? 1 : EdCapacidad,
                Estado = _editandoEstado,
                Notas = string.IsNullOrWhiteSpace(EdNotas) ? null : EdNotas.Trim(),
                ImagenRuta = EdImagenRuta,
                Comodidades = ComodidadesElegidas(),
                Activa = true
            };
            await _hotel.GuardarHabitacionAsync(hab);
            EditorVisible = false;
            MensajeEstado = $"Habitación {hab.Numero} guardada.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo guardar la habitación: {ex.Message}"; }
    }

    private string? ComodidadesElegidas()
    {
        var sel = ComodidadesEditor.Where(c => c.Seleccionada).Select(c => c.Nombre).ToArray();
        return sel.Length == 0 ? null : string.Join("|", sel);
    }

    [RelayCommand]
    private async Task EliminarHabitacion(HabitacionCardVM? card)
    {
        if (_hotel is null || card is null) return;
        if (card.Estado == EstadoHabitacion.Ocupada) { MensajeEstado = "No puedes eliminar una habitación ocupada."; return; }
        try
        {
            await _hotel.DesactivarHabitacionAsync(card.Id);
            MensajeEstado = $"Habitación {card.Numero} eliminada.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo eliminar: {ex.Message}"; }
    }
}

/// <summary>Tarjeta de una habitación (compartida por administración y recepción).</summary>
public partial class HabitacionCardVM : ObservableObject
{
    public Guid Id { get; init; }
    public string Numero { get; init; } = "";
    public int Piso { get; init; }
    public TipoHabitacion Tipo { get; init; }
    public string TipoTexto { get; init; } = "";
    public decimal PrecioNoche { get; init; }
    public decimal PrecioHora { get; init; }
    public int Capacidad { get; init; }
    public string? Notas { get; init; }
    public string? ImagenRuta { get; init; }
    public string? Comodidades { get; init; }
    public EstadoHabitacion Estado { get; init; }
    public string EstadoTexto { get; init; } = "";
    public string? HuespedNombre { get; init; }

    public bool TieneImagen => !string.IsNullOrWhiteSpace(ImagenRuta);
    public bool TienePrecioHora => PrecioHora > 0m;

    /// <summary>Comodidades como lista (para chips).</summary>
    public IReadOnlyList<string> ComodidadesLista =>
        string.IsNullOrWhiteSpace(Comodidades)
            ? Array.Empty<string>()
            : Comodidades.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    public bool TieneComodidades => ComodidadesLista.Count > 0;

    /// <summary>Comodidades en una línea (para el panel de alquiler).</summary>
    public string ComodidadesTexto => string.Join(" · ", ComodidadesLista);
    public string PrecioTexto => TienePrecioHora
        ? $"S/ {PrecioNoche:N0} noche · S/ {PrecioHora:N0} hora"
        : $"S/ {PrecioNoche:N0} noche";
    public string HuespedTexto => string.IsNullOrWhiteSpace(HuespedNombre) ? "" : HuespedNombre!;

    public static HabitacionCardVM Desde(Habitacion h, string? huesped) => new()
    {
        Id = h.Id, Numero = h.Numero, Piso = h.Piso, Tipo = h.Tipo,
        TipoTexto = h.Tipo.ToString(), PrecioNoche = h.PrecioNoche, PrecioHora = h.PrecioHora,
        Capacidad = h.Capacidad, Notas = h.Notas, ImagenRuta = h.ImagenRuta, Comodidades = h.Comodidades,
        Estado = h.Estado, EstadoTexto = TextoEstado(h.Estado), HuespedNombre = huesped
    };

    public static HabitacionCardVM Mock(string numero, int piso, string tipo, EstadoHabitacion estado,
        decimal noche, decimal hora, string? huesped = null) => new()
    {
        Id = Guid.NewGuid(), Numero = numero, Piso = piso, TipoTexto = tipo,
        PrecioNoche = noche, PrecioHora = hora, Capacidad = 2, Estado = estado,
        EstadoTexto = TextoEstado(estado), HuespedNombre = huesped
    };

    private static string TextoEstado(EstadoHabitacion e) => e switch
    {
        EstadoHabitacion.Disponible => "Disponible",
        EstadoHabitacion.Ocupada => "Ocupada",
        EstadoHabitacion.Limpieza => "Limpieza",
        EstadoHabitacion.Mantenimiento => "Mantenimiento",
        EstadoHabitacion.Reservada => "Reservada",
        _ => ""
    };
}

/// <summary>Línea de consumo mostrada en la cuenta de la habitación.</summary>
public sealed record ConsumoLineaVM(Guid Id, string Descripcion, decimal Cantidad, decimal PrecioUnitario, decimal Importe)
{
    public string CantidadTexto => Cantidad == Math.Truncate(Cantidad) ? ((long)Cantidad).ToString() : Cantidad.ToString("0.###");
}

/// <summary>Opción de producto para cargar como consumo a la habitación.</summary>
public sealed record ProductoConsumoOpcion(Guid Id, string Nombre, decimal Precio)
{
    public string NombreConPrecio => $"{Nombre}  —  S/ {Precio:N2}";
}

/// <summary>Chip de comodidad seleccionable en el editor de habitación.</summary>
public partial class ComodidadOpcion : ObservableObject
{
    public ComodidadOpcion(string nombre) => Nombre = nombre;
    public string Nombre { get; }
    [ObservableProperty] private bool _seleccionada;
}
