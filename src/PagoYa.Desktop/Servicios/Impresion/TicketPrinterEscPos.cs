using System.Drawing.Printing;
using System.Globalization;
using System.IO;
using System.Text;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Desktop.Servicios.Impresion;

/// <summary>
/// Implementación de <see cref="ITicketPrinter"/> que genera comandos <b>ESC/POS
/// crudos</b> y los envía al spooler vía <see cref="RawPrinterHelper"/>.
///
/// Formato del ticket (58/80mm):
///   negocio (centrado, negrita, doble alto) → RUC/dirección/teléfono →
///   número de nota + fecha → líneas de ítems (cant x descripción ... importe) →
///   subtotal/IGV/TOTAL → método de pago + vuelto → pie ("Gracias").
///   Termina con avance de papel y corte (GS V).
///
/// Codificación: CP437/Latin. Los tickets llevan tildes/ñ; se usa CP850 (Multilingual)
/// que la mayoría de térmicas soportan, con transliteración de respaldo.
///
/// Compatibilidad: Windows 10/11. La impresora debe existir en Windows. Si el
/// hardware no está disponible (demo/headless), la impresión falla de forma
/// controlada y la venta NO se revierte (el ticket es secundario).
/// </summary>
public sealed class TicketPrinterEscPos : ITicketPrinter
{
    private const int AnchoColumnasDefault = 42; // típico para 80mm; 58mm usa 32.

    private static readonly CultureInfo Pe = CultureInfo.GetCultureInfo("es-PE");

    // --- Comandos ESC/POS ---
    private static readonly byte[] Init = { 0x1B, 0x40 };                 // ESC @
    private static readonly byte[] AlignLeft = { 0x1B, 0x61, 0x00 };
    private static readonly byte[] AlignCenter = { 0x1B, 0x61, 0x01 };
    private static readonly byte[] BoldOn = { 0x1B, 0x45, 0x01 };
    private static readonly byte[] BoldOff = { 0x1B, 0x45, 0x00 };
    private static readonly byte[] DoubleOn = { 0x1D, 0x21, 0x11 };       // doble ancho+alto
    private static readonly byte[] DoubleOff = { 0x1D, 0x21, 0x00 };
    private static readonly byte[] Cut = { 0x1D, 0x56, 0x42, 0x00 };      // GS V B: corte parcial
    private static readonly byte[] FeedLine = { 0x0A };

    // ESC p m t1 t2 — pulso de apertura del cajón. m=0 (pin 2), t1/t2 = duración
    // del pulso en unidades de 2ms (25→50ms ON, 250→500ms OFF). Es el estándar de
    // facto que aceptan Epson/Bixolon y la mayoría de clones térmicos.
    private static readonly byte[] DrawerKick = { 0x1B, 0x70, 0x00, 0x19, 0xFA };

    private readonly DatosNegocio _negocio;

    public TicketPrinterEscPos(DatosNegocio negocio) => _negocio = negocio;

    public Task<ResultadoImpresion> ImprimirTicketVentaAsync(Venta venta, CancellationToken ct = default)
    {
        // Trabajo síncrono breve envuelto en Task para no bloquear la UI.
        return Task.Run(() =>
        {
            try
            {
                var impresora = ResolverImpresora();
                if (impresora is null)
                    return ResultadoImpresion.Fallo("No hay impresora térmica configurada ni predeterminada.");

                var datos = ConstruirTicket(venta);
                var ok = RawPrinterHelper.EnviarBytes(impresora, datos);
                return ok
                    ? ResultadoImpresion.Ok()
                    : ResultadoImpresion.Fallo($"El spooler rechazó el ticket (impresora '{impresora}').");
            }
            catch (Exception ex)
            {
                return ResultadoImpresion.Fallo($"Error al imprimir: {ex.Message}");
            }
        }, ct);
    }

    /// <inheritdoc />
    public Task<ResultadoImpresion> AbrirCajonAsync(CancellationToken ct = default)
    {
        return Task.Run(() =>
        {
            try
            {
                var impresora = ResolverImpresora();
                if (impresora is null)
                    return ResultadoImpresion.Fallo("No hay impresora térmica configurada ni predeterminada.");

                // Init + pulso: init limpia estados previos y garantiza que el pulso
                // se interprete siempre igual sin depender del último ticket impreso.
                var datos = new byte[Init.Length + DrawerKick.Length];
                Init.CopyTo(datos, 0);
                DrawerKick.CopyTo(datos, Init.Length);

                var ok = RawPrinterHelper.EnviarBytes(impresora, datos);
                return ok
                    ? ResultadoImpresion.Ok()
                    : ResultadoImpresion.Fallo($"El spooler rechazó el pulso del cajón (impresora '{impresora}').");
            }
            catch (Exception ex)
            {
                return ResultadoImpresion.Fallo($"Error al abrir el cajón: {ex.Message}");
            }
        }, ct);
    }

    private string? ResolverImpresora()
    {
        if (!string.IsNullOrWhiteSpace(_negocio.NombreImpresora))
            return _negocio.NombreImpresora;
        try
        {
            var settings = new PrinterSettings();
            var predeterminada = settings.PrinterName;
            return string.IsNullOrWhiteSpace(predeterminada) ? null : predeterminada;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Serializa el ticket completo a bytes ESC/POS (CP850).</summary>
    private byte[] ConstruirTicket(Venta venta)
    {
        var enc = ObtenerCodificacion();
        var ancho = _negocio.ColumnasTicket > 0 ? _negocio.ColumnasTicket : AnchoColumnasDefault;
        using var ms = new MemoryStream();
        void Raw(byte[] b) => ms.Write(b, 0, b.Length);
        void Txt(string s) => ms.Write(enc.GetBytes(s), 0, enc.GetByteCount(s));
        void Linea(string s = "") { Txt(s); Raw(FeedLine); }

        Raw(Init);

        // Cajón: se pulsa al inicio para que se abra de inmediato, en paralelo con
        // la impresión del ticket. Solo en efectivo (Yape/tarjeta no mueven cajón).
        if (_negocio.AbrirCajonEnEfectivo && venta.MetodoPago == MetodoPago.Efectivo)
            Raw(DrawerKick);

        // --- Encabezado del negocio ---
        Raw(AlignCenter);
        Raw(BoldOn); Raw(DoubleOn);
        Linea(_negocio.Nombre);
        Raw(DoubleOff); Raw(BoldOff);
        if (!string.IsNullOrWhiteSpace(_negocio.Ruc)) Linea($"RUC: {_negocio.Ruc}");
        if (!string.IsNullOrWhiteSpace(_negocio.Direccion)) Linea(_negocio.Direccion);
        if (!string.IsNullOrWhiteSpace(_negocio.Telefono)) Linea($"Tel: {_negocio.Telefono}");
        Linea();
        Raw(BoldOn); Linea("NOTA DE VENTA"); Raw(BoldOff);
        Linea(venta.Numero);

        // --- Datos de la venta ---
        Raw(AlignLeft);
        Linea(new string('-', ancho));
        Linea($"Fecha: {venta.FechaHora.ToString("dd/MM/yyyy HH:mm", Pe)}");
        Linea($"Pago : {NombreMetodo(venta.MetodoPago)}");
        Linea(new string('-', ancho));

        // --- Ítems ---
        foreach (var d in venta.Detalles)
        {
            // Línea 1: descripción (recortada).
            Linea(Recortar(d.DescripcionProducto, ancho));
            // Línea 2: "  cant x precio" a la izquierda, importe a la derecha.
            var izq = $"  {FmtCant(d.Cantidad)} x {Fmt(d.PrecioUnitario)}";
            var der = Fmt(d.Importe);
            Linea(DosColumnas(izq, der, ancho));
        }

        Linea(new string('-', ancho));

        // --- Totales ---
        Linea(DosColumnas("Subtotal:", Fmt(venta.SubTotal), ancho));
        Linea(DosColumnas("IGV (18%):", Fmt(venta.Igv), ancho));
        Raw(BoldOn); Raw(DoubleOn);
        // En doble ancho la cuenta de columnas se reduce a la mitad.
        Linea(DosColumnas("TOTAL:", Fmt(venta.Total), ancho / 2));
        Raw(DoubleOff); Raw(BoldOff);

        if (venta.MontoRecibido is { } recibido)
        {
            Linea(DosColumnas("Recibido:", Fmt(recibido), ancho));
            var vuelto = recibido - venta.Total;
            if (vuelto > 0) Linea(DosColumnas("Vuelto:", Fmt(vuelto), ancho));
        }

        // --- Pie ---
        Linea();
        Raw(AlignCenter);
        Linea(_negocio.PieTicket);
        Linea("Documento interno - no es comprobante");
        Linea("de pago autorizado por SUNAT");

        // Avance + corte
        Raw(FeedLine); Raw(FeedLine); Raw(FeedLine);
        Raw(Cut);

        return ms.ToArray();
    }

    private static Encoding ObtenerCodificacion()
    {
        try
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding(850); // CP850 Multilingual (tildes/ñ).
        }
        catch
        {
            return Encoding.ASCII;
        }
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

    private static string Fmt(decimal monto) => "S/ " + monto.ToString("N2", Pe);
    private static string FmtCant(decimal cant) => cant == Math.Truncate(cant)
        ? ((long)cant).ToString(Pe)
        : cant.ToString("0.###", Pe);

    private static string Recortar(string s, int max)
        => s.Length <= max ? s : s[..max];

    private static string DosColumnas(string izq, string der, int ancho = AnchoColumnasDefault)
    {
        if (izq.Length + der.Length >= ancho)
            return izq + " " + der;
        return izq + new string(' ', ancho - izq.Length - der.Length) + der;
    }
}
