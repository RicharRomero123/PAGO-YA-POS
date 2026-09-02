using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Invoicing.Sunat;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Pantalla "Facturación" (tier Facturador Pro). Muestra los datos del emisor
/// SUNAT, el ambiente y si hay certificado configurado, y permite EMITIR un
/// comprobante de prueba con el motor real (<see cref="IInvoiceEngine"/>) para
/// verificar el pipeline UBL 2.1 + firma + CDR.
///
/// Las ventas del POS ya emiten su boleta automáticamente (ver
/// CobroRapidoViewModel.EngancharFacturacionAsync); esta pantalla es el panel de
/// control/diagnóstico. Solo navegable con el flag "invoicing".
/// </summary>
public partial class FacturacionViewModel : ObservableObject
{
    private readonly IInvoiceEngine? _motor;

    [ObservableProperty] private bool _puedeEmitir;
    [ObservableProperty] private string _ruc = "";
    [ObservableProperty] private string _razonSocial = "";
    [ObservableProperty] private string _serieBoleta = "";
    [ObservableProperty] private string _ambiente = "";
    [ObservableProperty] private bool _certificadoConfigurado;
    [ObservableProperty] private bool _emitiendo;
    [ObservableProperty] private string _mensajeEstado = "";

    // Resultado de la última emisión de prueba.
    [ObservableProperty] private bool _hayResultado;
    [ObservableProperty] private bool _ultimoAceptado;
    [ObservableProperty] private string _ultimoComprobante = "";
    [ObservableProperty] private string _ultimoEstadoSunat = "";
    [ObservableProperty] private string _ultimoCdr = "";
    [ObservableProperty] private string _ultimoHash = "";

    /// <summary>Constructor de DISEÑO.</summary>
    public FacturacionViewModel()
    {
        PuedeEmitir = true;
        Ruc = "20512345678";
        RazonSocial = "BODEGA DEMO SAC";
        SerieBoleta = "B001";
        Ambiente = "Simulado";
        CertificadoConfigurado = false;
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public FacturacionViewModel(IInvoiceEngine motor, OpcionesEmisor emisor)
    {
        _motor = motor;
        PuedeEmitir = motor.PuedeEmitir;
        Ruc = string.IsNullOrWhiteSpace(emisor.Ruc) ? "(configura tu RUC)" : emisor.Ruc;
        RazonSocial = emisor.RazonSocial;
        SerieBoleta = emisor.SerieBoleta;
        Ambiente = emisor.Ambiente switch
        {
            AmbienteSunat.Produccion => "Producción SUNAT",
            AmbienteSunat.Beta => "Homologación (beta)",
            _ => "Simulado (offline)"
        };
        CertificadoConfigurado = !string.IsNullOrWhiteSpace(emisor.CertificadoPfxPath);
    }

    /// <summary>Emite un comprobante de PRUEBA para verificar el pipeline.</summary>
    [RelayCommand]
    private async Task EmitirPruebaAsync(CancellationToken ct = default)
    {
        if (_motor is null || Emitiendo) return;
        if (!_motor.PuedeEmitir)
        {
            MensajeEstado = "La facturación no está habilitada por la licencia.";
            return;
        }

        Emitiendo = true;
        MensajeEstado = "Emitiendo comprobante de prueba…";
        try
        {
            var res = await _motor.EmitirComprobanteAsync(VentaDePrueba(), ct);
            HayResultado = res.Comprobante is not null;
            UltimoAceptado = res.Aceptado;
            MensajeEstado = res.Aceptado ? "Comprobante emitido correctamente." : $"Rechazado: {res.Mensaje}";

            if (res.Comprobante is { } c)
            {
                UltimoComprobante = $"{c.Serie}-{c.Correlativo:D8}";
                UltimoEstadoSunat = c.EstadoSunat ?? "—";
                UltimoCdr = res.CodigoCdr ?? "—";
                UltimoHash = string.IsNullOrEmpty(c.HashXml)
                    ? "—"
                    : (c.HashXml.Length > 24 ? c.HashXml[..24] + "…" : c.HashXml);
            }
        }
        catch (Exception ex)
        {
            MensajeEstado = $"Error al emitir: {ex.Message}";
        }
        finally
        {
            Emitiendo = false;
        }
    }

    private static Venta VentaDePrueba()
    {
        var venta = new Venta
        {
            Numero = "PRUEBA-0001",
            FechaHora = DateTime.Now,
            MetodoPago = MetodoPago.Efectivo,
            SubTotal = 8.47m,
            Igv = 1.53m,
            Total = 10.00m
        };
        venta.Detalles.Add(new DetalleVenta
        {
            DescripcionProducto = "Producto de prueba",
            Cantidad = 2,
            PrecioUnitario = 5.00m,
            Importe = 10.00m
        });
        return venta;
    }
}
