using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Producto o artículo del catálogo del negocio (bodega, minimarket, etc.).
/// El stock se mantiene desnormalizado en <see cref="StockActual"/> para
/// lecturas rápidas en el POS; la fuente de verdad de movimientos vive en
/// <see cref="Inventario"/>.
/// </summary>
public class Producto : EntidadBase
{
    /// <summary>Código de barras o SKU interno. Índice de búsqueda rápida en el POS.</summary>
    public string Codigo { get; set; } = string.Empty;

    /// <summary>Nombre comercial del producto.</summary>
    public string Nombre { get; set; } = string.Empty;

    /// <summary>Descripción opcional.</summary>
    public string? Descripcion { get; set; }

    /// <summary>Precio de venta unitario en soles (PEN), incluye IGV.</summary>
    public decimal PrecioVenta { get; set; }

    /// <summary>Costo unitario de compra (para márgenes). Opcional.</summary>
    public decimal? CostoCompra { get; set; }

    /// <summary>
    /// Indica si el precio ya incluye IGV (true) o es valor sin impuestos.
    /// En Perú lo habitual en bodegas es precio con IGV incluido.
    /// </summary>
    public bool PrecioIncluyeIgv { get; set; } = true;

    /// <summary>Unidad de medida (ej. "NIU" unidad, "KGM" kilogramo — Catálogo 03 SUNAT).</summary>
    public string UnidadMedida { get; set; } = "NIU";

    /// <summary>Stock disponible (cache desnormalizado). Ver <see cref="Inventario"/>.</summary>
    public decimal StockActual { get; set; }

    /// <summary>Si el producto controla stock. Servicios/genéricos pueden no controlarlo.</summary>
    public bool ControlaStock { get; set; } = true;

    /// <summary>Producto activo/visible en el catálogo del POS.</summary>
    public bool Activo { get; set; } = true;

    /// <summary>
    /// Umbral de "stock bajo" para las alertas de reposición del POS. 0 = sin umbral
    /// (no genera aviso). Clave para farmacias/boticas que reponen medicamentos.
    /// </summary>
    public decimal StockMinimo { get; set; }

    // ------------------------------------------------------------------
    // Campos farmacéuticos (rubro Farmacia / Botica — Perú)
    //
    // Se guardan a nivel de producto (no de lote independiente) para mantener
    // simple el POS de una botica pequeña: el producto lleva el lote y la fecha
    // de vencimiento del stock vigente. Todos son opcionales y solo se muestran/
    // editan cuando el negocio es del rubro farmacia.
    // ------------------------------------------------------------------

    /// <summary>Fecha de vencimiento del lote vigente (solo fecha, sin hora). Null si no aplica.</summary>
    public DateTime? FechaVencimiento { get; set; }

    /// <summary>Número de lote del stock vigente (trazabilidad). Null/vacío si no aplica.</summary>
    public string? Lote { get; set; }

    /// <summary>Número de Registro Sanitario DIGEMID (medicamentos). Opcional.</summary>
    public string? RegistroSanitario { get; set; }

    /// <summary>
    /// Principio activo / Denominación Común Internacional (DCI). Permite buscar y
    /// ofrecer genéricos en el POS (obligación de informar genéricos en Perú).
    /// </summary>
    public string? PrincipioActivo { get; set; }

    /// <summary>
    /// True si la venta exige receta médica (antibióticos, controlados/psicotrópicos).
    /// El POS avisa al cajero antes de agregarlo al carrito.
    /// </summary>
    public bool RequiereReceta { get; set; }

    // ------------------------------------------------------------------
    // Estado de vencimiento (derivado; se calcula contra la fecha de hoy)
    // ------------------------------------------------------------------

    /// <summary>Días que faltan para vencer (negativo si ya venció); null si no tiene fecha.</summary>
    public int? DiasParaVencer =>
        FechaVencimiento is { } f ? (int)(f.Date - DateTime.Today).TotalDays : (int?)null;

    /// <summary>True si el producto ya está vencido (no debe venderse).</summary>
    public bool EstaVencido => DiasParaVencer is < 0;

    /// <summary>True si vence dentro de los próximos <paramref name="dias"/> días (pero aún no vence).</summary>
    public bool PorVencer(int dias = 30) => DiasParaVencer is { } d && d >= 0 && d <= dias;

    /// <summary>True si el umbral de stock mínimo está definido y el stock cayó a ese nivel o menos.</summary>
    public bool StockBajo => ControlaStock && StockMinimo > 0m && StockActual <= StockMinimo;

    /// <summary>
    /// Ruta local a la foto del producto (en %LocalAppData%\PagoYa\img). Null si
    /// no tiene foto; el POS muestra el ícono/emoji por defecto en ese caso.
    /// </summary>
    public string? ImagenRuta { get; set; }

    /// <summary>Proveedor del producto (a quién reabastecer). Null si no asignado.</summary>
    public Guid? ProveedorId { get; set; }

    /// <summary>
    /// Personalización del producto serializada a JSON (rubro restaurante/comida):
    /// grupos de modificadores (tamaños, agregados, notas). Null/vacío = producto
    /// simple, sin opciones. Se (de)serializa con <see cref="PersonalizacionSerializer"/>.
    /// </summary>
    public string? PersonalizacionJson { get; set; }

    // ------------------------------------------------------------------
    // Descuento / oferta por producto
    // ------------------------------------------------------------------

    /// <summary>Cómo se define el descuento de este producto (ninguno / % / precio de oferta).</summary>
    public TipoDescuento TipoDescuento { get; set; } = TipoDescuento.Ninguno;

    /// <summary>
    /// Valor del descuento según <see cref="TipoDescuento"/>: porcentaje 0–100 si es
    /// <see cref="TipoDescuento.Porcentaje"/>, o precio de oferta en soles si es
    /// <see cref="TipoDescuento.Oferta"/>. Ignorado cuando no hay descuento.
    /// </summary>
    public decimal DescuentoValor { get; set; }

    /// <summary>
    /// Precio efectivo al que se cobra el producto tras aplicar el descuento. Nunca
    /// supera <see cref="PrecioVenta"/> ni baja de 0; es lo que el POS lleva al
    /// carrito y al ticket. Un valor de oferta ≥ precio normal se ignora (sin efecto).
    /// </summary>
    public decimal PrecioFinal => TipoDescuento switch
    {
        TipoDescuento.Porcentaje =>
            decimal.Round(PrecioVenta * (1 - Math.Clamp(DescuentoValor, 0m, 100m) / 100m), 2),
        TipoDescuento.Oferta =>
            DescuentoValor > 0m && DescuentoValor < PrecioVenta ? decimal.Round(DescuentoValor, 2) : PrecioVenta,
        _ => PrecioVenta
    };

    /// <summary>True si el precio final es menor que el precio normal (hay oferta vigente).</summary>
    public bool TieneDescuento => PrecioFinal < PrecioVenta;

    /// <summary>Porcentaje efectivo de descuento redondeado (para el badge "-15%"); 0 si no aplica.</summary>
    public int PorcentajeDescuento =>
        PrecioVenta > 0m && TieneDescuento
            ? (int)decimal.Round((1 - PrecioFinal / PrecioVenta) * 100m, 0)
            : 0;
}
