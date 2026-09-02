namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Comodidades/adicionales predefinidos de una habitación (mercado peruano:
/// hoteles y hostales del paso). Se muestran como chips que el usuario marca al
/// crear/editar el cuarto; no tiene que escribirlos.
/// </summary>
public static class HotelComodidades
{
    /// <summary>Catálogo predefinido, en el orden en que se muestran.</summary>
    public static IReadOnlyList<string> Predefinidas { get; } = new[]
    {
        "TV Smart / Netflix",
        "TV Cable",
        "WiFi",
        "Jacuzzi",
        "Sillón tántrico",
        "Aire acondicionado",
        "Frigobar",
        "Agua caliente 24h",
        "Terma",
        "Ventilador",
        "Cama king",
        "Espejos de techo",
        "Luces de colores",
        "Cochera privada",
        "Room service",
        "Frazadas extra",
        "Toallas",
        "Desayuno incluido",
    };
}
