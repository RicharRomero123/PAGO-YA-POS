using System.Collections.ObjectModel;
using System.ComponentModel;
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
/// Recepción hotelera integrada en <b>Cobrar</b>: mapa de habitaciones por piso,
/// alquiler (check-in por hora/noche, marca la hora de ingreso) y check-out que
/// cobra el hospedaje + consumos como una <see cref="Venta"/> normal (entra a Caja
/// y Reportes, con hora de ingreso/salida en el ticket). La habitación se
/// administra aparte (crear/editar) en el módulo Habitaciones.
/// </summary>
public partial class RecepcionPosViewModel : ObservableObject
{
    private readonly IHotelRepository? _hotel;
    private readonly IProductoRepository? _productos;
    private readonly IVentaRepository? _ventas;
    private readonly ICajaRepository? _cajas;
    private readonly ITicketPrinter? _impresora;

    private const decimal TasaIgv = 0.18m;

    private readonly ObservableCollection<HabitacionCardVM> _habitaciones = new();

    /// <summary>Vista del mapa agrupada por piso.</summary>
    public ICollectionView HabitacionesView { get; }

    /// <summary>Productos del inventario para cargar como consumo.</summary>
    public ObservableCollection<ProductoConsumoOpcion> ProductosConsumo { get; } = new();

    /// <summary>Consumos de la estadía seleccionada.</summary>
    public ObservableCollection<ConsumoLineaVM> ConsumosActuales { get; } = new();

    public IReadOnlyList<string> MetodosPago { get; } = new[] { "Efectivo", "Yape / Plin", "Tarjeta" };

    [ObservableProperty] private string _mensajeEstado = "";
    [ObservableProperty] private int _disponibles;
    [ObservableProperty] private int _ocupadas;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HaySeleccion))]
    [NotifyPropertyChangedFor(nameof(SelDisponible))]
    [NotifyPropertyChangedFor(nameof(SelOcupada))]
    [NotifyPropertyChangedFor(nameof(SelLiberable))]
    private HabitacionCardVM? _seleccion;

    public bool HaySeleccion => Seleccion is not null;
    public bool SelDisponible => Seleccion?.Estado == EstadoHabitacion.Disponible;
    public bool SelOcupada => Seleccion?.Estado == EstadoHabitacion.Ocupada;
    public bool SelLiberable => Seleccion is { Estado: EstadoHabitacion.Limpieza or EstadoHabitacion.Mantenimiento or EstadoHabitacion.Reservada };

    private EstadiaHabitacion? _estadiaActual;

    // --- Alquiler (check-in) ---
    [ObservableProperty] private string _ciNombre = "";
    [ObservableProperty] private string _ciDocumento = "";
    [ObservableProperty] private string _ciTelefono = "";
    [ObservableProperty] private int _ciPersonas = 1;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CiTarifaTexto))]
    private bool _ciPorHora;

    public string CiTarifaTexto
    {
        get
        {
            if (Seleccion is null) return "";
            var precio = CiPorHora ? Seleccion.PrecioHora : Seleccion.PrecioNoche;
            return $"Tarifa: S/ {precio:N2} por {(CiPorHora ? "hora" : "noche")}";
        }
    }

    // --- Productos adicionales pedidos al momento del check-in (van a la misma cuenta/boleta) ---
    /// <summary>Productos que el huésped pide al ingresar (se cargan a la habitación al alquilar).</summary>
    public ObservableCollection<AdicionalStaged> AdicionalesCheckin { get; } = new();

    [ObservableProperty] private ProductoConsumoOpcion? _ciProducto;
    [ObservableProperty] private int _ciCantidad = 1;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(TotalAdicionalesTexto))]
    private decimal _totalAdicionales;

    public string TotalAdicionalesTexto => $"S/ {TotalAdicionales:N2}";

    // --- Ocupación / check-out ---
    [ObservableProperty] private string _ocupHuesped = "";
    [ObservableProperty] private string _ocupDocumento = "";
    [ObservableProperty] private string _ocupIngreso = "";
    [ObservableProperty] private string _ocupTiempo = "";
    [ObservableProperty] private string _ocupModalidad = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MontoConsumosTexto))]
    private decimal _totalConsumos;

    public string MontoConsumosTexto => $"S/ {TotalConsumos:N2}";

    [ObservableProperty] private ProductoConsumoOpcion? _consumoProducto;
    [ObservableProperty] private int _consumoCantidad = 1;

    [ObservableProperty] private bool _checkoutVisible;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MontoHospedajeTexto))]
    [NotifyPropertyChangedFor(nameof(TotalCheckoutTexto))]
    private decimal _unidadesCobro = 1;

    [ObservableProperty] private decimal _precioUnitarioCobro;
    [ObservableProperty] private string _unidadCobroEtiqueta = "noches";
    [ObservableProperty] private int _metodoPagoIndex;

    public string MontoHospedajeTexto => $"S/ {(UnidadesCobro * PrecioUnitarioCobro):N2}";
    public string TotalCheckoutTexto => $"S/ {(UnidadesCobro * PrecioUnitarioCobro + TotalConsumos):N2}";

    partial void OnUnidadesCobroChanged(decimal value)
    { OnPropertyChanged(nameof(MontoHospedajeTexto)); OnPropertyChanged(nameof(TotalCheckoutTexto)); }

    /// <summary>Constructor de DISEÑO.</summary>
    public RecepcionPosViewModel()
    {
        _habitaciones.Add(HabitacionCardVM.Mock("101", 1, "Simple", EstadoHabitacion.Disponible, 60, 20));
        _habitaciones.Add(HabitacionCardVM.Mock("102", 1, "Matrimonial", EstadoHabitacion.Ocupada, 80, 25, "Juan Pérez"));
        _habitaciones.Add(HabitacionCardVM.Mock("201", 2, "Suite", EstadoHabitacion.Disponible, 150, 0));
        HabitacionesView = CrearVistaAgrupada();
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public RecepcionPosViewModel(
        IHotelRepository hotel, IProductoRepository productos,
        IVentaRepository ventas, ICajaRepository cajas, ITicketPrinter impresora)
    {
        _hotel = hotel;
        _productos = productos;
        _ventas = ventas;
        _cajas = cajas;
        _impresora = impresora;
        HabitacionesView = CrearVistaAgrupada();
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

        if (ProductosConsumo.Count == 0 && _productos is not null)
            foreach (var p in await _productos.BuscarAsync(null, ct))
                ProductosConsumo.Add(new ProductoConsumoOpcion(p.Id, p.Nombre, p.PrecioFinal));

        var idSel = Seleccion?.Id;
        _habitaciones.Clear();
        foreach (var h in await _hotel.ListarHabitacionesAsync(true, ct))
        {
            string? huesped = null;
            if (h.Estado == EstadoHabitacion.Ocupada)
                huesped = (await _hotel.ObtenerEstadiaActivaAsync(h.Id, ct))?.HuespedNombre;
            _habitaciones.Add(HabitacionCardVM.Desde(h, huesped));
        }
        Disponibles = _habitaciones.Count(h => h.Estado == EstadoHabitacion.Disponible);
        Ocupadas = _habitaciones.Count(h => h.Estado == EstadoHabitacion.Ocupada);
        HabitacionesView.Refresh();

        if (idSel is { } sid)
        {
            var card = _habitaciones.FirstOrDefault(c => c.Id == sid);
            if (card is not null) await SeleccionarAsync(card); else Seleccion = null;
        }
    }

    [RelayCommand]
    private async Task Seleccionar(HabitacionCardVM? card) => await SeleccionarAsync(card);

    private async Task SeleccionarAsync(HabitacionCardVM? card)
    {
        CheckoutVisible = false;
        Seleccion = card;
        _estadiaActual = null;
        ConsumosActuales.Clear();
        TotalConsumos = 0;
        if (card is null) return;

        CiNombre = ""; CiDocumento = ""; CiTelefono = ""; CiPersonas = 1;
        CiPorHora = card.PrecioNoche <= 0 && card.PrecioHora > 0;
        AdicionalesCheckin.Clear(); CiProducto = null; CiCantidad = 1; TotalAdicionales = 0;
        OnPropertyChanged(nameof(CiTarifaTexto));

        if (card.Estado == EstadoHabitacion.Ocupada && _hotel is not null)
            await CargarEstadiaAsync(card.Id);
    }

    private async Task CargarEstadiaAsync(Guid habitacionId)
    {
        if (_hotel is null) return;
        _estadiaActual = await _hotel.ObtenerEstadiaActivaAsync(habitacionId);
        if (_estadiaActual is null) return;

        OcupHuesped = _estadiaActual.HuespedNombre;
        OcupDocumento = _estadiaActual.HuespedDocumento;
        OcupIngreso = _estadiaActual.CheckInUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm");
        OcupTiempo = TiempoTranscurrido(_estadiaActual.CheckInUtc);
        OcupModalidad = _estadiaActual.TipoCobro == TipoCobroHospedaje.Hora
            ? $"Por hora · S/ {_estadiaActual.PrecioUnitario:N2}/h"
            : $"Por noche · S/ {_estadiaActual.PrecioUnitario:N2}/noche";

        ConsumosActuales.Clear();
        foreach (var c in await _hotel.ListarConsumosAsync(_estadiaActual.Id))
            ConsumosActuales.Add(new ConsumoLineaVM(c.Id, c.Descripcion, c.Cantidad, c.PrecioUnitario, c.Importe));
        TotalConsumos = await _hotel.TotalConsumosAsync(_estadiaActual.Id);
    }

    // ---------------- Adicionales en el check-in ----------------
    [RelayCommand]
    private void AgregarAdicionalCheckin()
    {
        if (CiProducto is null) { MensajeEstado = "Elige un producto para agregar."; return; }
        var cant = CiCantidad < 1 ? 1 : CiCantidad;

        // Si ya está en la lista, suma cantidad en vez de duplicar.
        var existente = AdicionalesCheckin.FirstOrDefault(a => a.ProductoId == CiProducto.Id);
        if (existente is not null)
        {
            var idx = AdicionalesCheckin.IndexOf(existente);
            AdicionalesCheckin[idx] = existente with { Cantidad = existente.Cantidad + cant };
        }
        else
        {
            AdicionalesCheckin.Add(new AdicionalStaged(Guid.NewGuid(), CiProducto.Id, CiProducto.Nombre, cant, CiProducto.Precio));
        }
        CiProducto = null; CiCantidad = 1;
        TotalAdicionales = AdicionalesCheckin.Sum(a => a.Importe);
    }

    [RelayCommand]
    private void QuitarAdicionalCheckin(AdicionalStaged? item)
    {
        if (item is null) return;
        AdicionalesCheckin.Remove(item);
        TotalAdicionales = AdicionalesCheckin.Sum(a => a.Importe);
    }

    // ---------------- Alquiler ----------------
    [RelayCommand]
    private async Task Alquilar()
    {
        if (_hotel is null || Seleccion is null) return;
        if (string.IsNullOrWhiteSpace(CiNombre)) { MensajeEstado = "Ingresa el nombre del huésped."; return; }
        if (string.IsNullOrWhiteSpace(CiDocumento)) { MensajeEstado = "Ingresa el documento del huésped."; return; }
        var precio = CiPorHora ? Seleccion.PrecioHora : Seleccion.PrecioNoche;
        if (precio <= 0) { MensajeEstado = "La habitación no tiene tarifa para esa modalidad."; return; }

        try
        {
            var e = new EstadiaHabitacion
            {
                HabitacionId = Seleccion.Id,
                NumeroHabitacion = Seleccion.Numero,
                HuespedNombre = CiNombre.Trim(),
                HuespedDocumento = CiDocumento.Trim(),
                HuespedTelefono = string.IsNullOrWhiteSpace(CiTelefono) ? null : CiTelefono.Trim(),
                Personas = CiPersonas < 1 ? 1 : CiPersonas,
                TipoCobro = CiPorHora ? TipoCobroHospedaje.Hora : TipoCobroHospedaje.Noche,
                PrecioUnitario = precio,
                CheckInUtc = DateTime.UtcNow,
                Estado = EstadoEstadia.Activa
            };
            await _hotel.GuardarEstadiaAsync(e);

            // Cargar a la cuenta los productos pedidos al ingresar (van a la misma boleta del check-out).
            foreach (var a in AdicionalesCheckin)
                await _hotel.AgregarConsumoAsync(new ConsumoHabitacion
                {
                    EstadiaId = e.Id, ProductoId = a.ProductoId, Descripcion = a.Descripcion,
                    Cantidad = a.Cantidad, PrecioUnitario = a.PrecioUnitario, FechaHoraUtc = DateTime.UtcNow
                });

            await _hotel.CambiarEstadoHabitacionAsync(Seleccion.Id, EstadoHabitacion.Ocupada);
            var extra = AdicionalesCheckin.Count > 0 ? $" + {AdicionalesCheckin.Count} producto(s)" : "";
            MensajeEstado = $"Ingreso registrado: {e.HuespedNombre} en habitación {e.NumeroHabitacion}{extra}. Se cobra todo junto en el check-out.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo registrar el ingreso: {ex.Message}"; }
    }

    // ---------------- Consumos ----------------
    [RelayCommand]
    private async Task AgregarConsumo()
    {
        if (_hotel is null || _estadiaActual is null) return;
        if (ConsumoProducto is null) { MensajeEstado = "Elige un producto para cargar el consumo."; return; }
        var cant = ConsumoCantidad < 1 ? 1 : ConsumoCantidad;
        try
        {
            // El stock se descuenta al hacer check-out (la venta incluye los consumos),
            // para no descontar dos veces.
            await _hotel.AgregarConsumoAsync(new ConsumoHabitacion
            {
                EstadiaId = _estadiaActual.Id,
                ProductoId = ConsumoProducto.Id,
                Descripcion = ConsumoProducto.Nombre,
                Cantidad = cant,
                PrecioUnitario = ConsumoProducto.Precio,
                FechaHoraUtc = DateTime.UtcNow
            });
            ConsumoCantidad = 1;
            MensajeEstado = $"Consumo agregado: {ConsumoProducto.Nombre} x{cant}.";
            await CargarEstadiaAsync(_estadiaActual.HabitacionId);
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo agregar el consumo: {ex.Message}"; }
    }

    [RelayCommand]
    private async Task QuitarConsumo(ConsumoLineaVM? linea)
    {
        if (_hotel is null || _estadiaActual is null || linea is null) return;
        try { await _hotel.QuitarConsumoAsync(linea.Id); await CargarEstadiaAsync(_estadiaActual.HabitacionId); }
        catch (Exception ex) { MensajeEstado = $"No se pudo quitar el consumo: {ex.Message}"; }
    }

    // ---------------- Check-out (cobro como venta) ----------------
    [RelayCommand]
    private void IniciarCheckout()
    {
        if (_estadiaActual is null) return;
        PrecioUnitarioCobro = _estadiaActual.PrecioUnitario;
        UnidadCobroEtiqueta = _estadiaActual.TipoCobro == TipoCobroHospedaje.Hora ? "horas" : "noches";
        UnidadesCobro = CalcularUnidades(_estadiaActual);
        MetodoPagoIndex = 0;
        CheckoutVisible = true;
    }

    [RelayCommand]
    private void CancelarCheckout() => CheckoutVisible = false;

    [RelayCommand]
    private async Task ConfirmarCheckout()
    {
        if (_hotel is null || _ventas is null || _cajas is null || _estadiaActual is null || Seleccion is null) return;
        try
        {
            var caja = await _cajas.ObtenerCajaAbiertaAsync();
            if (caja is null) { MensajeEstado = "No hay caja abierta. Abre la caja antes de cobrar."; return; }

            var unidades = UnidadesCobro < 1 ? 1 : decimal.Round(UnidadesCobro, 2);
            var precio = _estadiaActual.PrecioUnitario;
            var hospedaje = decimal.Round(unidades * precio, 2);
            var consumos = await _hotel.ListarConsumosAsync(_estadiaActual.Id);
            var totalConsumos = consumos.Sum(c => c.Importe);
            var total = hospedaje + totalConsumos;

            var salida = DateTime.Now;
            var ingresoLocal = _estadiaActual.CheckInUtc.ToLocalTime();

            // Asegurar el producto oculto de hospedaje (para la FK de detalle_ventas).
            if (_productos is not null)
                await _productos.GuardarAsync(ProductosEspeciales.Hospedaje());

            var venta = new Venta
            {
                Numero = "H-" + DateTime.Now.ToString("yyMMdd-HHmmss"),
                CajaId = caja.Id,
                FechaHora = salida,
                MetodoPago = IndiceAMetodoPago(MetodoPagoIndex),
                Estado = EstadoVenta.Completada,
                Total = total,
                SubTotal = decimal.Round(total / (1 + TasaIgv), 2),
                Igv = total - decimal.Round(total / (1 + TasaIgv), 2),
                MontoRecibido = total,
                OrigenCajaId = caja.OrigenCajaId
            };

            var etiqueta = _estadiaActual.TipoCobro == TipoCobroHospedaje.Hora ? "hora(s)" : "noche(s)";
            venta.Detalles.Add(new DetalleVenta
            {
                ProductoId = ProductosEspeciales.HospedajeId,
                DescripcionProducto =
                    $"Hab {_estadiaActual.NumeroHabitacion} · {unidades:0.##} {etiqueta} " +
                    $"({ingresoLocal:dd/MM HH:mm} → {salida:dd/MM HH:mm})",
                Cantidad = unidades,
                PrecioUnitario = precio,
                Importe = hospedaje,
                OrigenCajaId = caja.OrigenCajaId
            });

            foreach (var c in consumos)
                venta.Detalles.Add(new DetalleVenta
                {
                    ProductoId = c.ProductoId ?? ProductosEspeciales.HospedajeId,
                    DescripcionProducto = c.Descripcion,
                    Cantidad = c.Cantidad,
                    PrecioUnitario = c.PrecioUnitario,
                    Importe = c.Importe,
                    OrigenCajaId = caja.OrigenCajaId
                });

            // Registrar venta (atómico: descuenta stock de los consumos reales).
            await _ventas.RegistrarAsync(venta);

            if (venta.MetodoPago == MetodoPago.Efectivo)
                await _cajas.RegistrarMovimientoAsync(new MovimientoCaja
                {
                    CajaId = caja.Id,
                    Tipo = TipoMovimientoCaja.Ingreso,
                    Monto = venta.Total,
                    Concepto = $"Hospedaje Hab {_estadiaActual.NumeroHabitacion} ({venta.Numero})",
                    FechaHora = DateTime.Now,
                    OrigenCajaId = caja.OrigenCajaId
                });

            if (_impresora is not null)
                try { await _impresora.ImprimirTicketVentaAsync(venta); } catch { /* ticket secundario */ }

            // Cerrar estadía y liberar habitación (a limpieza).
            _estadiaActual.CheckOutUtc = DateTime.UtcNow;
            _estadiaActual.Unidades = unidades;
            _estadiaActual.MontoHospedaje = hospedaje;
            _estadiaActual.MontoConsumos = totalConsumos;
            _estadiaActual.Total = total;
            _estadiaActual.MetodoPago = (int)venta.MetodoPago;
            _estadiaActual.Estado = EstadoEstadia.Cerrada;
            await _hotel.GuardarEstadiaAsync(_estadiaActual);
            await _hotel.CambiarEstadoHabitacionAsync(Seleccion.Id, EstadoHabitacion.Limpieza);

            MensajeEstado = $"Check-out Hab {_estadiaActual.NumeroHabitacion}: cobrado S/ {total:N2} ({venta.Numero}).";
            CheckoutVisible = false;
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo cobrar el check-out: {ex.Message}"; }
    }

    // ---------------- Estado de habitación ----------------
    [RelayCommand]
    private async Task MarcarDisponible()
    {
        if (_hotel is null || Seleccion is null) return;
        await _hotel.CambiarEstadoHabitacionAsync(Seleccion.Id, EstadoHabitacion.Disponible);
        MensajeEstado = $"Habitación {Seleccion.Numero} disponible.";
        await CargarAsync();
    }

    // ---------------- Helpers ----------------
    private static decimal CalcularUnidades(EstadiaHabitacion e)
    {
        var span = DateTime.UtcNow - e.CheckInUtc;
        var u = e.TipoCobro == TipoCobroHospedaje.Hora
            ? Math.Ceiling((decimal)span.TotalHours)
            : Math.Ceiling((decimal)span.TotalDays);
        return u < 1 ? 1 : u;
    }

    private static string TiempoTranscurrido(DateTime desdeUtc)
    {
        var s = DateTime.UtcNow - desdeUtc;
        if (s.TotalMinutes < 1) return "recién ingresó";
        if (s.TotalHours < 1) return $"{(int)s.TotalMinutes} min";
        if (s.TotalDays < 1) return $"{(int)s.TotalHours}h {s.Minutes}min";
        return $"{(int)s.TotalDays}d {s.Hours}h";
    }

    private static MetodoPago IndiceAMetodoPago(int i) => i switch
    {
        1 => MetodoPago.BilleteraDigital,
        2 => MetodoPago.Tarjeta,
        _ => MetodoPago.Efectivo
    };
}

/// <summary>Producto adicional pedido al momento del check-in (aún no persistido).</summary>
public sealed record AdicionalStaged(Guid TempId, Guid ProductoId, string Descripcion, decimal Cantidad, decimal PrecioUnitario)
{
    public decimal Importe => decimal.Round(Cantidad * PrecioUnitario, 2);
    public string CantidadTexto => Cantidad == Math.Truncate(Cantidad) ? ((long)Cantidad).ToString() : Cantidad.ToString("0.###");
}
