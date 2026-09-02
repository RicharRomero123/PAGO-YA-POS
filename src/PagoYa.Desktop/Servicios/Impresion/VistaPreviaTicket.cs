using System.Windows;
using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.Servicios.Impresion;

/// <summary>Abre la ventana de vista previa del ticket de una venta.</summary>
public interface IVistaPreviaTicket
{
    void Mostrar(Venta venta);
}

/// <summary>
/// Implementación WPF: construye <see cref="TicketPreviewWindow"/> con los datos
/// del negocio (incluye logo) y la impresora, y la muestra como diálogo.
/// </summary>
public sealed class VistaPreviaTicket : IVistaPreviaTicket
{
    private readonly DatosNegocio _negocio;
    private readonly ITicketPrinter _printer;

    public VistaPreviaTicket(DatosNegocio negocio, ITicketPrinter printer)
    {
        _negocio = negocio;
        _printer = printer;
    }

    public void Mostrar(Venta venta)
    {
        var win = new TicketPreviewWindow(venta, _negocio, _printer)
        {
            Owner = Application.Current?.MainWindow
        };
        win.ShowDialog();
    }
}
