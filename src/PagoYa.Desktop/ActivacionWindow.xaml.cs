using System.Windows;
using PagoYa.Desktop.ViewModels;

namespace PagoYa.Desktop;

/// <summary>
/// Ventana de <b>activación de licencia</b> (gate de arranque del modelo "Base
/// exige licencia"). Se muestra como diálogo antes del login: si el usuario no
/// activa, la app no continúa. Al activar con éxito cierra con DialogResult true.
/// </summary>
public partial class ActivacionWindow : Window
{
    public ActivacionWindow(ActivacionViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        // Activación exitosa -> cerrar el diálogo con resultado positivo (continúa el arranque).
        vm.ActivacionExitosa = () =>
        {
            DialogResult = true;
            Close();
        };
    }

    // "Salir": cierra sin activar (DialogResult queda false -> App hace Shutdown).
    private void Salir_Click(object sender, RoutedEventArgs e) => Close();
}
