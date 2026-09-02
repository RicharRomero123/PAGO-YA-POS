using System.Windows.Controls;
using PagoYa.Desktop.ViewModels;

namespace PagoYa.Desktop.Views;

/// <summary>
/// Vista de gestión de usuarios. Sincroniza el PasswordBox (no bindable) hacia
/// el ViewModel y lo limpia cuando el editor se cierra.
/// </summary>
public partial class UsuariosView : UserControl
{
    public UsuariosView()
    {
        InitializeComponent();
        PasswordNuevo.PasswordChanged += (_, _) =>
        {
            if (DataContext is UsuariosViewModel vm) vm.FormPassword = PasswordNuevo.Password;
        };
        DataContextChanged += (_, _) => EngancharLimpieza();
    }

    private void EngancharLimpieza()
    {
        if (DataContext is not UsuariosViewModel vm) return;
        vm.PropertyChanged += (_, e) =>
        {
            // Al cerrar el editor, vaciamos el campo de contraseña por seguridad.
            if (e.PropertyName == nameof(UsuariosViewModel.EditorVisible) && !vm.EditorVisible)
                PasswordNuevo.Password = "";
        };
    }
}
