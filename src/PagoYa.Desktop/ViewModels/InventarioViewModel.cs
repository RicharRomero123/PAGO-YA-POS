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
/// Gestión de productos / inventario. CRUD real contra
/// <see cref="IProductoRepository"/>.
///
/// Runtime: carga los productos desde BD y permite crear/editar/desactivar y
/// ajustar stock. Diseño: el constructor sin parámetros siembra mock para el
/// render en modo diseñador (d:DataContext).
/// </summary>
public partial class InventarioViewModel : ObservableObject
{
    private readonly IProductoRepository? _repo;
    private readonly IProveedorRepository? _proveedores;
    private readonly IConfiguracionStore? _config;
    private readonly Dictionary<Guid, string> _nombreProveedor = new();
    private readonly ObservableCollection<ProductoInventarioItem> _items = new();
    public ICollectionView ItemsView { get; }

    /// <summary>Opciones de proveedor para el selector del formulario (incluye "Sin proveedor").</summary>
    public ObservableCollection<ProveedorOpcion> ProveedoresOpciones { get; } = new();

    /// <summary>Categorías sugeridas según el rubro del negocio (autocompletar el campo Categoría).</summary>
    public ObservableCollection<string> CategoriasSugeridas { get; } = new();

    [ObservableProperty] private Guid? _formProveedorId;

    [ObservableProperty] private string _textoBusqueda = "";
    [ObservableProperty] private string _mensajeEstado = "";

    // --- Formulario de alta/edición ---
    [ObservableProperty] private bool _editorVisible;
    [ObservableProperty] private Guid _editandoId;
    [ObservableProperty] private string _formCodigo = "";
    [ObservableProperty] private string _formNombre = "";
    [ObservableProperty] private string _formCategoria = "General";

    /// <summary>Texto para crear una categoría nueva (campo aparte del selector).</summary>
    [ObservableProperty] private string _nuevaCategoria = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FormPreviewDescuento))]
    private decimal _formPrecio;

    [ObservableProperty] private decimal _formStock;
    [ObservableProperty] private decimal _formStockMinimo;

    // --- Campos farmacéuticos (solo visibles/relevantes cuando EsFarmacia) ---
    [ObservableProperty] private DateTime? _formFechaVencimiento;
    [ObservableProperty] private string _formLote = "";
    [ObservableProperty] private string _formRegistroSanitario = "";
    [ObservableProperty] private string _formPrincipioActivo = "";
    [ObservableProperty] private bool _formRequiereReceta;

    /// <summary>True si el negocio es farmacia/botica: habilita la sección farmacéutica del editor y los badges de vencimiento.</summary>
    public bool EsFarmacia { get; }

    /// <summary>True si el rubro es de comida (restaurante/pollería/cafetería): habilita la sección de personalización/modificadores.</summary>
    public bool EsComida { get; }

    /// <summary>Grupos de modificadores editables del producto en edición (presentaciones, agregados, quitar…).</summary>
    public ObservableCollection<GrupoModificadorEditVM> Grupos { get; } = new();

    // --- Descuento del producto (0 = sin descuento, 1 = %, 2 = precio de oferta) ---
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FormDescuentoTieneValor))]
    [NotifyPropertyChangedFor(nameof(FormDescuentoEtiqueta))]
    [NotifyPropertyChangedFor(nameof(FormPreviewDescuento))]
    private int _formDescuentoModo;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FormPreviewDescuento))]
    private decimal _formDescuentoValor;

    /// <summary>True si el modo elegido requiere capturar un valor (% u oferta).</summary>
    public bool FormDescuentoTieneValor => FormDescuentoModo != 0;

    /// <summary>Etiqueta del campo de valor según el modo elegido.</summary>
    public string FormDescuentoEtiqueta => FormDescuentoModo == 1 ? "% de descuento" : "Precio de oferta (S/)";

    /// <summary>Vista previa en vivo del precio final que se cobrará (o aviso si el valor no aplica).</summary>
    public string FormPreviewDescuento
    {
        get
        {
            if (FormDescuentoModo == 0) return "";
            var tmp = new Producto
            {
                PrecioVenta = FormPrecio,
                TipoDescuento = (TipoDescuento)FormDescuentoModo,
                DescuentoValor = FormDescuentoValor
            };
            return tmp.TieneDescuento
                ? $"Se venderá a S/ {tmp.PrecioFinal:N2}  (-{tmp.PorcentajeDescuento}%)"
                : "El valor no genera descuento (revísalo).";
        }
    }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FormTieneImagen))]
    private string? _formImagenRuta;

    public bool FormTieneImagen => !string.IsNullOrWhiteSpace(FormImagenRuta);

    /// <summary>Constructor de DISEÑO: siembra mock. No toca BD.</summary>
    public InventarioViewModel()
    {
        void Add(string cod, string nombre, string cat, decimal precio, int stock, int minimo,
            DateTime? vence = null, string? principio = null, bool receta = false)
            => _items.Add(new ProductoInventarioItem(Guid.NewGuid(), cod, nombre, cat, precio, stock, minimo, null,
                fechaVencimiento: vence, principioActivo: principio, requiereReceta: receta));

        Add("7501055", "Paracetamol 500mg", "Analgésicos", 0.50m, 48, 12, DateTime.Today.AddDays(18), "Paracetamol");
        Add("7501056", "Amoxicilina 500mg", "Antibióticos", 1.20m, 6, 12, DateTime.Today.AddDays(120), "Amoxicilina", receta: true);
        Add("7502001", "Ibuprofeno 400mg", "Analgésicos", 0.80m, 30, 10, DateTime.Today.AddDays(-3), "Ibuprofeno");
        Add("7502002", "Vitamina C 1g", "Suplementos", 0.90m, 3, 8, DateTime.Today.AddDays(200));
        Add("7501099", "Sal de Andrews", "Digestivos", 1.50m, 0, 24);

        ItemsView = CollectionViewSource.GetDefaultView(_items);
        ItemsView.Filter = FiltroFila;
        EsFarmacia = true; // en diseño mostramos la sección farmacéutica para poder previsualizarla
        EsComida = true;    // en diseño mostramos la sección de personalización para poder previsualizarla
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public InventarioViewModel(IProductoRepository repo, IProveedorRepository proveedores, IConfiguracionStore config)
    {
        _repo = repo;
        _proveedores = proveedores;
        _config = config;
        EsFarmacia = string.Equals(config.Leer()?.Rubro, "farmacia", StringComparison.OrdinalIgnoreCase);
        EsComida = PlantillasRubro.EsRubroComida(config.Leer()?.Rubro);
        ItemsView = CollectionViewSource.GetDefaultView(_items);
        ItemsView.Filter = FiltroFila;
    }

    /// <summary>Carga proveedores (para el selector y resolver nombres) y luego los productos.</summary>
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_repo is null) return;

        // 0) Categorías del selector: las sugeridas por el rubro (por defecto) +
        //    las personalizadas que el dueño haya creado (persistidas en config).
        if (CategoriasSugeridas.Count == 0)
        {
            var cfg = _config?.Leer();
            var rubro = cfg?.Rubro ?? "bodega";
            foreach (var c in PlantillasRubro.Categorias(rubro)) AgregarASugeridas(c);
            if (cfg?.CategoriasPersonalizadas is { } personalizadas)
                foreach (var c in personalizadas) AgregarASugeridas(c);
        }

        // 1) Proveedores: opciones del selector + mapa id→nombre.
        _nombreProveedor.Clear();
        ProveedoresOpciones.Clear();
        ProveedoresOpciones.Add(new ProveedorOpcion(null, "(Sin proveedor)"));
        if (_proveedores is not null)
        {
            foreach (var pr in await _proveedores.ListarAsync(true, ct))
            {
                _nombreProveedor[pr.Id] = pr.Nombre;
                ProveedoresOpciones.Add(new ProveedorOpcion(pr.Id, pr.Nombre));
            }
        }

        // 2) Productos, resolviendo el nombre del proveedor.
        var lista = await _repo.BuscarAsync(null, ct);
        _items.Clear();
        foreach (var p in lista)
        {
            var nombreProv = p.ProveedorId is { } pid && _nombreProveedor.TryGetValue(pid, out var n) ? n : null;
            _items.Add(ProductoInventarioItem.Desde(p, nombreProv));
        }
        ItemsView.Refresh();
    }

    private bool FiltroFila(object o)
        => o is ProductoInventarioItem p
           && (string.IsNullOrWhiteSpace(TextoBusqueda)
               || p.Nombre.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase)
               || p.Codigo.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase));

    partial void OnTextoBusquedaChanged(string value) => ItemsView.Refresh();

    // ------------------------------------------------------------------
    // Comandos CRUD
    // ------------------------------------------------------------------

    [RelayCommand]
    private void NuevoProducto()
    {
        EditandoId = Guid.Empty;
        FormCodigo = "";
        FormNombre = "";
        FormCategoria = "General";
        FormPrecio = 0m;
        FormStock = 0m;
        FormStockMinimo = 0m;
        FormFechaVencimiento = null;
        FormLote = "";
        FormRegistroSanitario = "";
        FormPrincipioActivo = "";
        FormRequiereReceta = false;
        FormImagenRuta = null;
        FormProveedorId = null;
        FormDescuentoModo = 0;
        FormDescuentoValor = 0m;
        Grupos.Clear();
        EditorVisible = true;
    }

    [RelayCommand]
    private void EditarProducto(ProductoInventarioItem? item)
    {
        if (item is null) return;
        EditandoId = item.Id;
        FormCodigo = item.Codigo;
        FormNombre = item.Nombre;
        FormCategoria = item.Categoria;
        FormPrecio = item.Precio;
        FormStock = item.Stock;
        FormStockMinimo = item.StockMinimo;
        FormFechaVencimiento = item.FechaVencimiento;
        FormLote = item.Lote ?? "";
        FormRegistroSanitario = item.RegistroSanitario ?? "";
        FormPrincipioActivo = item.PrincipioActivo ?? "";
        FormRequiereReceta = item.RequiereReceta;
        FormImagenRuta = item.ImagenRuta;
        FormProveedorId = item.ProveedorId;
        FormDescuentoModo = item.TipoDescuentoInt;
        FormDescuentoValor = item.DescuentoValor;

        // Personalización (rubro comida): deserializa y llena los grupos/opciones editables.
        Grupos.Clear();
        var pers = PersonalizacionSerializer.Deserializar(item.PersonalizacionJson);
        foreach (var g in pers.Grupos)
        {
            var gvm = new GrupoModificadorEditVM
            {
                Nombre = g.Nombre,
                Multiple = g.Multiple,
                Obligatorio = g.Obligatorio
            };
            foreach (var o in g.Opciones)
                gvm.Opciones.Add(new OpcionModificadorEditVM { Nombre = o.Nombre, PrecioExtra = o.PrecioExtra });
            Grupos.Add(gvm);
        }

        EditorVisible = true;
    }

    [RelayCommand]
    private void CancelarEdicion() => EditorVisible = false;

    // ------------------------------------------------------------------
    // Personalización / modificadores (rubro comida): editar grupos y opciones
    // ------------------------------------------------------------------

    [RelayCommand]
    private void AgregarGrupo() => Grupos.Add(new GrupoModificadorEditVM());

    [RelayCommand]
    private void EliminarGrupo(GrupoModificadorEditVM? grupo)
    {
        if (grupo is not null) Grupos.Remove(grupo);
    }

    [RelayCommand]
    private void AgregarOpcion(GrupoModificadorEditVM? grupo)
        => grupo?.Opciones.Add(new OpcionModificadorEditVM());

    [RelayCommand]
    private void EliminarOpcion(OpcionModificadorEditVM? opcion)
    {
        if (opcion is null) return;
        foreach (var g in Grupos)
            if (g.Opciones.Remove(opcion)) return;
    }

    /// <summary>Construye el <see cref="PersonalizacionProducto"/> desde los VMs editables (filtra vacíos).</summary>
    private PersonalizacionProducto ConstruirPersonalizacion()
    {
        var pers = new PersonalizacionProducto { PermiteNota = true };
        foreach (var g in Grupos)
        {
            var nombreGrupo = g.Nombre?.Trim();
            if (string.IsNullOrWhiteSpace(nombreGrupo)) continue;

            var grupo = new GrupoModificador
            {
                Nombre = nombreGrupo,
                Multiple = g.Multiple,
                Obligatorio = g.Obligatorio
            };
            foreach (var o in g.Opciones)
            {
                var nombreOpc = o.Nombre?.Trim();
                if (string.IsNullOrWhiteSpace(nombreOpc)) continue;
                grupo.Opciones.Add(new OpcionModificador { Nombre = nombreOpc, PrecioExtra = o.PrecioExtra });
            }
            if (grupo.Opciones.Count > 0) pers.Grupos.Add(grupo);
        }
        return pers;
    }

    // ------------------------------------------------------------------
    // Categorías: el rubro trae unas por defecto, pero el dueño puede crear
    // las suyas. Se persisten en la config para reaparecer en cada arranque.
    // ------------------------------------------------------------------

    /// <summary>Agrega una categoría a la lista del selector si aún no está (case-insensitive).</summary>
    private void AgregarASugeridas(string categoria)
    {
        var cat = categoria?.Trim();
        if (string.IsNullOrWhiteSpace(cat)) return;
        if (!CategoriasSugeridas.Any(c => string.Equals(c, cat, StringComparison.OrdinalIgnoreCase)))
            CategoriasSugeridas.Add(cat);
    }

    /// <summary>
    /// Registra una categoría como propia del negocio: la agrega al selector y la
    /// persiste en la config (idempotente). Devuelve true si era nueva.
    /// </summary>
    private bool RegistrarCategoria(string categoria)
    {
        var cat = categoria?.Trim();
        if (string.IsNullOrWhiteSpace(cat)) return false;

        bool eraNueva = !CategoriasSugeridas.Any(c => string.Equals(c, cat, StringComparison.OrdinalIgnoreCase));
        AgregarASugeridas(cat);

        if (_config is not null)
        {
            var cfg = _config.Leer() ?? new ConfiguracionNegocio();
            if (!cfg.CategoriasPersonalizadas.Any(c => string.Equals(c, cat, StringComparison.OrdinalIgnoreCase)))
            {
                cfg.CategoriasPersonalizadas.Add(cat);
                _config.Guardar(cfg);
            }
        }
        return eraNueva;
    }

    /// <summary>
    /// Crea la categoría escrita en <see cref="NuevaCategoria"/> (o, si está vacía,
    /// la del selector) y la deja seleccionada en el formulario.
    /// </summary>
    [RelayCommand]
    private void AgregarCategoria()
    {
        var cat = (string.IsNullOrWhiteSpace(NuevaCategoria) ? FormCategoria : NuevaCategoria)?.Trim();
        if (string.IsNullOrWhiteSpace(cat))
        {
            MensajeEstado = "Escribe el nombre de la categoría a crear.";
            return;
        }
        bool eraNueva = RegistrarCategoria(cat);
        FormCategoria = cat;
        NuevaCategoria = "";
        MensajeEstado = eraNueva ? $"Categoría «{cat}» creada." : $"«{cat}» ya existía; seleccionada.";
    }

    /// <summary>Abre un selector de imagen y copia la foto elegida a la carpeta local del negocio.</summary>
    [RelayCommand]
    private void CargarFoto()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Elegir foto del producto",
            Filter = "Imágenes (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp"
        };
        if (dlg.ShowDialog() != true) return;

        try
        {
            var carpeta = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PagoYa", "img");
            Directory.CreateDirectory(carpeta);
            var ext = Path.GetExtension(dlg.FileName);
            var destino = Path.Combine(carpeta, $"{Guid.NewGuid():N}{ext}");
            File.Copy(dlg.FileName, destino, overwrite: true);
            FormImagenRuta = destino;
            MensajeEstado = "Foto cargada.";
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo cargar la foto: {ex.Message}";
        }
    }

    [RelayCommand]
    private void QuitarFoto() => FormImagenRuta = null;

    [RelayCommand]
    private async Task GuardarProductoAsync()
    {
        if (_repo is null) { EditorVisible = false; return; }
        if (string.IsNullOrWhiteSpace(FormNombre) || string.IsNullOrWhiteSpace(FormCodigo))
        {
            MensajeEstado = "Código y nombre son obligatorios.";
            return;
        }

        try
        {
            var producto = new Producto
            {
                Id = EditandoId == Guid.Empty ? Guid.NewGuid() : EditandoId,
                Codigo = FormCodigo.Trim(),
                Nombre = FormNombre.Trim(),
                Descripcion = FormCategoria.Trim(),   // categoría reutiliza 'descripcion'
                PrecioVenta = FormPrecio,
                PrecioIncluyeIgv = true,
                UnidadMedida = "NIU",
                StockActual = FormStock,
                StockMinimo = FormStockMinimo,
                ControlaStock = true,
                Activo = true,
                // Campos farmacéuticos: solo se persisten para el rubro farmacia
                // (en otros rubros quedan null/false y no cambian nada visible).
                FechaVencimiento = EsFarmacia ? FormFechaVencimiento : null,
                Lote = EsFarmacia && !string.IsNullOrWhiteSpace(FormLote) ? FormLote.Trim() : null,
                RegistroSanitario = EsFarmacia && !string.IsNullOrWhiteSpace(FormRegistroSanitario) ? FormRegistroSanitario.Trim() : null,
                PrincipioActivo = EsFarmacia && !string.IsNullOrWhiteSpace(FormPrincipioActivo) ? FormPrincipioActivo.Trim() : null,
                RequiereReceta = EsFarmacia && FormRequiereReceta,
                ImagenRuta = FormImagenRuta,
                ProveedorId = FormProveedorId,
                TipoDescuento = (TipoDescuento)FormDescuentoModo,
                DescuentoValor = FormDescuentoModo == 0 ? 0m : FormDescuentoValor,
                // Personalización (rubro comida): solo se persiste si el rubro es de comida.
                // En otros rubros queda null (producto simple) sin importar lo que haya en memoria.
                PersonalizacionJson = EsComida
                    ? PersonalizacionSerializer.Serializar(ConstruirPersonalizacion())
                    : null
            };
            // La categoría del producto (aunque se haya escrito al vuelo en el
            // selector) queda registrada como propia del negocio para reutilizarla.
            RegistrarCategoria(producto.Descripcion);

            await _repo.GuardarAsync(producto);
            EditorVisible = false;
            MensajeEstado = $"Producto '{producto.Nombre}' guardado.";
            await CargarAsync();
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo guardar: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task DesactivarProductoAsync(ProductoInventarioItem? item)
    {
        if (_repo is null || item is null) return;
        try
        {
            await _repo.DesactivarAsync(item.Id);
            MensajeEstado = $"Producto '{item.Nombre}' desactivado.";
            await CargarAsync();
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo desactivar: {ex.Message}";
        }
    }
}

/// <summary>Fila de la tabla de inventario (respaldada por una entidad real).</summary>
public sealed class ProductoInventarioItem
{
    public ProductoInventarioItem(Guid id, string codigo, string nombre, string categoria,
        decimal precio, decimal stock, decimal stockMinimo, string? imagenRuta,
        Guid? proveedorId = null, string? proveedorNombre = null,
        int tipoDescuentoInt = 0, decimal descuentoValor = 0m,
        DateTime? fechaVencimiento = null, string? lote = null, string? registroSanitario = null,
        string? principioActivo = null, bool requiereReceta = false,
        string? personalizacionJson = null)
    {
        Id = id; Codigo = codigo; Nombre = nombre; Categoria = categoria;
        Precio = precio; Stock = stock; StockMinimo = stockMinimo; ImagenRuta = imagenRuta;
        ProveedorId = proveedorId; ProveedorNombre = proveedorNombre;
        TipoDescuentoInt = tipoDescuentoInt; DescuentoValor = descuentoValor;
        FechaVencimiento = fechaVencimiento; Lote = lote; RegistroSanitario = registroSanitario;
        PrincipioActivo = principioActivo; RequiereReceta = requiereReceta;
        PersonalizacionJson = personalizacionJson;
    }

    public Guid Id { get; }
    public string Codigo { get; }
    public string Nombre { get; }
    public string Categoria { get; }

    /// <summary>Precio normal (de lista) del producto.</summary>
    public decimal Precio { get; }
    public decimal Stock { get; }
    public decimal StockMinimo { get; }
    public string? ImagenRuta { get; }
    public Guid? ProveedorId { get; }
    public string? ProveedorNombre { get; }

    /// <summary>Tipo de descuento como entero (0 ninguno / 1 % / 2 oferta).</summary>
    public int TipoDescuentoInt { get; }

    /// <summary>Valor del descuento (% u oferta según el tipo).</summary>
    public decimal DescuentoValor { get; }

    // Reutiliza la lógica de la entidad para no duplicar el cálculo del precio final.
    private Producto Calc => new()
    {
        PrecioVenta = Precio,
        TipoDescuento = (Core.Enums.TipoDescuento)TipoDescuentoInt,
        DescuentoValor = DescuentoValor
    };

    /// <summary>True si el producto está en oferta.</summary>
    public bool TieneDescuento => Calc.TieneDescuento;

    /// <summary>Precio efectivo al que se cobra (con descuento aplicado).</summary>
    public decimal PrecioFinal => Calc.PrecioFinal;

    /// <summary>Badge de oferta ("-15%" o "OFERTA"); vacío si no hay descuento.</summary>
    public string EtiquetaDescuento =>
        !TieneDescuento ? "" : Calc.PorcentajeDescuento > 0 ? $"-{Calc.PorcentajeDescuento}%" : "OFERTA";

    public string ProveedorTexto => string.IsNullOrWhiteSpace(ProveedorNombre) ? "—" : ProveedorNombre!;
    public bool TieneImagen => !string.IsNullOrWhiteSpace(ImagenRuta);
    public bool StockBajo => Stock > 0 && StockMinimo > 0 && Stock <= StockMinimo;
    public bool SinStock => Stock == 0;
    public bool EsOk => !SinStock && !StockBajo;
    public string EstadoStock => SinStock ? "Sin stock" : StockBajo ? "Stock bajo" : "OK";

    // --- Campos farmacéuticos (rubro farmacia) ---
    public DateTime? FechaVencimiento { get; }
    public string? Lote { get; }
    public string? RegistroSanitario { get; }
    public string? PrincipioActivo { get; }
    public bool RequiereReceta { get; }

    /// <summary>JSON de personalización (rubro comida); null/vacío = producto simple.</summary>
    public string? PersonalizacionJson { get; }

    /// <summary>Días para vencer (negativo si venció); null si no tiene fecha. Reutiliza la lógica de la entidad.</summary>
    private Producto CalcVenc => new() { FechaVencimiento = FechaVencimiento };
    public bool TieneVencimiento => FechaVencimiento is not null;
    public bool EstaVencido => CalcVenc.EstaVencido;
    public bool PorVencer => CalcVenc.PorVencer(30);
    public int? DiasParaVencer => CalcVenc.DiasParaVencer;

    /// <summary>Texto corto del badge de vencimiento ("VENCIDO" / "Vence en 12 d"); vacío si está OK o sin fecha.</summary>
    public string EtiquetaVencimiento =>
        !TieneVencimiento ? "" : EstaVencido ? "VENCIDO" : PorVencer ? $"Vence en {DiasParaVencer} d" : "";

    /// <summary>True si hay que mostrar el badge de alerta de vencimiento (vencido o por vencer ≤30 d).</summary>
    public bool AlertaVencimiento => EstaVencido || PorVencer;

    /// <summary>Fecha de vencimiento formateada (dd/MM/yyyy) o vacío.</summary>
    public string FechaVencimientoTexto => FechaVencimiento?.ToString("dd/MM/yyyy") ?? "";

    /// <summary>
    /// Mapea desde una entidad, incluyendo StockMinimo real y los campos farmacéuticos.
    /// </summary>
    public static ProductoInventarioItem Desde(Producto p, string? proveedorNombre = null) => new(
        p.Id, p.Codigo, p.Nombre,
        string.IsNullOrWhiteSpace(p.Descripcion) ? "General" : p.Descripcion!,
        p.PrecioVenta, p.StockActual, p.StockMinimo, p.ImagenRuta, p.ProveedorId, proveedorNombre,
        (int)p.TipoDescuento, p.DescuentoValor,
        p.FechaVencimiento, p.Lote, p.RegistroSanitario, p.PrincipioActivo, p.RequiereReceta,
        p.PersonalizacionJson);
}

/// <summary>Opción del selector de proveedor (Id null = "Sin proveedor").</summary>
public sealed record ProveedorOpcion(Guid? Id, string Nombre);

/// <summary>
/// VM editable de un grupo de modificadores en el editor de inventario (rubro comida).
/// Se traduce a <see cref="GrupoModificador"/> al guardar.
/// </summary>
public partial class GrupoModificadorEditVM : ObservableObject
{
    [ObservableProperty] private string _nombre = "";

    /// <summary>true = el cliente elige varias opciones (checkbox); false = una sola (radio).</summary>
    [ObservableProperty] private bool _multiple;

    /// <summary>true = obligatorio elegir al menos una opción al vender.</summary>
    [ObservableProperty] private bool _obligatorio;

    public ObservableCollection<OpcionModificadorEditVM> Opciones { get; } = new();
}

/// <summary>
/// VM editable de una opción de un grupo (rubro comida). <see cref="PrecioExtra"/> se
/// suma al precio base del producto al venderlo.
/// </summary>
public partial class OpcionModificadorEditVM : ObservableObject
{
    [ObservableProperty] private string _nombre = "";
    [ObservableProperty] private decimal _precioExtra;
}
