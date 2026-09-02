using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Desktop.Servicios.Impresion;

namespace PagoYa.Desktop;

/// <summary>
/// Vista previa del ticket antes de imprimir: reconstruye el mismo formato del
/// ticket ESC/POS como texto monoespaciado + el logo del negocio, y permite
/// imprimirlo desde aquí. Así el usuario confirma que se ve bien.
/// </summary>
public partial class TicketPreviewWindow : Window
{
    private static readonly CultureInfo Pe = CultureInfo.GetCultureInfo("es-PE");

    private readonly Venta _venta;
    private readonly ITicketPrinter _printer;

    public TicketPreviewWindow(Venta venta, DatosNegocio negocio, ITicketPrinter printer)
    {
        InitializeComponent();
        _venta = venta;
        _printer = printer;

        CargarLogo(negocio.LogoRuta);
        TicketTexto.Text = ConstruirTexto(venta, negocio);
    }

    private void CargarLogo(string? ruta)
    {
        if (string.IsNullOrWhiteSpace(ruta) || !File.Exists(ruta)) { LogoImg.Visibility = Visibility.Collapsed; return; }
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new System.Uri(ruta, System.UriKind.Absolute);
            bmp.EndInit();
            bmp.Freeze();
            LogoImg.Source = bmp;
        }
        catch { LogoImg.Visibility = Visibility.Collapsed; }
    }

    private static string ConstruirTexto(Venta v, DatosNegocio n)
    {
        var ancho = n.ColumnasTicket > 0 ? n.ColumnasTicket : 42;
        var sb = new StringBuilder();
        void Linea(string s = "") => sb.AppendLine(s);
        void Centro(string s) => Linea(Centrar(s, ancho));

        Centro(n.Nombre.ToUpper(Pe));
        if (!string.IsNullOrWhiteSpace(n.Ruc)) Centro($"RUC: {n.Ruc}");
        if (!string.IsNullOrWhiteSpace(n.Direccion)) Centro(n.Direccion);
        if (!string.IsNullOrWhiteSpace(n.Telefono)) Centro($"Tel: {n.Telefono}");
        Linea();
        Centro("NOTA DE VENTA");
        Centro(v.Numero);
        Linea(new string('-', ancho));
        Linea($"Fecha: {v.FechaHora.ToString("dd/MM/yyyy HH:mm", Pe)}");
        Linea($"Pago : {NombreMetodo(v.MetodoPago)}");
        Linea(new string('-', ancho));

        foreach (var d in v.Detalles)
        {
            Linea(Recortar(d.DescripcionProducto, ancho));
            var izq = $"  {FmtCant(d.Cantidad)} x {Fmt(d.PrecioUnitario)}";
            Linea(DosColumnas(izq, Fmt(d.Importe), ancho));
        }

        Linea(new string('-', ancho));
        Linea(DosColumnas("Subtotal:", Fmt(v.SubTotal), ancho));
        Linea(DosColumnas("IGV (18%):", Fmt(v.Igv), ancho));
        Linea(DosColumnas("TOTAL:", Fmt(v.Total), ancho));
        if (v.MontoRecibido is { } rec)
        {
            Linea(DosColumnas("Recibido:", Fmt(rec), ancho));
            var vuelto = rec - v.Total;
            if (vuelto > 0) Linea(DosColumnas("Vuelto:", Fmt(vuelto), ancho));
        }
        Linea();
        Centro(n.PieTicket);
        Centro("Documento interno - no es comprobante");
        Centro("de pago autorizado por SUNAT");
        return sb.ToString();
    }

    private async void Imprimir_Click(object sender, RoutedEventArgs e)
    {
        BtnImprimir.IsEnabled = false;
        Estado.Text = "Enviando a la impresora…";
        var r = await _printer.ImprimirTicketVentaAsync(_venta);
        Estado.Text = r.Exito ? "Ticket enviado a la impresora." : $"No se pudo imprimir: {r.Mensaje}";
        BtnImprimir.IsEnabled = true;
    }

    private void Cerrar_Click(object sender, RoutedEventArgs e) => Close();

    // --- Helpers de formato (espejo del ticket ESC/POS) ---
    private static string Fmt(decimal m) => "S/ " + m.ToString("N2", Pe);
    private static string FmtCant(decimal c) => c == System.Math.Truncate(c) ? ((long)c).ToString(Pe) : c.ToString("0.###", Pe);
    private static string Recortar(string s, int max) => s.Length <= max ? s : s[..max];
    private static string Centrar(string s, int ancho)
    {
        if (s.Length >= ancho) return s;
        var pad = (ancho - s.Length) / 2;
        return new string(' ', pad) + s;
    }
    private static string DosColumnas(string izq, string der, int ancho)
    {
        if (izq.Length + der.Length >= ancho) return izq + " " + der;
        return izq + new string(' ', ancho - izq.Length - der.Length) + der;
    }
    private static string NombreMetodo(MetodoPago m) => m switch
    {
        MetodoPago.Efectivo => "Efectivo",
        MetodoPago.Tarjeta => "Tarjeta",
        MetodoPago.BilleteraDigital => "Yape / Plin",
        MetodoPago.Transferencia => "Transferencia",
        MetodoPago.Credito => "Credito",
        _ => m.ToString()
    };
}
