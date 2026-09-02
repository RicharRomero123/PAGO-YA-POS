using CommunityToolkit.Mvvm.ComponentModel;
using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Ítem de producto para la grilla de cobro. Mapea desde
/// <see cref="PagoYa.Core.Entidades.Producto"/> (vía IProductoRepository) o se
/// crea con datos de diseño para el render en modo diseñador.
/// </summary>
public partial class ProductoItemViewModel : ObservableObject
{
    /// <summary>Id del producto en BD (Guid.Empty para ítems de diseño).</summary>
    public Guid ProductoId { get; init; }

    public string Codigo { get; init; } = "";
    public string Nombre { get; init; } = "";

    /// <summary>Precio al que se cobra (ya con descuento aplicado si lo tiene).</summary>
    public decimal Precio { get; init; }

    /// <summary>Precio normal (de lista) antes del descuento; se muestra tachado si hay oferta.</summary>
    public decimal PrecioNormal { get; init; }

    /// <summary>True si el producto está en oferta (precio final &lt; precio normal).</summary>
    public bool TieneDescuento { get; init; }

    /// <summary>Etiqueta del badge de oferta ("-15%" o "OFERTA"); vacío si no hay descuento.</summary>
    public string EtiquetaDescuento { get; init; } = "";

    public string Categoria { get; init; } = "General";

    /// <summary>Stock disponible (cache desnormalizado del producto).</summary>
    public decimal StockActual { get; init; }

    /// <summary>Si el producto controla stock. Servicios/genéricos pueden no controlarlo.</summary>
    public bool ControlaStock { get; init; } = true;

    /// <summary>Umbral de "stock bajo" para el aviso visual del POS.</summary>
    public decimal StockMinimo { get; init; } = 5m;

    /// <summary>Emoji/glifo de muestra para la card (fallback si no hay foto).</summary>
    public string Icono { get; init; } = "\U0001F4E6"; // 📦

    /// <summary>Ruta local de la foto del producto (o null → se usa el ícono).</summary>
    public string? ImagenRuta { get; init; }

    /// <summary>True si el producto tiene foto cargada.</summary>
    public bool TieneImagen => !string.IsNullOrWhiteSpace(ImagenRuta);

    /// <summary>Sin unidades disponibles: la card se muestra agotada y no deja agregar.</summary>
    public bool SinStock => ControlaStock && StockActual <= 0;

    /// <summary>Quedan pocas unidades (>0 y ≤ mínimo): tinte de aviso en la card.</summary>
    public bool StockBajo => ControlaStock && StockActual > 0 && StockActual <= StockMinimo;

    /// <summary>Texto corto para la esquina de la card ("Agotado" / "Quedan 3").</summary>
    public string EtiquetaStock =>
        !ControlaStock ? "" : SinStock ? "Agotado" : StockBajo ? $"Quedan {FormatoStock(StockActual)}" : "";

    private static string FormatoStock(decimal s) =>
        s == Math.Truncate(s) ? ((long)s).ToString() : s.ToString("0.###");

    // ------------------------------------------------------------------
    // Campos farmacéuticos (rubro farmacia) — para genéricos, receta y bloqueo de vencidos
    // ------------------------------------------------------------------

    /// <summary>Principio activo / DCI del medicamento (para orientar venta de genéricos). Null/vacío si no aplica.</summary>
    public string? PrincipioActivo { get; init; }

    /// <summary>True si mostrar el principio activo bajo el nombre en la card.</summary>
    public bool TienePrincipioActivo => !string.IsNullOrWhiteSpace(PrincipioActivo);

    /// <summary>True si la venta exige receta médica (antibióticos/controlados): la card muestra badge "Rx".</summary>
    public bool RequiereReceta { get; init; }

    /// <summary>Fecha de vencimiento del lote vigente (solo fecha). Null si no aplica.</summary>
    public DateTime? FechaVencimiento { get; init; }

    /// <summary>True si el producto está vencido: no se puede agregar al carrito y la card se muestra bloqueada.</summary>
    public bool EstaVencido { get; init; }

    /// <summary>
    /// La card se muestra deshabilitada (agotada o vencida). Un producto vencido no
    /// se puede vender aunque tenga stock.
    /// </summary>
    public bool NoVendible => SinStock || EstaVencido;

    // ------------------------------------------------------------------
    // Personalización (rubro comida) — modificadores/agregados/nota de cocina
    // ------------------------------------------------------------------

    /// <summary>Personalización del producto (grupos de modificadores + nota). Null si es simple.</summary>
    public PersonalizacionProducto? Personalizacion { get; init; }

    /// <summary>True si el producto tiene algo que personalizar al venderlo (abre diálogo en Cobro).</summary>
    public bool TienePersonalizacion => Personalizacion is { } p && p.TieneContenido && p.Grupos.Count > 0;

    /// <summary>Construye el VM a partir de una entidad de dominio.</summary>
    public static ProductoItemViewModel Desde(Producto p) => new()
    {
        ProductoId = p.Id,
        Codigo = p.Codigo,
        Nombre = p.Nombre,
        Precio = p.PrecioFinal,
        PrecioNormal = p.PrecioVenta,
        TieneDescuento = p.TieneDescuento,
        EtiquetaDescuento = p.PorcentajeDescuento > 0 ? $"-{p.PorcentajeDescuento}%" : (p.TieneDescuento ? "OFERTA" : ""),
        Categoria = string.IsNullOrWhiteSpace(p.Descripcion) ? "General" : p.Descripcion!,
        StockActual = p.StockActual,
        ControlaStock = p.ControlaStock,
        ImagenRuta = p.ImagenRuta,
        PrincipioActivo = p.PrincipioActivo,
        RequiereReceta = p.RequiereReceta,
        FechaVencimiento = p.FechaVencimiento,
        EstaVencido = p.EstaVencido,
        Personalizacion = PersonalizacionSerializer.Deserializar(p.PersonalizacionJson),
        Icono = "\U0001F4E6"
    };
}
