using System.Windows;
using System.Windows.Input;
using PagoYa.Desktop.ViewModels;
using PagoYa.Desktop.Views;

namespace PagoYa.Desktop;

/// <summary>
/// Ventana principal (shell). Aloja el menú lateral y el área de contenido.
/// El único comportamiento en code-behind son los <b>atajos globales</b>
/// (F2 Buscar / F4 Cobrar / F8 Cancelar), que se enrutan a la pantalla de
/// Cobro Rápido cuando está activa. Todo lo demás es MVVM.
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        PreviewKeyDown += AlPresionarTecla;
    }

    private void AlPresionarTecla(object sender, KeyEventArgs e)
    {
        if (e.Key is not (Key.F2 or Key.F4 or Key.F8)) return;
        if (DataContext is not MainWindowViewModel vm) return;

        // Los atajos de venta solo aplican en la pantalla de Cobro Rápido.
        if (vm.ModuloActivo != "cobro") return;

        var vista = BuscarVista<CobroRapidoView>(this);
        vista?.ManejarAtajo(e.Key);
        e.Handled = true;
    }

    private static T? BuscarVista<T>(DependencyObject raiz) where T : DependencyObject
    {
        var n = System.Windows.Media.VisualTreeHelper.GetChildrenCount(raiz);
        for (var i = 0; i < n; i++)
        {
            var hijo = System.Windows.Media.VisualTreeHelper.GetChild(raiz, i);
            if (hijo is T encontrado) return encontrado;
            var nieto = BuscarVista<T>(hijo);
            if (nieto is not null) return nieto;
        }
        return null;
    }
}
