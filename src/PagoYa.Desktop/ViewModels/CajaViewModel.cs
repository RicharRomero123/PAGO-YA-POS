using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Apertura / cierre de caja (arqueo) real contra <see cref="ICajaRepository"/>
/// y <see cref="IVentaRepository"/>.
///
/// Runtime: al cargar consulta la caja abierta, sus movimientos y las ventas de
/// la sesión para calcular esperado vs contado. Diseño: el constructor sin
/// parámetros usa mock para el render en modo diseñador.
/// </summary>
public partial class CajaViewModel : ObservableObject
{
    private readonly ICajaRepository? _cajas;
    private readonly IVentaRepository? _ventas;

    private Caja? _cajaActual;

    [ObservableProperty] private bool _cajaAbierta = true;
    [ObservableProperty] private string _cajero = "María Quispe";
    [ObservableProperty] private string _horaApertura = "08:12 a. m.";
    [ObservableProperty] private decimal _montoInicial = 100.00m;
    [ObservableProperty] private decimal _ventasEfectivo = 342.50m;
    [ObservableProperty] private decimal _ventasDigital = 218.00m;
    [ObservableProperty] private decimal _ventasTarjeta = 95.00m;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Diferencia))]
    private decimal _montoContado;

    [ObservableProperty] private string _mensajeEstado = "";

    // Para abrir caja (formulario).
    [ObservableProperty] private decimal _montoAperturaNueva = 100m;
    [ObservableProperty] private string _cajeroNuevo = "";

    public decimal EsperadoEnCaja => MontoInicial + VentasEfectivo;
    public decimal Diferencia => MontoContado - EsperadoEnCaja;

    public ObservableCollection<MovimientoCajaItem> Movimientos { get; } = new();

    // --- Historial de cajas por fechas ---
    [ObservableProperty] private DateTime _historialDesde = DateTime.Today.AddDays(-7);
    [ObservableProperty] private DateTime _historialHasta = DateTime.Today;
    [ObservableProperty] private bool _historialVacio;

    public ObservableCollection<CajaHistorialItem> Historial { get; } = new();

    /// <summary>Constructor de DISEÑO: mock para el diseñador.</summary>
    public CajaViewModel()
    {
        Movimientos.Add(new("08:12", "Apertura", "Fondo inicial", 100.00m));
        Movimientos.Add(new("09:34", "Venta", "Nota #0142 (Efectivo)", 23.50m));
        Movimientos.Add(new("10:05", "Venta", "Nota #0143 (Yape)", 45.00m));
        Movimientos.Add(new("11:20", "Egreso", "Compra de bolsas", -8.00m));
        Movimientos.Add(new("12:47", "Venta", "Nota #0144 (Efectivo)", 61.80m));

        Historial.Add(new("26/08/2026", "08:05", "20:14", "María Quispe", 100m, 742.50m, 0m, "Cerrada", false));
        Historial.Add(new("25/08/2026", "08:10", "20:02", "José Torres", 100m, 655.00m, -3.50m, "Cerrada", false));
        Historial.Add(new("24/08/2026", "08:00", "—", "María Quispe", 100m, null, null, "Abierta", true));
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public CajaViewModel(ICajaRepository cajas, IVentaRepository ventas)
    {
        _cajas = cajas;
        _ventas = ventas;
    }

    /// <summary>Carga el estado real de la caja abierta (o marca cerrada si no hay).</summary>
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_cajas is null || _ventas is null) return;

        _cajaActual = await _cajas.ObtenerCajaAbiertaAsync(ct);
        if (_cajaActual is null)
        {
            CajaAbierta = false;
            Movimientos.Clear();
            MontoInicial = 0;
            VentasEfectivo = VentasDigital = VentasTarjeta = 0;
            MensajeEstado = "No hay una caja abierta.";
            OnPropertyChanged(nameof(EsperadoEnCaja));
            OnPropertyChanged(nameof(Diferencia));
            await CargarHistorialAsync(ct);
            return;
        }

        CajaAbierta = true;
        Cajero = _cajaActual.Cajero;
        HoraApertura = _cajaActual.FechaApertura.ToString("hh:mm tt");
        MontoInicial = _cajaActual.MontoApertura;

        // Agregados de ventas de la sesión por método de pago.
        var ventas = await _ventas.ListarPorCajaAsync(_cajaActual.Id, ct);
        var vigentes = ventas.Where(v => v.Estado == EstadoVenta.Completada).ToList();
        VentasEfectivo = vigentes.Where(v => v.MetodoPago == MetodoPago.Efectivo).Sum(v => v.Total);
        VentasDigital = vigentes.Where(v => v.MetodoPago == MetodoPago.BilleteraDigital).Sum(v => v.Total);
        VentasTarjeta = vigentes.Where(v => v.MetodoPago == MetodoPago.Tarjeta).Sum(v => v.Total);

        // Timeline de movimientos.
        var movs = await _cajas.ListarMovimientosAsync(_cajaActual.Id, ct);
        Movimientos.Clear();
        foreach (var m in movs)
        {
            var signo = m.Tipo is TipoMovimientoCaja.Egreso or TipoMovimientoCaja.Retiro ? -1m : 1m;
            Movimientos.Add(new MovimientoCajaItem(
                m.FechaHora.ToString("HH:mm"),
                NombreTipo(m.Tipo),
                m.Concepto,
                signo * m.Monto));
        }

        OnPropertyChanged(nameof(EsperadoEnCaja));
        OnPropertyChanged(nameof(Diferencia));

        await CargarHistorialAsync(ct);
    }

    /// <summary>Carga el historial de sesiones de caja del rango de fechas elegido.</summary>
    [RelayCommand]
    private async Task CargarHistorialAsync(CancellationToken ct = default)
    {
        if (_cajas is null) return;
        try
        {
            var sesiones = await _cajas.ListarSesionesAsync(
                DateOnly.FromDateTime(HistorialDesde), DateOnly.FromDateTime(HistorialHasta), ct);

            Historial.Clear();
            foreach (var s in sesiones)
            {
                var abierta = s.Estado == EstadoCaja.Abierta;
                Historial.Add(new CajaHistorialItem(
                    s.FechaApertura.ToString("dd/MM/yyyy"),
                    s.FechaApertura.ToString("HH:mm"),
                    s.FechaCierre?.ToString("HH:mm") ?? "—",
                    s.Cajero,
                    s.MontoApertura,
                    s.MontoCierre,
                    s.Diferencia,
                    abierta ? "Abierta" : "Cerrada",
                    abierta));
            }
            HistorialVacio = Historial.Count == 0;
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo cargar el historial: {ex.Message}"; }
    }

    [RelayCommand]
    private void RegistrarConteo()
    {
        // El binding ya recalcula Diferencia; forzamos notificación por claridad.
        OnPropertyChanged(nameof(Diferencia));
    }

    [RelayCommand]
    private async Task AbrirCajaAsync()
    {
        if (_cajas is null) { CajaAbierta = true; return; }
        try
        {
            var caja = new Caja
            {
                Nombre = "Caja 1",
                Cajero = string.IsNullOrWhiteSpace(CajeroNuevo) ? "Cajero" : CajeroNuevo.Trim(),
                Estado = EstadoCaja.Abierta,
                MontoApertura = MontoAperturaNueva,
                FechaApertura = DateTime.Now
            };
            await _cajas.AbrirCajaAsync(caja);
            MensajeEstado = "Caja abierta.";
            await CargarAsync();
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo abrir la caja: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task CerrarCajaAsync()
    {
        if (_cajas is null || _cajaActual is null)
        {
            CajaAbierta = false;
            return;
        }
        try
        {
            _cajaActual.MontoCierre = MontoContado;
            _cajaActual.Diferencia = MontoContado - EsperadoEnCaja;
            _cajaActual.FechaCierre = DateTime.Now;
            await _cajas.CerrarCajaAsync(_cajaActual);
            CajaAbierta = false;
            MensajeEstado = $"Caja cerrada. Diferencia: S/ {_cajaActual.Diferencia:N2}";
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo cerrar la caja: {ex.Message}";
        }
    }

    private static string NombreTipo(TipoMovimientoCaja t) => t switch
    {
        TipoMovimientoCaja.AperturaFondo => "Apertura",
        TipoMovimientoCaja.Ingreso => "Ingreso",
        TipoMovimientoCaja.Egreso => "Egreso",
        TipoMovimientoCaja.Retiro => "Retiro",
        _ => t.ToString()
    };
}

/// <summary>Fila del arqueo (para la tabla de movimientos).</summary>
public sealed record MovimientoCajaItem(string Hora, string Tipo, string Detalle, decimal Monto);

/// <summary>Fila del historial de sesiones de caja (por fechas).</summary>
public sealed record CajaHistorialItem(
    string Fecha, string Apertura, string Cierre, string Cajero,
    decimal Fondo, decimal? Contado, decimal? Diferencia, string Estado, bool Abierta)
{
    private static readonly System.Globalization.CultureInfo Pe =
        System.Globalization.CultureInfo.GetCultureInfo("es-PE");
    private static string Fmt(decimal m) => "S/ " + m.ToString("N2", Pe);

    public string FondoTexto => Fmt(Fondo);
    public string ContadoTexto => Contado is null ? "—" : Fmt(Contado.Value);
    public string DiferenciaTexto => Diferencia is null ? "—" : Fmt(Diferencia.Value);

    public bool Cuadrada => Diferencia == 0m;
    public bool Faltante => Diferencia is < 0m;
    public bool Sobrante => Diferencia is > 0m;
}
