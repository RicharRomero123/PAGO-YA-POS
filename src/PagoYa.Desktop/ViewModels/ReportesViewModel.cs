using System.Collections.ObjectModel;
using System.IO;
using ClosedXML.Excel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PagoYa.Core.Contratos;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios.Impresion;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Reportes del día: tarjetas de métricas + últimas ventas + ranking de
/// productos + desglose por método de pago.
///
/// Runtime: agrega datos reales desde <see cref="IReportesRepository"/> para la
/// fecha LOCAL de hoy. Diseño: el constructor sin parámetros siembra mock para
/// el render del diseñador (d:DataContext). Reportes móviles/nube requieren el
/// flag cloud_sync (fuera del tier Base).
/// </summary>
public partial class ReportesViewModel : ObservableObject
{
    private static readonly string[] Meses =
    {
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
    };

    private readonly IReportesRepository? _repo;
    private readonly IVentaRepository? _ventas;
    private readonly IVistaPreviaTicket? _preview;

    [ObservableProperty] private string _fecha = "";
    [ObservableProperty] private decimal _totalVendido;
    [ObservableProperty] private int _cantidadVentas;
    [ObservableProperty] private decimal _ticketPromedio;
    [ObservableProperty] private decimal _productosVendidos;
    [ObservableProperty] private bool _sinVentas;
    [ObservableProperty] private string _mensajeEstado = "";

    // Rango para exportar a Excel (por defecto: hoy).
    [ObservableProperty] private DateTime _exportDesde = DateTime.Today;
    [ObservableProperty] private DateTime _exportHasta = DateTime.Today;

    public ObservableCollection<VentaResumenItem> UltimasVentas { get; } = new();
    public ObservableCollection<TopProductoItem> MasVendidos { get; } = new();
    public ObservableCollection<MetodoPagoItem> PorMetodo { get; } = new();

    /// <summary>Constructor de DISEÑO: siembra mock. No toca BD.</summary>
    public ReportesViewModel()
    {
        Fecha = "Hoy, 25 de agosto de 2026";
        TotalVendido = 655.50m;
        CantidadVentas = 47;
        TicketPromedio = 13.95m;
        ProductosVendidos = 213;

        UltimasVentas.Add(new VentaResumenItem(Guid.NewGuid(), "Nota #0147", "12:47 p. m.", "Efectivo", 61.80m, "Pagado", false));
        UltimasVentas.Add(new VentaResumenItem(Guid.NewGuid(), "Nota #0146", "12:31 p. m.", "Yape / Plin", 18.50m, "Pagado", false));
        UltimasVentas.Add(new VentaResumenItem(Guid.NewGuid(), "Nota #0145", "12:10 p. m.", "Tarjeta", 95.00m, "Pagado", false));
        UltimasVentas.Add(new VentaResumenItem(Guid.NewGuid(), "Nota #0144", "11:58 a. m.", "Efectivo", 7.20m, "Anulado", true));

        MasVendidos.Add(new TopProductoItem("Pan Frances (und)", 128, 38.40m));
        MasVendidos.Add(new TopProductoItem("Inca Kola 500ml", 34, 119.00m));
        MasVendidos.Add(new TopProductoItem("Leche Gloria Tarro", 21, 88.20m));

        PorMetodo.Add(new MetodoPagoItem("Efectivo", 320.00m, 28));
        PorMetodo.Add(new MetodoPagoItem("Yape / Plin", 210.50m, 12));
        PorMetodo.Add(new MetodoPagoItem("Tarjeta", 125.00m, 7));
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public ReportesViewModel(IReportesRepository repo, IVentaRepository ventas, IVistaPreviaTicket preview)
    {
        _repo = repo;
        _ventas = ventas;
        _preview = preview;
        Fecha = TextoFecha(DateTime.Now);
    }

    /// <summary>Recarga el reporte de HOY (fecha local del POS).</summary>
    [RelayCommand]
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_repo is null) return;

        var hoy = DateTime.Now;
        Fecha = TextoFecha(hoy);

        try
        {
            var r = await _repo.ObtenerReporteDelDiaAsync(DateOnly.FromDateTime(hoy), ct);

            TotalVendido = r.TotalVendido;
            CantidadVentas = r.CantidadVentas;
            TicketPromedio = r.TicketPromedio;
            ProductosVendidos = r.ProductosVendidos;
            SinVentas = r.CantidadVentas == 0;
            MensajeEstado = "";

            UltimasVentas.Clear();
            foreach (var v in r.UltimasVentas)
                UltimasVentas.Add(new VentaResumenItem(
                    v.Id,
                    v.Numero,
                    v.FechaHora.ToString("hh:mm tt").ToLowerInvariant(),
                    EtiquetaMetodo(v.Metodo),
                    v.Total,
                    v.Estado == EstadoVenta.Anulada ? "Anulado" : "Pagado",
                    v.Estado == EstadoVenta.Anulada));

            MasVendidos.Clear();
            foreach (var p in r.MasVendidos)
                MasVendidos.Add(new TopProductoItem(p.Nombre, p.Unidades, p.Total));

            PorMetodo.Clear();
            foreach (var pm in r.PorMetodo)
                PorMetodo.Add(new MetodoPagoItem(EtiquetaMetodo(pm.Metodo), pm.Total, pm.Cantidad));
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo cargar el reporte: {ex.Message}";
        }
    }

    /// <summary>Abre la vista previa del ticket de una venta pasada (desde ahí se puede imprimir).</summary>
    [RelayCommand]
    private async Task VerTicketAsync(VentaResumenItem? item)
    {
        if (item is null || _ventas is null || _preview is null)
        {
            MensajeEstado = "Vista previa no disponible en este entorno.";
            return;
        }
        try
        {
            var venta = await _ventas.ObtenerPorIdAsync(item.Id);
            if (venta is null) { MensajeEstado = "No se encontró la venta."; return; }
            _preview.Mostrar(venta);
        }
        catch (Exception ex) { MensajeEstado = $"Error al abrir la vista previa: {ex.Message}"; }
    }

    /// <summary>Exporta a un archivo Excel real (.xlsx) las ventas del rango elegido.</summary>
    [RelayCommand]
    private async Task ExportarExcelAsync()
    {
        if (_repo is null) return;
        try
        {
            var desde = DateOnly.FromDateTime(ExportDesde);
            var hasta = DateOnly.FromDateTime(ExportHasta);
            if (hasta < desde) (desde, hasta) = (hasta, desde);
            var ventas = await _repo.ListarVentasRangoAsync(desde, hasta);

            var dlg = new SaveFileDialog
            {
                Title = "Exportar ventas a Excel",
                Filter = "Libro de Excel (*.xlsx)|*.xlsx",
                FileName = $"ventas_{desde:yyyyMMdd}_{hasta:yyyyMMdd}.xlsx"
            };
            if (dlg.ShowDialog() != true) return;

            var ruta = dlg.FileName;
            await Task.Run(() => EscribirExcel(ruta, desde, hasta, ventas));
            MensajeEstado = $"Exportadas {ventas.Count} ventas a «{Path.GetFileName(ruta)}».";
        }
        catch (Exception ex) { MensajeEstado = $"No se pudo exportar: {ex.Message}"; }
    }

    /// <summary>Genera el .xlsx con encabezado con estilo, filas de ventas y total.</summary>
    private static void EscribirExcel(string ruta, DateOnly desde, DateOnly hasta, IReadOnlyList<VentaResumen> ventas)
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Ventas");

        // Título
        ws.Cell(1, 1).Value = desde == hasta
            ? $"Ventas del {desde:dd/MM/yyyy}"
            : $"Ventas del {desde:dd/MM/yyyy} al {hasta:dd/MM/yyyy}";
        var titulo = ws.Range(1, 1, 1, 6).Merge();
        titulo.Style.Font.Bold = true;
        titulo.Style.Font.FontSize = 15;
        titulo.Style.Font.FontColor = XLColor.FromHtml("#12233F");

        // Encabezados
        string[] cols = { "Número", "Fecha", "Hora", "Método de pago", "Estado", "Total (S/)" };
        for (int i = 0; i < cols.Length; i++)
            ws.Cell(3, i + 1).Value = cols[i];
        var head = ws.Range(3, 1, 3, cols.Length);
        head.Style.Font.Bold = true;
        head.Style.Font.FontColor = XLColor.White;
        head.Style.Fill.BackgroundColor = XLColor.FromHtml("#F26522");
        head.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        int row = 4;
        decimal total = 0m;
        foreach (var v in ventas)
        {
            bool anulado = v.Estado == EstadoVenta.Anulada;
            if (!anulado) total += v.Total;

            ws.Cell(row, 1).Value = v.Numero;
            ws.Cell(row, 2).Value = v.FechaHora.ToString("dd/MM/yyyy");
            ws.Cell(row, 3).Value = v.FechaHora.ToString("HH:mm");
            ws.Cell(row, 4).Value = EtiquetaMetodo(v.Metodo);
            ws.Cell(row, 5).Value = anulado ? "Anulado" : "Pagado";
            ws.Cell(row, 6).Value = v.Total;
            ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0.00";
            if (anulado) ws.Range(row, 1, row, 6).Style.Font.FontColor = XLColor.FromHtml("#B0B0B0");
            row++;
        }

        // Total
        var lblTot = ws.Cell(row + 1, 5);
        lblTot.Value = "Total:";
        lblTot.Style.Font.Bold = true;
        lblTot.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Right;
        var celTot = ws.Cell(row + 1, 6);
        celTot.Value = total;
        celTot.Style.Font.Bold = true;
        celTot.Style.NumberFormat.Format = "#,##0.00";
        celTot.Style.Fill.BackgroundColor = XLColor.FromHtml("#DDF7E6");

        ws.Columns().AdjustToContents();
        wb.SaveAs(ruta);
    }

    /// <summary>Etiqueta amigable del método de pago para la UI peruana.</summary>
    private static string EtiquetaMetodo(MetodoPago m) => m switch
    {
        MetodoPago.Efectivo => "Efectivo",
        MetodoPago.Tarjeta => "Tarjeta",
        MetodoPago.BilleteraDigital => "Yape / Plin",
        MetodoPago.Transferencia => "Transferencia",
        MetodoPago.Credito => "Crédito",
        _ => m.ToString()
    };

    /// <summary>"Hoy, 25 de agosto de 2026" (fecha local, sin depender de la cultura del SO).</summary>
    private static string TextoFecha(DateTime f) =>
        $"Hoy, {f.Day} de {Meses[f.Month - 1]} de {f.Year}";
}

public sealed record VentaResumenItem(
    Guid Id, string Numero, string Hora, string Metodo, decimal Total, string Estado, bool EsAnulado);

public sealed record TopProductoItem(string Nombre, decimal Unidades, decimal Total);

public sealed record MetodoPagoItem(string Metodo, decimal Total, int Cantidad);
