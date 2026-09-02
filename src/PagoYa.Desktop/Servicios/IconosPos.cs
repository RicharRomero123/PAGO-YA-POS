namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Rutas centralizadas a la iconografía del POS (PNG embebidos como Resource en
/// <c>Assets/Iconos</c>). Se exponen como URIs <b>pack absolutas</b> en texto,
/// que es la forma más robusta de enlazarlas a <c>Image.Source</c> vía binding
/// (el conversor de <see cref="System.Windows.Media.ImageSource"/> las resuelve
/// sin depender del BaseUri del control).
///
/// Un solo lugar para el mapeo logo→archivo: si mañana cambia un icono, se toca
/// aquí y todo el POS (sidebar, onboarding, identidad de rubro) queda alineado.
/// </summary>
public static class IconosPos
{
    private const string Base = "pack://application:,,,/Assets/Iconos/";

    // --- Navegación del sidebar ---
    public const string Cobrar = Base + "ico-cobrar.png";
    public const string Caja = Base + "ico-caja.png";
    public const string Inventario = Base + "ico-inventario.png";
    public const string Proveedores = Base + "ico-proveedores.png";
    public const string Reportes = Base + "ico-reportes.png";
    public const string Facturacion = Base + "ico-facturacion.png";
    public const string Nube = Base + "ico-nube.png";
    public const string Multisede = Base + "ico-tienda.png";
    public const string Usuarios = Base + "ico-usuarios.png";
    public const string Configuracion = Base + "ico-configuracion.png";

    // --- Elementos de estado ---
    public const string Candado = Base + "ico-candado.png";

    // --- Rubros con icono propio (los demás caen a emoji en el onboarding) ---
    public const string RubroBodega = Base + "ico-tienda.png";
    public const string RubroRestaurante = Base + "ico-restaurante.png";
    public const string RubroFarmacia = Base + "ico-farmacia.png";
    public const string RubroFerreteria = Base + "ico-ferreteria.png";
    public const string RubroHotel = Base + "ico-hotel.png";

    /// <summary>
    /// Icono del rubro para la identidad del negocio (sidebar). Devuelve la ruta
    /// PNG del rubro si existe; si no, cae al icono genérico de tienda para que el
    /// encabezado del POS siempre muestre un icono coherente.
    /// </summary>
    public static string DeRubro(string? clave) => (clave ?? "").ToLowerInvariant() switch
    {
        "restaurante" or "cafeteria" or "polleria" => RubroRestaurante,
        "farmacia" => RubroFarmacia,
        "ferreteria" => RubroFerreteria,
        "hotel" => RubroHotel,
        _ => RubroBodega, // bodega, licoreria, otro y desconocidos
    };
}
