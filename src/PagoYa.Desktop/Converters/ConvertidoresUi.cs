using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PagoYa.Desktop.Converters;

/// <summary>
/// Convierte un decimal a texto de moneda peruana: "S/ 1,234.50".
/// Usado en precios, totales y vuelto. Cultura fija es-PE.
/// </summary>
public sealed class MonedaSolesConverter : IValueConverter
{
    private static readonly CultureInfo Pe = CultureInfo.GetCultureInfo("es-PE");

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var monto = value switch
        {
            decimal d => d,
            double db => (decimal)db,
            int i => i,
            _ => 0m
        };
        return "S/ " + monto.ToString("N2", Pe);
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Compara el valor (string clave del módulo activo) con el parámetro; devuelve
/// Visible si coinciden. Usado por el shell para mostrar solo la pantalla activa.
/// </summary>
public sealed class IgualdadAVisibilidadConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.Equals(value?.ToString(), parameter?.ToString(), StringComparison.Ordinal)
            ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Valor "truthy" → Visibility. Acepta bool, números (≠0) y strings (no vacíos)
/// para poder ocultar avisos/campos vacíos. Parámetro "Inv" invierte la lógica.
/// </summary>
public sealed class BoolAVisibilidadConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var b = value switch
        {
            bool v => v,
            string s => !string.IsNullOrWhiteSpace(s),
            int i => i != 0,
            long l => l != 0,
            double d => d != 0,
            null => false,
            _ => true
        };
        if (parameter is string p && p.Equals("Inv", StringComparison.OrdinalIgnoreCase))
            b = !b;
        return b ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Convierte una URI <b>pack absoluta</b> (ej. "pack://application:,,,/Assets/Iconos/x.png")
/// a un <see cref="BitmapImage"/> congelado. Es la forma segura de enlazar los
/// iconos embebidos del POS a <c>Image.Source</c> por binding: no depende del
/// BaseUri del control (que dentro de plantillas/ItemsControl puede no resolverse)
/// y devuelve null si la ruta está vacía, para poder ocultar la imagen con estilo.
/// </summary>
public sealed class PackUriAImagenConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not string uri || string.IsNullOrWhiteSpace(uri)) return null;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(uri, UriKind.Absolute);
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Mapea una categoría (string) a un color vibrante estable, para que la grilla
/// de productos del POS se vea colorida y cada categoría tenga su tono fijo.
/// Determinístico por hash del nombre; el parámetro "Tint" devuelve la versión
/// pastel (fondo) en vez del color sólido (barra/acento).
/// </summary>
public sealed class CategoriaABrushConverter : IValueConverter
{
    // Paleta táctil saturada (acento) + su versión clara (fondo pastel).
    private static readonly (Color Solido, Color Tint)[] Paleta =
    {
        (Color.FromRgb(0x25, 0x63, 0xEB), Color.FromRgb(0xE5, 0xED, 0xFF)), // azul
        (Color.FromRgb(0x16, 0xA3, 0x4A), Color.FromRgb(0xDD, 0xF7, 0xE6)), // verde
        (Color.FromRgb(0xF5, 0x9E, 0x0B), Color.FromRgb(0xFF, 0xF2, 0xD6)), // ámbar
        (Color.FromRgb(0xDC, 0x26, 0x26), Color.FromRgb(0xFD, 0xE2, 0xE2)), // rojo
        (Color.FromRgb(0x7C, 0x3A, 0xED), Color.FromRgb(0xEE, 0xE5, 0xFF)), // violeta
        (Color.FromRgb(0x08, 0x91, 0xB2), Color.FromRgb(0xDC, 0xF3, 0xFA)), // cian
        (Color.FromRgb(0xDB, 0x27, 0x77), Color.FromRgb(0xFC, 0xE1, 0xEF)), // rosa
        (Color.FromRgb(0xEA, 0x58, 0x0C), Color.FromRgb(0xFF, 0xE9, 0xD9)), // naranja
    };

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var cat = value?.ToString() ?? "";
        var esTint = parameter is string p && p.Equals("Tint", StringComparison.OrdinalIgnoreCase);

        // "Todas" y vacío usan el naranja de marca para no desentonar.
        int idx;
        if (string.IsNullOrWhiteSpace(cat) || cat.Equals("Todas", StringComparison.OrdinalIgnoreCase))
            idx = 7;
        else
        {
            uint h = 2166136261;
            foreach (var c in cat) { h = (h ^ c) * 16777619; }
            idx = (int)(h % (uint)Paleta.Length);
        }

        var color = esTint ? Paleta[idx].Tint : Paleta[idx].Solido;
        return new SolidColorBrush(color);
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>Invierte un bool (para enlazar radios/opciones mutuamente excluyentes). Two-way.</summary>
public sealed class BoolInversoConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is bool b ? !b : true;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is bool b ? !b : false;
}

/// <summary>
/// Mapea el estado de una habitación (<see cref="PagoYa.Core.Enums.EstadoHabitacion"/>)
/// a un color para el mapa de recepción del hotel. Por defecto devuelve el color
/// sólido (verde/rojo/ámbar/gris/azul); el parámetro "Tint" devuelve la versión
/// pálida para fondos de tarjeta.
/// </summary>
public sealed class EstadoHabitacionAColorConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var esTint = parameter is string p && p.Equals("Tint", StringComparison.OrdinalIgnoreCase);
        var (solido, tint) = value switch
        {
            PagoYa.Core.Enums.EstadoHabitacion.Disponible    => (Color.FromRgb(0x16, 0xA3, 0x4A), Color.FromRgb(0xE7, 0xF7, 0xEC)),
            PagoYa.Core.Enums.EstadoHabitacion.Ocupada       => (Color.FromRgb(0xDC, 0x26, 0x26), Color.FromRgb(0xFD, 0xE7, 0xE7)),
            PagoYa.Core.Enums.EstadoHabitacion.Limpieza      => (Color.FromRgb(0xF5, 0x9E, 0x0B), Color.FromRgb(0xFE, 0xF3, 0xD9)),
            PagoYa.Core.Enums.EstadoHabitacion.Mantenimiento => (Color.FromRgb(0x6B, 0x72, 0x80), Color.FromRgb(0xEC, 0xEE, 0xF1)),
            PagoYa.Core.Enums.EstadoHabitacion.Reservada     => (Color.FromRgb(0x25, 0x63, 0xEB), Color.FromRgb(0xE5, 0xED, 0xFF)),
            _ => (Color.FromRgb(0x6B, 0x72, 0x80), Color.FromRgb(0xEC, 0xEE, 0xF1))
        };
        return new SolidColorBrush(esTint ? tint : solido);
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Mapea el estado de una mesa (<see cref="PagoYa.Core.Enums.EstadoMesa"/>) a un
/// color para el mapa del salón (rubro restaurante): Libre=verde, Ocupada=naranja
/// de marca, PorCobrar=ámbar, Reservada=gris. Por defecto devuelve el color sólido;
/// el parámetro "Tint" devuelve la versión pálida para fondos de tarjeta.
/// </summary>
public sealed class EstadoMesaAColorConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var esTint = parameter is string p && p.Equals("Tint", StringComparison.OrdinalIgnoreCase);
        var (solido, tint) = value switch
        {
            PagoYa.Core.Enums.EstadoMesa.Libre     => (Color.FromRgb(0x16, 0xA3, 0x4A), Color.FromRgb(0xE7, 0xF7, 0xEC)),
            PagoYa.Core.Enums.EstadoMesa.Ocupada   => (Color.FromRgb(0xF2, 0x65, 0x22), Color.FromRgb(0xFF, 0xEC, 0xE1)),
            PagoYa.Core.Enums.EstadoMesa.PorCobrar => (Color.FromRgb(0xF5, 0x9E, 0x0B), Color.FromRgb(0xFE, 0xF3, 0xD9)),
            PagoYa.Core.Enums.EstadoMesa.Reservada => (Color.FromRgb(0x6B, 0x72, 0x80), Color.FromRgb(0xEC, 0xEE, 0xF1)),
            _ => (Color.FromRgb(0x6B, 0x72, 0x80), Color.FromRgb(0xEC, 0xEE, 0xF1))
        };
        return new SolidColorBrush(esTint ? tint : solido);
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}

/// <summary>
/// Carga una imagen desde una ruta local a <see cref="BitmapImage"/> sin dejar el
/// archivo bloqueado (CacheOption=OnLoad), para poder reemplazar la foto luego.
/// Devuelve null si la ruta está vacía o el archivo no existe (la UI muestra el
/// ícono por defecto en ese caso).
/// </summary>
public sealed class RutaAImagenConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var ruta = value as string;
        if (string.IsNullOrWhiteSpace(ruta) || !File.Exists(ruta)) return null;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
            bmp.UriSource = new Uri(ruta, UriKind.Absolute);
            bmp.DecodePixelWidth = 240; // miniatura: ahorra memoria en la grilla
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Binding.DoNothing;
}
