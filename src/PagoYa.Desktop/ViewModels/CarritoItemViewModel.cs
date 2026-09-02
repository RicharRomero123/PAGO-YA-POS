using CommunityToolkit.Mvvm.ComponentModel;
using PagoYa.Core.Enums;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Línea del carrito de la venta en curso. Notifica al padre (CobroRapidoViewModel)
/// cuando cambia la cantidad para recalcular subtotal/IGV/total.
/// Al confirmar la venta se mapea a <see cref="PagoYa.Core.Entidades.DetalleVenta"/>.
/// </summary>
public partial class CarritoItemViewModel : ObservableObject
{
    /// <summary>Callback que dispara el recálculo de totales en el VM padre.</summary>
    public Action? AlCambiarCantidad { get; set; }

    /// <summary>Id del producto en BD (Guid.Empty para líneas de diseño).</summary>
    public Guid ProductoId { get; init; }

    public string Nombre { get; init; } = "";
    public decimal PrecioUnitario { get; init; }

    // --- Metadatos de habitación (si esta línea es un alquiler de cuarto) ---
    /// <summary>True si la línea es una habitación alquilada (no un producto de inventario).</summary>
    public bool EsHabitacion { get; init; }
    /// <summary>Id de la habitación alquilada (cuando <see cref="EsHabitacion"/>).</summary>
    public Guid HabitacionId { get; init; }
    /// <summary>Número de la habitación (para el registro de la estadía).</summary>
    public string HabitacionNumero { get; init; } = "";
    /// <summary>Modalidad del alquiler (noche/hora).</summary>
    public TipoCobroHospedaje TipoCobro { get; init; }
    public string HuespedNombre { get; init; } = "";
    public string HuespedDocumento { get; init; } = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ImporteLinea))]
    private int _cantidad = 1;

    public decimal ImporteLinea => PrecioUnitario * Cantidad;

    partial void OnCantidadChanged(int value) => AlCambiarCantidad?.Invoke();
}
