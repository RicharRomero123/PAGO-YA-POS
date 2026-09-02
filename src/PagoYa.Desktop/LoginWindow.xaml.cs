using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using PagoYa.Desktop.ViewModels;

namespace PagoYa.Desktop;

/// <summary>
/// Ventana de acceso (login / creación del administrador). Se muestra como
/// diálogo antes del shell. El PasswordBox no soporta binding por seguridad, así
/// que se sincroniza a mano hacia el ViewModel en cada cambio. El toggle "ver
/// contraseña" intercambia el PasswordBox por un TextBox visible.
/// </summary>
public partial class LoginWindow : Window
{
    private readonly LoginViewModel _vm;

    // Íconos del ojo (Segoe MDL2 Assets): RedEye (oculto) / View (mostrando).
    private static readonly string OjoOculto = ((char)0xE7B3).ToString();
    private static readonly string OjoVisible = ((char)0xE890).ToString();

    // Estado del toggle "ver contraseña" de cada campo.
    private bool _ver1;
    private bool _ver2;

    public LoginWindow(LoginViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;

        // Al autenticar con éxito, cerramos el diálogo con resultado positivo.
        _vm.LoginExitoso = () =>
        {
            DialogResult = true;
            Close();
        };

        // Sincronización manual del PasswordBox (no bindable) y de su gemelo TextBox
        // visible (cuando el usuario activa "ver contraseña").
        PasswordBox.PasswordChanged += (_, _) => _vm.Password = PasswordBox.Password;
        PasswordConfirmarBox.PasswordChanged += (_, _) => _vm.PasswordConfirmar = PasswordConfirmarBox.Password;
        PasswordTextoBox.TextChanged += (_, _) => { if (_ver1) _vm.Password = PasswordTextoBox.Text; };
        PasswordConfirmarTextoBox.TextChanged += (_, _) => { if (_ver2) _vm.PasswordConfirmar = PasswordConfirmarTextoBox.Text; };

        _vm.PropertyChanged += OnVmPropertyChanged;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await _vm.InicializarAsync();
        ActualizarTextos();
        UsuarioBox.Focus();
    }

    private void OnVmPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(LoginViewModel.ModoSetup))
            ActualizarTextos();
    }

    private void ActualizarTextos()
    {
        if (_vm.ModoSetup)
        {
            Titulo.Text = "Crea tu cuenta de administrador";
            Subtitulo.Text = "Es la primera vez que abres PagoYa. Define tu usuario y contraseña; con esta cuenta gestionarás el negocio.";
        }
        else
        {
            Titulo.Text = "Iniciar sesión";
            Subtitulo.Text = "Ingresa con tu usuario y contraseña para operar el POS.";
        }
    }

    // "Ver contraseña": intercambia el PasswordBox (oculto) por un TextBox (visible)
    // y viceversa, copiando el valor y actualizando el ícono del ojo.
    private void ToggleVerClave1(object sender, RoutedEventArgs e)
    {
        _ver1 = !_ver1;
        SincronizarVer(_ver1, PasswordBox, PasswordTextoBox, OjoIcon1);
    }

    private void ToggleVerClave2(object sender, RoutedEventArgs e)
    {
        _ver2 = !_ver2;
        SincronizarVer(_ver2, PasswordConfirmarBox, PasswordConfirmarTextoBox, OjoIcon2);
    }

    private static void SincronizarVer(bool ver, PasswordBox pb, TextBox tb, TextBlock icono)
    {
        if (ver)
        {
            tb.Text = pb.Password;
            tb.Visibility = Visibility.Visible;
            pb.Visibility = Visibility.Collapsed;
            icono.Text = OjoVisible;
        }
        else
        {
            pb.Password = tb.Text;
            pb.Visibility = Visibility.Visible;
            tb.Visibility = Visibility.Collapsed;
            icono.Text = OjoOculto;
        }
    }
}
