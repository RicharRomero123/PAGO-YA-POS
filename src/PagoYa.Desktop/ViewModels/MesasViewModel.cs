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
/// Módulo <b>Mesas + Comandas</b> (rubro restaurante/pollería/cafetería). Integra en
/// una sola pantalla el flujo del salón, análogo al de recepción del hotel:
///   mapa por zona → abrir/atender cuenta (comanda) → enviar a cocina → cobrar.
///
/// Al abrir una mesa se crea (o recupera) un <see cref="Pedido"/> abierto y sus
/// líneas (<see cref="PedidoLinea"/>). Los productos personalizables (comida) abren
/// el diálogo de modificadores reutilizado del Cobro Rápido. El cobro construye una
/// <see cref="Venta"/> normal (mismo desglose IGV 18% que CobroRapido), entra a caja
/// y reportes, imprime ticket y libera la mesa. La comanda a cocina imprime sin
/// precios (mesa, mozo, hora, ítems + notas) marcando las líneas como enviadas.
///
/// El editor de mesas (alta/edición/baja) vive aquí mismo, como en Habitaciones.
/// </summary>
public partial class MesasViewModel : ObservableObject
{
    private const decimal TasaIgv = 0.18m; // IGV Perú 18%

    private readonly IMesaRepository? _mesas;
    private readonly IProductoRepository? _productos;
    private readonly IVentaRepository? _ventas;
    private readonly ICajaRepository? _cajas;
    private readonly ITicketPrinter? _impresora;
    private readonly IConfiguracionStore? _config;
    private readonly SesionActual? _sesion;

    private readonly ObservableCollection<MesaCardVM> _mesasCards = new();

    /// <summary>Vista del salón agrupada por zona.</summary>
    public ICollectionView MesasView { get; }

    // --- Catálogo (para la cuenta) ---
    private readonly ObservableCollection<ProductoItemViewModel> _productosCatalogo = new();
    public ICollectionView ProductosView { get; }

    /// <summary>Líneas de la cuenta de la mesa seleccionada.</summary>
    public ObservableCollection<PedidoLineaVM> LineasCuenta { get; } = new();

    public IReadOnlyList<string> MetodosPago { get; } = new[] { "Efectivo", "Yape / Plin", "Tarjeta" };

    [ObservableProperty] private string _mensajeEstado = "";
    [ObservableProperty] private int _totalMesas;
    [ObservableProperty] private int _libres;
    [ObservableProperty] private int _ocupadas;

    // ------------------------------------------------------------------
    // Cuenta / comanda de la mesa seleccionada
    // ------------------------------------------------------------------

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HaySeleccion))]
    private MesaCardVM? _seleccion;

    public bool HaySeleccion => Seleccion is not null;

    /// <summary>Pedido abierto de la mesa seleccionada (o null si no hay cuenta).</summary>
    private Pedido? _pedidoActual;

    [ObservableProperty] private string _textoBusqueda = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(TotalCuentaTexto))]
    private decimal _totalCuenta;

    public string TotalCuentaTexto => $"S/ {TotalCuenta:N2}";

    /// <summary>True si hay líneas pendientes de enviar a cocina.</summary>
    [ObservableProperty] private bool _hayPendientesCocina;

    [ObservableProperty] private int _metodoPagoIndex;

    /// <summary>Panel de cobro visible (diálogo simple de método de pago).</summary>
    [ObservableProperty] private bool _cobroVisible;

    [ObservableProperty] private decimal _pagaCon;

    // ------------------------------------------------------------------
    // Diálogo de personalización (rubro comida) — reutiliza los VMs del Cobro
    // ------------------------------------------------------------------

    [ObservableProperty] private bool _personalizarVisible;
    private ProductoItemViewModel? _personalizandoProducto;
    [ObservableProperty] private string _personalizarTitulo = "";
    [ObservableProperty] private bool _personalizarPermiteNota;
    [ObservableProperty] private string _personalizarNota = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PersonalizarTotalTexto))]
    private int _personalizarCantidad = 1;

    public ObservableCollection<GrupoPersonalizacionVM> PersonalizarGrupos { get; } = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PersonalizarPrecioTexto))]
    [NotifyPropertyChangedFor(nameof(PersonalizarTotalTexto))]
    private decimal _personalizarPrecioUnitario;

    public string PersonalizarPrecioTexto => $"S/ {PersonalizarPrecioUnitario:N2}";
    public string PersonalizarTotalTexto =>
        $"S/ {(PersonalizarPrecioUnitario * (PersonalizarCantidad < 1 ? 1 : PersonalizarCantidad)):N2}";

    // ------------------------------------------------------------------
    // Editor de mesa (alta / edición / baja)
    // ------------------------------------------------------------------

    [ObservableProperty] private bool _editorVisible;
    [ObservableProperty] private Guid _editandoId;
    private EstadoMesa _editandoEstado = EstadoMesa.Libre;
    [ObservableProperty] private string _edNumero = "";
    [ObservableProperty] private string _edZona = "";
    [ObservableProperty] private int _edCapacidad = 4;
    [ObservableProperty] private string _edNotas = "";
    [ObservableProperty] private string _tituloEditor = "Nueva mesa";

    /// <summary>Constructor de DISEÑO.</summary>
    public MesasViewModel()
    {
        _mesasCards.Add(MesaCardVM.Mock("1", "Salón", 4, EstadoMesa.Libre));
        _mesasCards.Add(MesaCardVM.Mock("2", "Salón", 2, EstadoMesa.Ocupada, 48.50m));
        _mesasCards.Add(MesaCardVM.Mock("T1", "Terraza", 6, EstadoMesa.PorCobrar, 120m));
        MesasView = CrearVistaAgrupada();
        ProductosView = CollectionViewSource.GetDefaultView(_productosCatalogo);
        ProductosView.Filter = FiltrarProducto;
        TotalMesas = _mesasCards.Count;
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public MesasViewModel(
        IMesaRepository mesas,
        IProductoRepository productos,
        IVentaRepository ventas,
        ICajaRepository cajas,
        ITicketPrinter impresora,
        IConfiguracionStore config,
        SesionActual? sesion = null)
    {
        _mesas = mesas;
        _productos = productos;
        _ventas = ventas;
        _cajas = cajas;
        _impresora = impresora;
        _config = config;
        _sesion = sesion;

        MesasView = CrearVistaAgrupada();
        ProductosView = CollectionViewSource.GetDefaultView(_productosCatalogo);
        ProductosView.Filter = FiltrarProducto;
    }

    private ICollectionView CrearVistaAgrupada()
    {
        var v = CollectionViewSource.GetDefaultView(_mesasCards);
        v.GroupDescriptions.Add(new PropertyGroupDescription(nameof(MesaCardVM.Zona)));
        v.SortDescriptions.Add(new SortDescription(nameof(MesaCardVM.Zona), ListSortDirection.Ascending));
        v.SortDescriptions.Add(new SortDescription(nameof(MesaCardVM.Numero), ListSortDirection.Ascending));
        return v;
    }

    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_mesas is null) return;

        // Catálogo (una sola vez): productos para la cuenta.
        if (_productosCatalogo.Count == 0 && _productos is not null)
        {
            foreach (var p in await _productos.BuscarAsync(null, ct))
                _productosCatalogo.Add(ProductoItemViewModel.Desde(p));
            ProductosView.Refresh();
        }

        var idSel = Seleccion?.Id;
        _mesasCards.Clear();
        foreach (var m in await _mesas.ListarMesasAsync(true, ct))
        {
            decimal total = 0m;
            if (m.Estado is EstadoMesa.Ocupada or EstadoMesa.PorCobrar)
            {
                var ped = await _mesas.ObtenerPedidoAbiertoAsync(m.Id, ct);
                total = ped?.Total ?? 0m;
            }
            _mesasCards.Add(MesaCardVM.Desde(m, total));
        }
        TotalMesas = _mesasCards.Count;
        Libres = _mesasCards.Count(m => m.Estado == EstadoMesa.Libre);
        Ocupadas = _mesasCards.Count(m => m.Estado is EstadoMesa.Ocupada or EstadoMesa.PorCobrar);
        MesasView.Refresh();

        // Re-seleccionar (refresca la cuenta si seguía abierta).
        if (idSel is { } sid)
        {
            var card = _mesasCards.FirstOrDefault(c => c.Id == sid);
            if (card is not null) await AbrirCuentaAsync(card); else Seleccion = null;
        }
    }

    // ------------------------------------------------------------------
    // Abrir / atender cuenta de una mesa
    // ------------------------------------------------------------------

    [RelayCommand]
    private async Task SeleccionarMesa(MesaCardVM? card) => await AbrirCuentaAsync(card);

    /// <summary>
    /// Clic en una mesa: si está Libre crea un pedido nuevo (mesa→Ocupada); si ya
    /// está Ocupada/PorCobrar recupera su pedido abierto. Deja lista la cuenta.
    /// </summary>
    private async Task AbrirCuentaAsync(MesaCardVM? card)
    {
        CobroVisible = false;
        PagaCon = 0;
        Seleccion = card;
        _pedidoActual = null;
        LineasCuenta.Clear();
        TotalCuenta = 0;
        HayPendientesCocina = false;
        if (card is null || _mesas is null) return;

        var abierto = await _mesas.ObtenerPedidoAbiertoAsync(card.Id);
        if (abierto is null)
        {
            // Mesa libre: crear una nueva comanda.
            var mozo = _sesion?.NombreMostrado;
            _pedidoActual = new Pedido
            {
                MesaId = card.Id,
                NumeroMesa = card.Numero,
                Numero = "P-" + DateTime.Now.ToString("yyMMdd-HHmmss"),
                Estado = EstadoPedido.Abierta,
                Mozo = string.IsNullOrWhiteSpace(mozo) ? "Mozo" : mozo!,
                Comensales = card.Capacidad,
                FechaApertura = DateTime.Now,
                Total = 0m
            };
            await _mesas.GuardarPedidoAsync(_pedidoActual);
            await _mesas.CambiarEstadoMesaAsync(card.Id, EstadoMesa.Ocupada);
        }
        else
        {
            _pedidoActual = abierto;
        }

        await RefrescarCuentaAsync();
    }

    /// <summary>Recarga las líneas y el total del pedido actual desde BD.</summary>
    private async Task RefrescarCuentaAsync()
    {
        if (_mesas is null || _pedidoActual is null) return;
        LineasCuenta.Clear();
        foreach (var l in await _mesas.ListarLineasAsync(_pedidoActual.Id))
            LineasCuenta.Add(PedidoLineaVM.Desde(l));
        TotalCuenta = await _mesas.TotalPedidoAsync(_pedidoActual.Id);
        HayPendientesCocina = LineasCuenta.Any(l => !l.EnviadoCocina);

        // Mantener el cache del total en la cabecera del pedido.
        if (_pedidoActual.Total != TotalCuenta)
        {
            _pedidoActual.Total = TotalCuenta;
            await _mesas.GuardarPedidoAsync(_pedidoActual);
        }
    }

    // ------------------------------------------------------------------
    // Agregar productos a la cuenta
    // ------------------------------------------------------------------

    partial void OnTextoBusquedaChanged(string value) => ProductosView.Refresh();

    private bool FiltrarProducto(object obj)
    {
        if (obj is not ProductoItemViewModel p) return false;
        if (string.IsNullOrWhiteSpace(TextoBusqueda)) return true;
        return p.Nombre.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase)
               || p.Codigo.Contains(TextoBusqueda, StringComparison.OrdinalIgnoreCase);
    }

    [RelayCommand]
    private async Task ElegirProducto(ProductoItemViewModel? producto)
    {
        if (producto is null || _pedidoActual is null) return;

        if (producto.EstaVencido)
        {
            MensajeEstado = $"«{producto.Nombre}» está vencido: no se puede vender.";
            return;
        }

        // Producto personalizable (comida): abre el diálogo de modificadores.
        if (producto.TienePersonalizacion)
        {
            AbrirPersonalizacion(producto);
            return;
        }

        await AgregarLineaAsync(producto, producto.Nombre, null, producto.Precio, 1);
    }

    /// <summary>
    /// Persiste una línea en el pedido con validación de stock (no permite pedir más
    /// unidades de las que hay). Refresca la cuenta. Devuelve false si el stock no alcanza.
    /// </summary>
    private async Task<bool> AgregarLineaAsync(ProductoItemViewModel producto, string descripcion,
        string? nota, decimal precioUnitario, int cantidad)
    {
        if (_mesas is null || _pedidoActual is null) return false;

        // Validación de stock: suma lo que ya está en la cuenta para este producto.
        if (producto.ControlaStock && producto.ProductoId != Guid.Empty)
        {
            var enCuenta = LineasCuenta.Where(l => l.ProductoId == producto.ProductoId).Sum(l => l.Cantidad);
            if (enCuenta + cantidad > producto.StockActual)
            {
                MensajeEstado = producto.StockActual <= 0
                    ? $"«{producto.Nombre}» está agotado. Reabastece en Inventario."
                    : $"Solo quedan {producto.StockActual:0.###} de «{producto.Nombre}» en stock.";
                return false;
            }
        }

        var cant = cantidad < 1 ? 1 : cantidad;
        var linea = new PedidoLinea
        {
            PedidoId = _pedidoActual.Id,
            ProductoId = producto.ProductoId,
            Descripcion = descripcion,
            Nota = string.IsNullOrWhiteSpace(nota) ? null : nota!.Trim(),
            Cantidad = cant,
            PrecioUnitario = precioUnitario,
            Importe = decimal.Round(cant * precioUnitario, 2),
            EnviadoCocina = false
        };
        await _mesas.AgregarLineaAsync(linea);
        await RefrescarCuentaAsync();
        MensajeEstado = $"Agregado: {descripcion}.";
        return true;
    }

    [RelayCommand]
    private async Task IncrementarLinea(PedidoLineaVM? linea)
    {
        if (linea is null || _mesas is null || _pedidoActual is null) return;
        var producto = _productosCatalogo.FirstOrDefault(p => p.ProductoId == linea.ProductoId);

        // Validación de stock antes de sumar una unidad más.
        if (producto is not null && producto.ControlaStock && producto.ProductoId != Guid.Empty)
        {
            var enCuenta = LineasCuenta.Where(l => l.ProductoId == linea.ProductoId).Sum(l => l.Cantidad);
            if (enCuenta + 1 > producto.StockActual)
            {
                MensajeEstado = $"No hay más stock de «{producto.Nombre}».";
                return;
            }
        }

        // Sumar una unidad = otra línea idéntica (misma descripción/nota) o crear.
        var nuevaCant = linea.Cantidad + 1;
        var actualizada = new PedidoLinea
        {
            Id = linea.Id,
            PedidoId = _pedidoActual.Id,
            ProductoId = linea.ProductoId,
            Descripcion = linea.Descripcion,
            Nota = linea.Nota,
            Cantidad = nuevaCant,
            PrecioUnitario = linea.PrecioUnitario,
            Importe = decimal.Round(nuevaCant * linea.PrecioUnitario, 2),
            // Al sumar unidades, la línea vuelve a "pendiente" para que la cocina
            // reciba la nueva cantidad en la próxima comanda.
            EnviadoCocina = false
        };
        // Quitar y volver a agregar preserva el Id (upsert de línea vía repo).
        await _mesas.QuitarLineaAsync(linea.Id);
        await _mesas.AgregarLineaAsync(actualizada);
        await RefrescarCuentaAsync();
    }

    [RelayCommand]
    private async Task QuitarLinea(PedidoLineaVM? linea)
    {
        if (linea is null || _mesas is null) return;
        await _mesas.QuitarLineaAsync(linea.Id);
        await RefrescarCuentaAsync();
    }

    // ------------------------------------------------------------------
    // Diálogo de personalización (rubro comida)
    // ------------------------------------------------------------------

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
            PersonalizarGrupos.Add(new GrupoPersonalizacionVM(g) { AlCambiarSeleccion = RecalcularPersonalizacion });

        RecalcularPersonalizacion();
        PersonalizarVisible = true;
    }

    partial void OnPersonalizarCantidadChanged(int value) => OnPropertyChanged(nameof(PersonalizarTotalTexto));

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
    private async Task ConfirmarPersonalizacion()
    {
        var producto = _personalizandoProducto;
        if (producto is null) { PersonalizarVisible = false; return; }

        var faltante = PersonalizarGrupos.FirstOrDefault(g => !g.EsValido);
        if (faltante is not null)
        {
            MensajeEstado = $"Elige una opción en «{faltante.Nombre}».";
            return;
        }

        // Descripción de la línea: base + opciones elegidas (la nota va en su campo).
        var elegidas = PersonalizarGrupos
            .SelectMany(g => g.Elegidas)
            .Select(o => o.Nombre)
            .ToList();

        var descripcion = producto.Nombre;
        if (elegidas.Count > 0)
            descripcion += " (" + string.Join(", ", elegidas) + ")";

        var nota = PersonalizarNota?.Trim();
        var cant = PersonalizarCantidad < 1 ? 1 : PersonalizarCantidad;

        if (!await AgregarLineaAsync(producto, descripcion, nota, PersonalizarPrecioUnitario, cant))
            return; // stock insuficiente: mantiene el diálogo con el aviso puesto

        PersonalizarVisible = false;
        _personalizandoProducto = null;
        PersonalizarGrupos.Clear();
    }

    // ------------------------------------------------------------------
    // Enviar comanda a cocina
    // ------------------------------------------------------------------

    [RelayCommand]
    private async Task EnviarCocina()
    {
        if (_mesas is null || _pedidoActual is null) return;
        var pendientes = LineasCuenta.Where(l => !l.EnviadoCocina).ToList();
        if (pendientes.Count == 0) { MensajeEstado = "No hay ítems nuevos para enviar a cocina."; return; }

        // Marcar enviadas (esencial: aunque la impresión falle, quedan registradas).
        await _mesas.MarcarLineasEnviadasAsync(_pedidoActual.Id);

        // Comanda best-effort SIN precios: mesa, mozo, hora e ítems + notas.
        // ITicketPrinter no expone un método de comanda; se reutiliza el ticket de
        // venta con importes en 0 y estado "comanda" para no imprimir montos.
        var impreso = false;
        if (_impresora is not null)
        {
            try
            {
                var comanda = new Venta
                {
                    Numero = $"COMANDA Mesa {_pedidoActual.NumeroMesa} · {_pedidoActual.Mozo}",
                    FechaHora = DateTime.Now,
                    MetodoPago = MetodoPago.Efectivo,
                    Estado = EstadoVenta.Completada,
                    SubTotal = 0m, Igv = 0m, Total = 0m
                };
                foreach (var l in pendientes)
                {
                    var desc = l.Descripcion;
                    if (!string.IsNullOrWhiteSpace(l.Nota)) desc += "  >> " + l.Nota;
                    comanda.Detalles.Add(new DetalleVenta
                    {
                        ProductoId = l.ProductoId,
                        DescripcionProducto = desc,
                        Cantidad = l.Cantidad,
                        PrecioUnitario = 0m,
                        Importe = 0m
                    });
                }
                var res = await _impresora.ImprimirTicketVentaAsync(comanda);
                impreso = res.Exito;
            }
            catch { /* comanda es best-effort */ }
        }

        await RefrescarCuentaAsync();
        MensajeEstado = impreso
            ? $"Comanda enviada a cocina ({pendientes.Count} ítem(s))."
            : $"Comanda marcada ({pendientes.Count} ítem(s)). Impresión no disponible.";
    }

    // ------------------------------------------------------------------
    // Cobrar mesa
    // ------------------------------------------------------------------

    [RelayCommand]
    private void IniciarCobro()
    {
        if (_pedidoActual is null || LineasCuenta.Count == 0)
        {
            MensajeEstado = "La cuenta está vacía.";
            return;
        }
        MetodoPagoIndex = 0;
        PagaCon = 0;
        CobroVisible = true;
    }

    [RelayCommand]
    private void CancelarCobro() => CobroVisible = false;

    [RelayCommand]
    private async Task ConfirmarCobro()
    {
        if (_mesas is null || _ventas is null || _cajas is null || _pedidoActual is null || Seleccion is null) return;
        if (LineasCuenta.Count == 0) { MensajeEstado = "La cuenta está vacía."; return; }

        try
        {
            var caja = await _cajas.ObtenerCajaAbiertaAsync();
            if (caja is null) { MensajeEstado = "No hay caja abierta. Abre la caja antes de cobrar."; return; }

            var lineas = await _mesas.ListarLineasAsync(_pedidoActual.Id);
            var total = lineas.Sum(l => l.Importe);
            var subtotal = decimal.Round(total / (1 + TasaIgv), 2);
            var igv = decimal.Round(total - subtotal, 2);

            var venta = new Venta
            {
                Numero = "M-" + DateTime.Now.ToString("yyMMdd-HHmmss"),
                CajaId = caja.Id,
                FechaHora = DateTime.Now,
                MetodoPago = IndiceAMetodoPago(MetodoPagoIndex),
                Estado = EstadoVenta.Completada,
                SubTotal = subtotal,
                Igv = igv,
                Total = total,
                MontoRecibido = PagaCon > 0 ? PagaCon : null,
                OrigenCajaId = caja.OrigenCajaId
            };

            foreach (var l in lineas)
                venta.Detalles.Add(new DetalleVenta
                {
                    ProductoId = l.ProductoId,
                    DescripcionProducto = l.Descripcion,
                    Cantidad = l.Cantidad,
                    PrecioUnitario = l.PrecioUnitario,
                    Descuento = 0m,
                    Importe = l.Importe,
                    OrigenCajaId = caja.OrigenCajaId
                });

            // Persistencia atómica (descuenta stock de los productos reales + outbox).
            await _ventas.RegistrarAsync(venta);

            // Solo el efectivo entra al arqueo de caja.
            if (venta.MetodoPago == MetodoPago.Efectivo)
                await _cajas.RegistrarMovimientoAsync(new MovimientoCaja
                {
                    CajaId = caja.Id,
                    Tipo = TipoMovimientoCaja.Ingreso,
                    Monto = venta.Total,
                    Concepto = $"Mesa {_pedidoActual.NumeroMesa} ({venta.Numero})",
                    FechaHora = DateTime.Now,
                    OrigenCajaId = caja.OrigenCajaId
                });

            if (_impresora is not null)
                try { await _impresora.ImprimirTicketVentaAsync(venta); } catch { /* ticket secundario */ }

            // Cerrar el pedido y liberar la mesa.
            _pedidoActual.Estado = EstadoPedido.Cobrada;
            _pedidoActual.FechaCierre = DateTime.Now;
            _pedidoActual.VentaId = venta.Id;
            _pedidoActual.Total = total;
            await _mesas.GuardarPedidoAsync(_pedidoActual);
            await _mesas.CambiarEstadoMesaAsync(Seleccion.Id, EstadoMesa.Libre);

            MensajeEstado = $"Mesa {_pedidoActual.NumeroMesa} cobrada: S/ {total:N2} ({venta.Numero}).";
            CobroVisible = false;
            Seleccion = null;
            _pedidoActual = null;
            LineasCuenta.Clear();
            TotalCuenta = 0;
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo cobrar la mesa: {ex.Message}"; }
    }

    // ------------------------------------------------------------------
    // Editor de mesa
    // ------------------------------------------------------------------

    [RelayCommand]
    private void NuevaMesa()
    {
        TituloEditor = "Nueva mesa";
        EditandoId = Guid.Empty;
        _editandoEstado = EstadoMesa.Libre;
        EdNumero = ""; EdZona = "Salón"; EdCapacidad = 4; EdNotas = "";
        EditorVisible = true;
    }

    [RelayCommand]
    private void EditarMesa(MesaCardVM? card)
    {
        if (card is null) return;
        TituloEditor = $"Editar mesa {card.Numero}";
        EditandoId = card.Id;
        _editandoEstado = card.Estado;
        EdNumero = card.Numero;
        EdZona = card.Zona;
        EdCapacidad = card.Capacidad;
        EdNotas = card.Notas ?? "";
        EditorVisible = true;
    }

    [RelayCommand]
    private void CancelarEditor() => EditorVisible = false;

    [RelayCommand]
    private async Task GuardarMesa()
    {
        if (_mesas is null) { EditorVisible = false; return; }
        if (string.IsNullOrWhiteSpace(EdNumero)) { MensajeEstado = "El número/nombre de la mesa es obligatorio."; return; }
        try
        {
            var mesa = new Mesa
            {
                Id = EditandoId == Guid.Empty ? Guid.NewGuid() : EditandoId,
                Numero = EdNumero.Trim(),
                Zona = string.IsNullOrWhiteSpace(EdZona) ? null : EdZona.Trim(),
                Capacidad = EdCapacidad < 1 ? 1 : EdCapacidad,
                Estado = _editandoEstado,
                Notas = string.IsNullOrWhiteSpace(EdNotas) ? null : EdNotas.Trim(),
                Activa = true
            };
            await _mesas.GuardarMesaAsync(mesa);
            EditorVisible = false;
            MensajeEstado = $"Mesa {mesa.Numero} guardada.";
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo guardar la mesa: {ex.Message}"; }
    }

    [RelayCommand]
    private async Task EliminarMesa(MesaCardVM? card)
    {
        if (_mesas is null || card is null) return;
        if (card.Estado is EstadoMesa.Ocupada or EstadoMesa.PorCobrar)
        {
            MensajeEstado = "No puedes eliminar una mesa con cuenta abierta.";
            return;
        }
        try
        {
            await _mesas.DesactivarMesaAsync(card.Id);
            MensajeEstado = $"Mesa {card.Numero} eliminada.";
            if (Seleccion?.Id == card.Id) { Seleccion = null; _pedidoActual = null; LineasCuenta.Clear(); }
            await CargarAsync();
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo eliminar: {ex.Message}"; }
    }

    private static MetodoPago IndiceAMetodoPago(int i) => i switch
    {
        1 => MetodoPago.BilleteraDigital,
        2 => MetodoPago.Tarjeta,
        _ => MetodoPago.Efectivo
    };
}

/// <summary>Tarjeta de una mesa en el mapa del salón (mapa + editor).</summary>
public partial class MesaCardVM : ObservableObject
{
    public Guid Id { get; init; }
    public string Numero { get; init; } = "";
    public string Zona { get; init; } = "Salón";
    public int Capacidad { get; init; }
    public string? Notas { get; init; }
    public EstadoMesa Estado { get; init; }
    public string EstadoTexto { get; init; } = "";

    /// <summary>Total actual de la cuenta (solo si la mesa está ocupada/por cobrar).</summary>
    public decimal TotalActual { get; init; }

    public bool TieneCuenta => Estado is EstadoMesa.Ocupada or EstadoMesa.PorCobrar;
    public string TotalTexto => TieneCuenta ? $"S/ {TotalActual:N2}" : "";

    public static MesaCardVM Desde(Mesa m, decimal total) => new()
    {
        Id = m.Id, Numero = m.Numero, Zona = m.ZonaAgrupacion, Capacidad = m.Capacidad,
        Notas = m.Notas, Estado = m.Estado, EstadoTexto = TextoEstado(m.Estado), TotalActual = total
    };

    public static MesaCardVM Mock(string numero, string zona, int cap, EstadoMesa estado, decimal total = 0m) => new()
    {
        Id = Guid.NewGuid(), Numero = numero, Zona = zona, Capacidad = cap,
        Estado = estado, EstadoTexto = TextoEstado(estado), TotalActual = total
    };

    private static string TextoEstado(EstadoMesa e) => e switch
    {
        EstadoMesa.Libre => "Libre",
        EstadoMesa.Ocupada => "Ocupada",
        EstadoMesa.PorCobrar => "Por cobrar",
        EstadoMesa.Reservada => "Reservada",
        _ => ""
    };
}

/// <summary>Línea de la comanda mostrada en la cuenta de la mesa.</summary>
public sealed class PedidoLineaVM
{
    public Guid Id { get; init; }
    public Guid ProductoId { get; init; }
    public string Descripcion { get; init; } = "";
    public string? Nota { get; init; }
    public decimal Cantidad { get; init; }
    public decimal PrecioUnitario { get; init; }
    public decimal Importe { get; init; }
    public bool EnviadoCocina { get; init; }

    public bool TieneNota => !string.IsNullOrWhiteSpace(Nota);
    public string CantidadTexto => Cantidad == Math.Truncate(Cantidad) ? ((long)Cantidad).ToString() : Cantidad.ToString("0.###");

    public static PedidoLineaVM Desde(PedidoLinea l) => new()
    {
        Id = l.Id, ProductoId = l.ProductoId, Descripcion = l.Descripcion, Nota = l.Nota,
        Cantidad = l.Cantidad, PrecioUnitario = l.PrecioUnitario, Importe = l.Importe,
        EnviadoCocina = l.EnviadoCocina
    };
}
