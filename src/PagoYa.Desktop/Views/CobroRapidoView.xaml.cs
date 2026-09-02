using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using PagoYa.Desktop.ViewModels;

namespace PagoYa.Desktop.Views;

/// <summary>
/// Pantalla de Cobro Rápido. El code-behind solo maneja el comportamiento de
/// UI puro (foco automático en el buscador y atajos de teclado); la lógica de
/// negocio vive en <see cref="CobroRapidoViewModel"/> (MVVM).
/// </summary>
public partial class CobroRapidoView : UserControl
{
    public CobroRapidoView()
    {
        InitializeComponent();
        Loaded += (_, _) => EnfocarBuscador();
    }

    private void EnfocarBuscador()
    {
        BuscadorBox.Focus();
        Keyboard.Focus(BuscadorBox);
    }

    /// <summary>Atajos globales F2 / F4 / F8, invocados por la ventana host.</summary>
    public void ManejarAtajo(Key tecla)
    {
        if (DataContext is not CobroRapidoViewModel vm) return;
        switch (tecla)
        {
            case Key.F2:
                EnfocarBuscador();
                break;
            case Key.F4:
                if (vm.CobrarCommand.CanExecute(null)) vm.CobrarCommand.Execute(null);
                break;
            case Key.F8:
                vm.CancelarVentaCommand.Execute(null);
                break;
        }
    }
}
