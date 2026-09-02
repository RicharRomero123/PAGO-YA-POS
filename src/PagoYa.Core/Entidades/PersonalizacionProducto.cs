using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Personalización de un producto (pensado para el rubro restaurante/comida): un
/// conjunto de <see cref="GrupoModificador"/> que el cajero resuelve al vender
/// (presentación/tamaño, agregados con precio, notas para cocina). Se serializa a
/// JSON y se guarda en la columna <c>personalizacion_json</c> del producto.
/// </summary>
public sealed class PersonalizacionProducto
{
    /// <summary>Grupos de opciones (tamaños, agregados, quitar ingredientes…).</summary>
    public List<GrupoModificador> Grupos { get; set; } = new();

    /// <summary>Si se permite escribir una nota libre para la cocina al vender.</summary>
    public bool PermiteNota { get; set; } = true;

    /// <summary>True si hay algo que personalizar (algún grupo con opciones o nota libre).</summary>
    [JsonIgnore]
    public bool TieneContenido => PermiteNota || Grupos.Any(g => g.Opciones.Count > 0);
}

/// <summary>
/// Grupo de modificadores. Si <see cref="Multiple"/> es false se elige UNA opción
/// (tipo radio: presentaciones/tamaños); si es true se eligen VARIAS (tipo
/// checkbox: agregados, quitar ingredientes).
/// </summary>
public sealed class GrupoModificador
{
    /// <summary>Nombre visible del grupo ("Tamaño", "Agregados", "Quitar").</summary>
    public string Nombre { get; set; } = "";

    /// <summary>true = elegir varias opciones; false = elegir solo una.</summary>
    public bool Multiple { get; set; }

    /// <summary>true = obligatorio elegir al menos una opción antes de agregar al carrito.</summary>
    public bool Obligatorio { get; set; }

    /// <summary>Opciones del grupo.</summary>
    public List<OpcionModificador> Opciones { get; set; } = new();
}

/// <summary>
/// Una opción de un grupo. <see cref="PrecioExtra"/> se SUMA al precio base del
/// producto (0 para notas/quitar ingredientes). Puede ser negativo para descuentos
/// puntuales, aunque lo normal es 0 o positivo.
/// </summary>
public sealed class OpcionModificador
{
    public string Nombre { get; set; } = "";
    public decimal PrecioExtra { get; set; }
}

/// <summary>
/// Serialización de <see cref="PersonalizacionProducto"/> hacia/desde el JSON que
/// se guarda en el producto. Tolerante a null/vacío/corrupto (devuelve vacío).
/// </summary>
public static class PersonalizacionSerializer
{
    private static readonly JsonSerializerOptions Opciones = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>Serializa a JSON, o null si no hay contenido (grupos vacíos y sin nota).</summary>
    public static string? Serializar(PersonalizacionProducto? p)
    {
        if (p is null || (p.Grupos.Count == 0 && !p.PermiteNota)) return null;
        return JsonSerializer.Serialize(p, Opciones);
    }

    /// <summary>Deserializa el JSON guardado a un objeto (nunca null; vacío si no aplica).</summary>
    public static PersonalizacionProducto Deserializar(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new PersonalizacionProducto { PermiteNota = false };
        try
        {
            return JsonSerializer.Deserialize<PersonalizacionProducto>(json, Opciones)
                   ?? new PersonalizacionProducto { PermiteNota = false };
        }
        catch (JsonException)
        {
            return new PersonalizacionProducto { PermiteNota = false };
        }
    }
}
