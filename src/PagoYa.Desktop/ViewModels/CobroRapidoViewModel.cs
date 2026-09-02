using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios;
using PagoYa.Desktop.Servicios.Impresion;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// ViewModel de la pantalla de <b>Cobro Rápido</b> (la más importante del POS).
///
/// Runtime: carga el catálogo real desde <see cref="IProductoRepository"/> y, al
/// cobrar, registra la <see cref="Venta"/> + su detalle vía
/// <see cref="IVentaRepository"/> (atómico, descuenta inventario y escribe
/// outbox), registra el movimiento de caja, imprime el ticket ESC/POS y —si el
/// flag "invoicing" está activo— engancha el motor de facturación.
///
/// Diseño: el constructor sin parámetros siembra datos mock para el render en
/// modo diseñador (d:DataContext). En producción se usa el constructor con DI.
/// </summary>
public partial class CobroRapidoViewModel : ObservableObject
{
    private const decimal TasaIgv = 0.18m; // IGV Perú 18%

    private readonly IProductoRepository? _productos_repo;
    private readonly IVentaRepository? _ventas;
    private readonly ICajaRepository? _cajas;
    private readonly ITicketPrinter? _impresora;
    private readonly IInvoiceEngine? _facturacion;
    private readonly ILicenseService? _licencia;
    private readonly IConfiguracionStore? _config;
    private readonly IHotelRepository? _hotel;

    /// <summary>Fuente completa de productos. Se filtra en <see cref="ProductosView"/>.</summary>
    private readonly ObservableCollection<ProductoItemViewModel> _productos = new();

    public ICollectionView ProductosView { get; }

    public ObservableCollection<CarritoItemViewModel> Carrito { get; } = new();

    /// <summary>True si el negocio es hotel/hostal: agrega la categoría "Habitaciones" al POS.</summary>
    [ObservableProperty] private bool _esHotel;

    /// <summary>Tiles de habitaciones (se muestran en la grilla al elegir la categoría "Habitaciones").</summary>
    public ObservableCollection<HabitacionCardVM> Habitaciones { get; } = new();

    // --- Diálogo "alquilar habitación" (agrega la habitación al carrito) ---
    [ObservableProperty] private bool _habDialogoVisible;
    private Guid _habDialogId;
    private string _habDialogNumero = "";
    private decimal _habDialogPrecioNoche;
    private decimal _habDialogPrecioHora;

    [ObservableProperty] private string _habDialogTitulo = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HabDialogTarifaTexto))]
    [NotifyPropertyChangedFor(nameof(HabDialogTotalTexto))]
    private bool _habDialogPorHora;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HabDialogTotalTexto))]
    private int _habDialogCantidad = 1;

    [ObservableProperty] private string _habDialogHuesped = "";
    [ObservableProperty] private string _habDialogDocumento = "";

    public string HabDialogUnidad => HabDialogPorHora ? "horas" : "noches";
    public decimal HabDialogTarifa => HabDialogPorHora ? _habDialogPrecioHora : _habDialogPrecioNoche;
    public string HabDialogTarifaTexto => $"Tarifa: S/ {HabDialogTarifa:N2} por {(HabDialogPorHora ? "hora" : "noche")}";
    public string HabDialogTotalTexto => $"S/ {(HabDialogTarifa * (HabDialogCantidad < 1 ? 1 : HabDialogCantidad)):N2}";

    partial void OnHabDialogPorHoraChanged(bool value) { OnPropertyChanged(nameof(HabDialogUnidad)); OnPropertyChanged(nameof(HabDialogTarifa)); }

    // --- Diálogo "personalizar producto" (rubro comida: modificadores + nota de cocina) ---
    [ObservableProperty] private bool _personalizarVisible;

    /// <summary>Producto en curso de personalización (mientras el diálogo está abierto).</summary>
    private ProductoItemViewModel? _personalizandoProducto;

    [ObservableProperty] private string _personalizarTitulo = "";

    /// <summary>True si el producto en curso permite escribir una nota para la cocina.</summary>
    [ObservableProperty] private bool _personalizarPermiteNota;

    /// <summary>Nota libre para la cocina (se imprime en el ticket).</summary>
    [ObservableProperty] private string _personalizarNota = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PersonalizarTotalTexto))]
    private int _personalizarCantidad = 1;

    /// <summary>Grupos de modificadores del producto en curso (radios/checkboxes en el diálogo).</summary>
    public ObservableCollection<GrupoPersonalizacionVM> PersonalizarGrupos { get; } = new();

    /// <summary>Precio unitario resultante = base + extras elegidos (se recalcula en vivo).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PersonalizarPrecioTexto))]
    [NotifyPropertyChangedFor(nameof(PersonalizarTotalTexto))]
    private decimal _personalizarPrecioUnitario;

    public string PersonalizarPrecioTexto => $"S/ {PersonalizarPrecioUnitario:N2}";
    public string PersonalizarTotalTexto =>
        $"S/ {(PersonalizarPrecioUnitario * (PersonalizarCantidad < 1 ? 1 : PersonalizarCantidad)):N2}";

    /// <summary>Categorías con imagen/ícono representativo para la barra lateral.</summary>
    public ObservableCollection<CategoriaItem> Categorias { get; } = new();

    public ObservableCollection<string> MetodosPago { get; } = new()
    {
        "Efectivo", "Yape / Plin", "Tarjeta"
    };

    [ObservableProperty] private string _textoBusqueda = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MostrandoHabitaciones))]
    private string _categoriaSeleccionada = "Todas";

    /// <summary>True cuando la categoría activa es "Habitaciones" (la grilla muestra cuartos).</summary>
    public bool MostrandoHabitaciones => CategoriaSeleccionada == "Habitaciones";
    [ObservableProperty] private string _metodoPagoSeleccionado = "Efectivo";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Vuelto))]
    [NotifyPropertyChangedFor(nameof(VueltoEsNegativo))]
    private decimal _pagaCon;

    /// <summary>Texto del monto "Paga con" (fuente de verdad para teclado físico y numpad táctil).</summary>
    [ObservableProperty] private string _pagaConTexto = "";

    /// <summary>Modo táctil: muestra el teclado numérico en pantalla para digitar montos.</summary>
    [ObservableProperty] private bool _modoTactil;

    [ObservableProperty] private decimal _subtotal;
    [ObservableProperty] private decimal _igv;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Vuelto))]
    [NotifyPropertyChangedFor(nameof(VueltoEsNegativo))]
    [NotifyPropertyChangedFor(nameof(CarritoTieneItems))]
    private decimal _total;

    [ObservableProperty] private int _cantidadItems;

    /// <summary>Aviso al usuario tras cobrar (impresión/facturación). Efímero.</summary>
    [ObservableProperty] private string _mensajeEstado = "";

    /// <summary>Vuelto = paga con − total. Nunca negativo para mostrar.</summary>
    public decimal Vuelto => PagaCon > Total ? PagaCon - Total : 0m;

    /// <summary>True si el efectivo entregado no alcanza (para tinte de aviso).</summary>
    public bool VueltoEsNegativo => PagaCon > 0 && PagaCon < Total;

    public bool CarritoTieneItems => Total > 0m;

    /// <summary>Constructor de DISEÑO: siembra mock para el diseñador. No toca BD.</summary>
    public CobroRapidoViewModel()
    {
        ProductosView = CollectionViewSource.GetDefaultView(_productos);
        ProductosView.Filter = FiltrarProducto;
        SembrarDatosDeDiseno();
        RecalcularTotales();
    }

    /// <summary>Constructor de PRODUCCIÓN (DI): usa repositorios y servicios reales.</summary>
    public CobroRapidoViewModel(
        IProductoRepository productos,
        IVentaRepository ventas,
        ICajaRepository cajas,
        ITicketPrinter impresora,
        IInvoiceEngine facturacion,
        ILicenseService licencia,
        IConfiguracionStore config,
        IHotelRepository hotel)
    {
        _productos_repo = productos;
        _ventas = ventas;
        _cajas = cajas;
        _impresora = impresora;
        _facturacion = facturacion;
        _licencia = licencia;
        _config = config;
        _hotel = hotel;

        var cfg = config.Leer();
        ModoTactil = cfg?.ModoTactil ?? false;
        EsHotel = string.Equals(cfg?.Rubro, "hotel", StringComparison.OrdinalIgnoreCase);

        ProductosView = CollectionViewSource.GetDefaultView(_productos);
        ProductosView.Filter = FiltrarProducto;
    }

    // ------------------------------------------------------------------
    // Teclado numérico en pantalla (modo táctil) para "Paga con"
    // ------------------------------------------------------------------

    /// <summary>Convierte el texto del monto a decimal (acepta punto decimal).</summary>
    partial void OnPagaConTextoChanged(string value)
    {
        PagaCon = decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out var d) ? d : 0m;
    }

    /// <summary>Pulsa una tecla del numpad: dígito 0-9 o "." (un solo punto).</summary>
    [RelayCommand]
    private void TeclaMonto(string? tecla)
    {
        if (string.IsNullOrEmpty(tecla)) return;
        if (tecla == "." && PagaConTexto.Contains('.')) return;
        if (PagaConTexto.Length >= 9) return; // límite razonable
        // Evita ceros a la izquierda tipo "00" (permite "0.").
        if (tecla != "." && PagaConTexto == "0") PagaConTexto = tecla;
        else PagaConTexto += tecla;
    }

    /// <summary>Borra el último carácter del monto.</summary>
    [RelayCommand]
    private void BorrarMonto()
    {
        if (PagaConTexto.Length > 0) PagaConTexto = PagaConTexto[..^1];
    }

    /// <summary>Limpia el monto "Paga con".</summary>
    [RelayCommand]
    private void LimpiarMonto() => PagaConTexto = "";

    /// <summary>Activa/desactiva el modo táctil (persiste en la config).</summary>
    [RelayCommand]
    private void ToggleTactil()
    {
        ModoTactil = !ModoTactil;
        try
        {
            var cfg = _config?.Leer() ?? new ConfiguracionNegocio();
            cfg.ModoTactil = ModoTactil;
            _config?.Guardar(cfg);
        }
        catch { /* no bloquear el cobro por un fallo al guardar preferencia */ }
    }

    /// <summary>Carga el catálogo real desde BD. Llamar tras construir (async).</summary>
    public async Task CargarCatalogoAsync(CancellationToken ct = default)
    {
        if (_productos_repo is null) return;

        var lista = await _productos_repo.BuscarAsync(null, ct);
        _productos.Clear();
        foreach (var p in lista)
            _productos.Add(ProductoItemViewModel.Desde(p));

        // Habitaciones (rubro hotel): tiles que se muestran al elegir esa categoría.
        if (EsHotel && _hotel is not null)
        {
            Habitaciones.Clear();
            foreach (var h in await _hotel.ListarHabitacionesAsync(true, ct))
            {
                string? huesped = null;
                if (h.Estado == EstadoHabitacion.Ocupada)
                    huesped = (await _hotel.ObtenerEstadiaActivaAsync(h.Id, ct))?.HuespedNombre;
                Habitaciones.Add(HabitacionCardVM.Desde(h, huesped));
            }
        }

        ReconstruirCategorias();
        ProductosView.Refresh();
        RecalcularTotales();
    }

    // ------------------------------------------------------------------
    // Comandos de carrito
    // ------------------------------------------------------------------

    [RelayCommand]
    private void AgregarProducto(ProductoItemViewModel? producto)
    {
        if (producto is null) return;

        // Bloqueo de vencidos (farmacia): un medicamento vencido no se puede vender,
        // aunque tenga stock. Mismo patrón que el bloqueo por SinStock.
        if (producto.EstaVencido)
        {
            MensajeEstado = producto.FechaVencimiento is { } fv
                ? $"«{producto.Nombre}» está vencido ({fv:dd/MM/yyyy}): no se puede vender."
                : $"«{producto.Nombre}» está vencido: no se puede vender.";
            return;
        }

        // Producto personalizable (rubro comida): abre el diálogo de modificadores
        // en vez de agregarlo directo. La validación de stock se hace al confirmar.
        if (producto.TienePersonalizacion)
        {
            AbrirPersonalizacion(producto);
            return;
        }

        AgregarAlCarrito(producto, producto.Nombre, producto.Precio);

        // Aviso no bloqueante de receta (farmacia): informa al químico/cajero, pero
        // NO impide la venta (la decisión final es del profesional).
        if (producto.RequiereReceta)
            MensajeEstado = $"«{producto.Nombre}» requiere receta médica. Verifícala antes de dispensar.";
    }

    /// <summary>
    /// Agrega (o incrementa) una línea al carrito con validación de stock. El nombre y
    /// el precio se pasan explícitos porque una línea personalizada difiere del producto
    /// base (nombre con opciones, precio con extras). Devuelve false si el stock no alcanza.
    /// </summary>
    private bool AgregarAlCarrito(ProductoItemViewModel producto, string nombreLinea, decimal precioUnitario, int cantidad = 1)
    {
        var existente = Carrito.FirstOrDefault(c => c.ProductoId == producto.ProductoId
                                                    && c.Nombre == nombreLinea);

        // Validación de stock: no se puede vender más de lo que hay en inventario.
        // El producto de diseño (ProductoId vacío) o los que no controlan stock
        // (servicios/genéricos) pasan sin límite.
        if (producto.ControlaStock && producto.ProductoId != Guid.Empty)
        {
            var enCarrito = existente?.Cantidad ?? 0;
            if (enCarrito + cantidad > producto.StockActual)
            {
                MensajeEstado = producto.StockActual <= 0
                    ? $"«{producto.Nombre}» está agotado. Reabastece en Inventario."
                    : $"Solo quedan {producto.StockActual:0.###} de «{producto.Nombre}» en stock.";
                return false;
            }
        }

        if (existente is not null)
        {
            existente.Cantidad += cantidad;
        }
        else
        {
            var linea = new CarritoItemViewModel
            {
                ProductoId = producto.ProductoId,
                Nombre = nombreLinea,
                PrecioUnitario = precioUnitario,
                Cantidad = cantidad < 1 ? 1 : cantidad
            };
            linea.AlCambiarCantidad = RecalcularTotales;
            Carrito.Add(linea);
        }
        RecalcularTotales();
        return true;
    }

    // ------------------------------------------------------------------
    // Diálogo de personalización (rubro comida)
    // ------------------------------------------------------------------

    /// <summary>Abre el diálogo de modificadores para un producto personalizable.</summary>
    private void AbrirPersonalizacion(ProductoItemViewModel producto)
    {
        _personalizandoProducto = producto;
        PersonalizarTitulo = producto.Nombre;
        PersonalizarNota = "";
        PersonalizarCantidad = 1;

        var pers = producto.Personalizacion!;
        PersonalizarPermiteNota = pers.PermiteNota;

        PersonalizarGrupos.Clear();
        foreach (var g in pers.Grupos)
        {
            var gvm = new GrupoPersonalizacionVM(g) { AlCambiarSeleccion = RecalcularPersonalizacion };
            PersonalizarGrupos.Add(gvm);
        }

        RecalcularPersonalizacion();
        PersonalizarVisible = true;
    }

    partial void OnPersonalizarCantidadChanged(int value) => OnPropertyChanged(nameof(PersonalizarTotalTexto));

    /// <summary>Recalcula el precio unitario en vivo = base + suma de extras elegidos.</summary>
    private void RecalcularPersonalizacion()
    {
        var basePrecio = _personalizandoProducto?.Precio ?? 0m;
        var extras = PersonalizarGrupos.Sum(g => g.ExtraElegido);
        PersonalizarPrecioUnitario = basePrecio + extras;
    }

    [RelayCommand]
    private void CancelarPersonalizacion()
    {
        PersonalizarVisible = false;
        _personalizandoProducto = null;
        PersonalizarGrupos.Clear();
    }

    [RelayCommand]
    private void ConfirmarPersonalizacion()
    {
        var producto = _personalizandoProducto;
        if (producto is null) { PersonalizarVisible = false; return; }

        // Grupos obligatorios sin elección: no dejar confirmar.
        var faltante = PersonalizarGrupos.FirstOrDefault(g => !g.EsValido);
        if (faltante is not null)
        {
            MensajeEstado = $"Elige una opción en «{faltante.Nombre}».";
            return;
        }

        // Nombre de la línea: base + opciones elegidas + nota (para que el ticket la
        // reciba vía DescripcionProducto y las líneas distintas no se fusionen).
        var elegidas = PersonalizarGrupos
            .SelectMany(g => g.Elegidas)
            .Select(o => o.Nombre)
            .ToList();

        var nombre = producto.Nombre;
        if (elegidas.Count > 0)
            nombre += " (" + string.Join(", ", elegidas) + ")";
        var nota = PersonalizarNota?.Trim();
        if (!string.IsNullOrWhiteSpace(nota))
            nombre += " — Nota: " + nota;

        var cant = PersonalizarCantidad < 1 ? 1 : PersonalizarCantidad;
        if (!AgregarAlCarrito(producto, nombre, PersonalizarPrecioUnitario, cant))
            return; // stock insuficiente: mantiene el diálogo abierto con el aviso puesto

        PersonalizarVisible = false;
        _personalizandoProducto = null;
        PersonalizarGrupos.Clear();

        if (producto.RequiereReceta)
            MensajeEstado = $"«{producto.Nombre}» requiere receta médica. Verifícala antes de dispensar.";
    }

    [RelayCommand]
    private void Incrementar(CarritoItemViewModel? item) { if (item is not null) item.Cantidad++; }

    [RelayCommand]
    private void Decrementar(CarritoItemViewModel? item)
    {
        if (item is null) return;
        if (item.Cantidad > 1) item.Cantidad--;
        else Quitar(item);
    }

    [RelayCommand]
    private void Quitar(CarritoItemViewModel? item)
    {
        if (item is null) return;
        Carrito.Remove(item);
        RecalcularTotales();
    }

    [RelayCommand]
    private void SeleccionarCategoria(string? categoria)
    {
        CategoriaSeleccionada = categoria ?? "Todas";
        ProductosView.Refresh();
    }

    // ------------------------------------------------------------------
    // Habitaciones (rubro hotel): vender el cuarto como una línea del carrito
    // ------------------------------------------------------------------

    /// <summary>Clic en un tile de habitación: alquilar (si está libre) o liberar (si está ocupada).</summary>
    [RelayCommand]
    private void SeleccionarHabitacion(HabitacionCardVM? card)
    {
        if (card is null) return;
        if (card.Estado != EstadoHabitacion.Disponible) { _ = LiberarHabitacionAsync(card); return; }

        _habDialogId = card.Id;
        _habDialogNumero = card.Numero;
        _habDialogPrecioNoche = card.PrecioNoche;
        _habDialogPrecioHora = card.PrecioHora;
        HabDialogTitulo = $"Alquilar habitación {card.Numero}";
        HabDialogPorHora = card.PrecioNoche <= 0 && card.PrecioHora > 0;
        HabDialogCantidad = 1;
        HabDialogHuesped = ""; HabDialogDocumento = "";
        OnPropertyChanged(nameof(HabDialogTarifa));
        OnPropertyChanged(nameof(HabDialogTarifaTexto));
        OnPropertyChanged(nameof(HabDialogTotalTexto));
        HabDialogoVisible = true;
    }

    [RelayCommand]
    private void CancelarHabDialog() => HabDialogoVisible = false;

    /// <summary>Agrega la habitación al carrito como una línea (se cobra junto con los productos).</summary>
    [RelayCommand]
    private void AgregarHabitacionAlCarrito()
    {
        var tarifa = HabDialogTarifa;
        if (tarifa <= 0) { MensajeEstado = "La habitación no tiene tarifa para esa modalidad."; return; }
        var cant = HabDialogCantidad < 1 ? 1 : HabDialogCantidad;

        var linea = new CarritoItemViewModel
        {
            ProductoId = ProductosEspeciales.HospedajeId,
            Nombre = $"Hab {_habDialogNumero} ({(HabDialogPorHora ? "por hora" : "por noche")})",
            PrecioUnitario = tarifa,
            Cantidad = cant,
            EsHabitacion = true,
            HabitacionId = _habDialogId,
            HabitacionNumero = _habDialogNumero,
            TipoCobro = HabDialogPorHora ? TipoCobroHospedaje.Hora : TipoCobroHospedaje.Noche,
            HuespedNombre = HabDialogHuesped.Trim(),
            HuespedDocumento = HabDialogDocumento.Trim()
        };
        linea.AlCambiarCantidad = RecalcularTotales;
        Carrito.Add(linea);
        HabDialogoVisible = false;
        MensajeEstado = $"Habitación {_habDialogNumero} agregada al carrito.";
        RecalcularTotales();
    }

    /// <summary>Libera una habitación ocupada (cierra su estadía y la marca disponible).</summary>
    private async Task LiberarHabitacionAsync(HabitacionCardVM card)
    {
        if (_hotel is null) return;
        try
        {
            var est = await _hotel.ObtenerEstadiaActivaAsync(card.Id);
            if (est is not null)
            {
                est.Estado = EstadoEstadia.Cerrada;
                est.CheckOutUtc = DateTime.UtcNow;
                await _hotel.GuardarEstadiaAsync(est);
            }
            await _hotel.CambiarEstadoHabitacionAsync(card.Id, EstadoHabitacion.Disponible);
            MensajeEstado = $"Habitación {card.Numero} liberada y disponible.";
            await CargarCatalogoAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo liberar la habitación: {ex.Message}"; }
    }

    [RelayCommand]
    private void SeleccionarMetodoPago(string? metodo)
    {
        if (!string.IsNullOrEmpty(metodo)) MetodoPagoSeleccionado = metodo;
    }

    /// <summary>F8 Cancelar: vacía el carrito y reinicia el cobro.</summary>
    [RelayCommand]
    private void CancelarVenta()
    {
        Carrito.Clear();
        PagaCon = 0;
        RecalcularTotales();
    }

    // ------------------------------------------------------------------
    // F4 COBRAR — flujo real
    // ------------------------------------------------------------------

    /// <summary>
    /// F4 Cobrar: (a) registra Venta+DetalleVenta (atómico, descuenta stock),
    /// (b) registra el movimiento de caja (solo efectivo afecta el arqueo),
    /// (c) imprime el ticket ESC/POS, (d) si "invoicing" está activo, engancha
    /// el motor de facturación. Tras cobrar limpia el carrito y refresca.
    /// </summary>
    [RelayCommand]
    private async Task CobrarAsync()
    {
        if (!CarritoTieneItems) return;

        // En modo diseño (sin DI) solo limpia, como el mock original.
        if (_ventas is null || _cajas is null)
        {
            Carrito.Clear();
            PagaConTexto = "";
            RecalcularTotales();
            return;
        }

        try
        {
            var caja = await _cajas.ObtenerCajaAbiertaAsync();
            if (caja is null)
            {
                MensajeEstado = "No hay una caja abierta. Abra la caja antes de cobrar.";
                return;
            }

            // Habitaciones en el carrito: asegurar el producto oculto de hospedaje (FK).
            var lineasHab = Carrito.Where(c => c.EsHabitacion).ToList();
            if (lineasHab.Count > 0 && _productos_repo is not null)
                await _productos_repo.GuardarAsync(ProductosEspeciales.Hospedaje());

            var venta = ConstruirVenta(caja);

            // (a) Persistencia atómica de la venta + detalle + inventario + outbox.
            await _ventas.RegistrarAsync(venta);

            // Registrar la estadía de cada habitación vendida y marcarla ocupada.
            foreach (var lh in lineasHab)
            {
                if (_hotel is null) break;
                await _hotel.GuardarEstadiaAsync(new Core.Entidades.EstadiaHabitacion
                {
                    HabitacionId = lh.HabitacionId,
                    NumeroHabitacion = lh.HabitacionNumero,
                    HuespedNombre = string.IsNullOrWhiteSpace(lh.HuespedNombre) ? "Huésped" : lh.HuespedNombre,
                    HuespedDocumento = lh.HuespedDocumento,
                    TipoCobro = lh.TipoCobro,
                    PrecioUnitario = lh.PrecioUnitario,
                    CheckInUtc = DateTime.UtcNow,
                    Unidades = lh.Cantidad,
                    MontoHospedaje = lh.ImporteLinea,
                    Total = lh.ImporteLinea,
                    MetodoPago = (int)venta.MetodoPago,
                    Estado = EstadoEstadia.Cerrada
                });
                await _hotel.CambiarEstadoHabitacionAsync(lh.HabitacionId, EstadoHabitacion.Ocupada);
            }

            // (b) Movimiento de caja: solo el efectivo entra al arqueo de la caja.
            if (venta.MetodoPago == MetodoPago.Efectivo)
            {
                await _cajas.RegistrarMovimientoAsync(new MovimientoCaja
                {
                    CajaId = caja.Id,
                    Tipo = TipoMovimientoCaja.Ingreso,
                    Monto = venta.Total,
                    Concepto = $"Venta {venta.Numero} (Efectivo)",
                    FechaHora = DateTime.Now,
                    OrigenCajaId = caja.OrigenCajaId
                });
            }

            // (c) Ticket ESC/POS (secundario: si falla, la venta ya está guardada).
            var resImp = _impresora is null
                ? ResultadoImpresion.Fallo("Impresora no configurada.")
                : await _impresora.ImprimirTicketVentaAsync(venta);

            // (d) Facturación electrónica (feature-gated).
            var textoFactura = await EngancharFacturacionAsync(venta);

            MensajeEstado = resImp.Exito
                ? $"Venta {venta.Numero} cobrada. Ticket impreso.{textoFactura}"
                : $"Venta {venta.Numero} cobrada. Ticket NO impreso: {resImp.Mensaje}{textoFactura}";

            // Limpiar y refrescar catálogo (stock actualizado).
            Carrito.Clear();
            PagaConTexto = "";
            RecalcularTotales();
            await CargarCatalogoAsync();
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo completar la venta: {ex.Message}";
        }
    }

    /// <summary>
    /// Enganche de facturación electrónica. TODO(sunat-facturacion): cuando el
    /// motor real (SunatInvoiceEngine) esté implementado, aquí se emite el
    /// comprobante y se guarda su Id en la venta. Hoy IInvoiceEngine es stub;
    /// solo devolvemos texto informativo si el flag está activo.
    /// </summary>
    private async Task<string> EngancharFacturacionAsync(Venta venta)
    {
        var invoicingActivo = _licencia?.TieneCaracteristica(CaracteristicaLicencia.Invoicing) == true;
        if (!invoicingActivo || _facturacion is null || !_facturacion.PuedeEmitir)
            return string.Empty;

        try
        {
            var res = await _facturacion.EmitirComprobanteAsync(venta);
            return res.Aceptado ? " Comprobante emitido." : $" Facturación: {res.Mensaje}";
        }
        catch (Exception ex)
        {
            return $" Facturación pendiente: {ex.Message}";
        }
    }

    private Venta ConstruirVenta(Caja caja)
    {
        var venta = new Venta
        {
            Numero = GenerarNumero(),
            CajaId = caja.Id,
            FechaHora = DateTime.Now,
            MetodoPago = MapearMetodo(MetodoPagoSeleccionado),
            Estado = EstadoVenta.Completada,
            SubTotal = Subtotal,
            Igv = Igv,
            Total = Total,
            MontoRecibido = PagaCon > 0 ? PagaCon : null,
            OrigenCajaId = caja.OrigenCajaId
        };

        foreach (var linea in Carrito)
        {
            venta.Detalles.Add(new DetalleVenta
            {
                ProductoId = linea.ProductoId,
                DescripcionProducto = linea.Nombre,
                Cantidad = linea.Cantidad,
                PrecioUnitario = linea.PrecioUnitario,
                Descuento = 0m,
                Importe = linea.ImporteLinea,
                OrigenCajaId = caja.OrigenCajaId
            });
        }
        return venta;
    }

    private static string GenerarNumero()
        => "V-" + DateTime.Now.ToString("yyMMdd-HHmmss");

    private static MetodoPago MapearMetodo(string etiqueta) => etiqueta switch
    {
        "Efectivo" => MetodoPago.Efectivo,
        "Yape / Plin" => MetodoPago.BilleteraDigital,
        "Tarjeta" => MetodoPago.Tarjeta,
        _ => MetodoPago.Efectivo
    };

    // ------------------------------------------------------------------
    // Cálculo y filtro
    // ------------------------------------------------------------------

    private void RecalcularTotales()
    {
        Total = Carrito.Sum(c => c.ImporteLinea);
        // El precio de bodega ya incluye IGV; lo desagregamos para el detalle.
        Subtotal = decimal.Round(Total / (1 + TasaIgv), 2);
        Igv = decimal.Round(Total - Subtotal, 2);
        CantidadItems = Carrito.Sum(c => c.Cantidad);
    }

    partial void OnTextoBusquedaChanged(string value) => ProductosView.Refresh();

    private bool FiltrarProducto(object obj)
    {
        if (obj is not ProductoItemViewModel p) return false;

        var pasaCategoria = CategoriaSeleccionada == "Todas"
                            || p.Categoria == CategoriaSeleccionada;

        var pasaBusqueda = string.IsNullOrWhiteSpace(TextoBusqueda)
                           || p.Nombre.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase)
                           || p.Codigo.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase)
                           || (!string.IsNullOrWhiteSpace(p.PrincipioActivo)
                               && p.PrincipioActivo!.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase));

        return pasaCategoria && pasaBusqueda;
    }

    // ------------------------------------------------------------------
    // Datos de diseño (mock) — solo para el diseñador (constructor sin DI)
    // ------------------------------------------------------------------

    private void SembrarDatosDeDiseno()
    {
        void Add(string nombre, decimal precio, string cat, string icono, decimal stock = 20m)
            => _productos.Add(new ProductoItemViewModel
            { Nombre = nombre, Precio = precio, Categoria = cat, Icono = icono, StockActual = stock });

        Add("Inca Kola 500ml", 3.50m, "Bebidas", "\U0001F964");
        Add("Coca Cola 500ml", 3.50m, "Bebidas", "\U0001F964", stock: 4m);  // stock bajo (demo)
        Add("Agua San Luis 625ml", 2.00m, "Bebidas", "\U0001F4A7");
        Add("Pan Frances (und)", 0.30m, "Panadería", "\U0001F35E");
        Add("Leche Gloria Tarro", 4.20m, "Abarrotes", "\U0001F95B");
        Add("Galleta Soda Field", 1.50m, "Snacks", "\U0001F36A", stock: 0m);  // agotado (demo)

        ReconstruirCategorias();
    }

    /// <summary>
    /// Rearma la barra de categorías: "Todas" + cada categoría distinta, con una
    /// FOTO representativa (la del primer producto de esa categoría que tenga foto)
    /// o un emoji según el nombre.
    /// </summary>
    private void ReconstruirCategorias()
    {
        Categorias.Clear();
        Categorias.Add(new CategoriaItem("Todas", null, "\U0001F5C2", true));
        // Habitaciones como primera categoría real (solo hotel): vende cuartos desde aquí.
        if (EsHotel)
            Categorias.Add(new CategoriaItem("Habitaciones", null, "\U0001F6CF", false));
        foreach (var cat in _productos.Select(p => p.Categoria).Distinct())
        {
            var foto = _productos.FirstOrDefault(p => p.Categoria == cat && p.TieneImagen)?.ImagenRuta;
            Categorias.Add(new CategoriaItem(cat, foto, EmojiCategoria(cat), false));
        }
    }

    /// <summary>Emoji representativo de una categoría, adivinado por palabras clave.</summary>
    private static string EmojiCategoria(string cat)
    {
        var c = cat.ToLowerInvariant();
        bool H(params string[] ks) => ks.Any(k => c.Contains(k));
        if (H("gaseosa", "bebida", "refresco")) return "\U0001F964";
        if (H("agua")) return "\U0001F4A7";
        if (H("cerveza", "licor", "vino", "trago", "cocktail")) return "\U0001F37A";
        if (H("jugo", "juguer")) return "\U0001F9C3";
        if (H("cafe", "café")) return "☕";
        if (H("abarrote", "grocer")) return "\U0001F6D2";
        if (H("snack", "piqueo")) return "\U0001F36A";
        if (H("golosina", "dulce", "chocolate", "caramelo")) return "\U0001F36B";
        if (H("limpieza", "hogar")) return "\U0001F9F9";
        if (H("pan", "panad")) return "\U0001F35E";
        if (H("fruta", "verdura")) return "\U0001F96C";
        if (H("carne", "pollo", "parrilla", "brasa")) return "\U0001F357";
        if (H("lacteo", "leche")) return "\U0001F95B";
        if (H("entrada")) return "\U0001F957";
        if (H("plato", "fondo", "menu", "menú")) return "\U0001F37D";
        if (H("postre")) return "\U0001F370";
        if (H("sándwich", "sandwich")) return "\U0001F96A";
        if (H("medicament", "farmac", "botica")) return "\U0001F48A";
        if (H("higiene", "cuidado", "personal")) return "\U0001F9F4";
        if (H("herramient")) return "\U0001F528";
        if (H("electric")) return "\U0001F4A1";
        if (H("gasfit", "tuberia", "caño")) return "\U0001F6BF";
        if (H("habitaci", "cuarto", "suite")) return "\U0001F6CF";
        if (H("minibar", "consumo")) return "\U0001F37E";
        if (H("servicio")) return "\U0001F6CE";
        return "\U0001F3F7";
    }
}

/// <summary>Categoría de la barra lateral: nombre + foto representativa o emoji.</summary>
public sealed record CategoriaItem(string Nombre, string? ImagenRuta, string Icono, bool EsTodas)
{
    public bool TieneImagen => !string.IsNullOrWhiteSpace(ImagenRuta);
}
