using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Estadía (registro de hospedaje) de una habitación: desde el check-in hasta el
/// check-out. Congela los datos del huésped y la tarifa pactada, acumula los
/// consumos (minibar, lavandería…) y, al cerrar, guarda el total cobrado.
/// </summary>
public class EstadiaHabitacion : EntidadBase
{
    /// <summary>Habitación ocupada.</summary>
    public Guid HabitacionId { get; set; }

    /// <summary>Número de habitación congelado (para historial aunque cambie el maestro).</summary>
    public string NumeroHabitacion { get; set; } = string.Empty;

    /// <summary>Nombre del huésped.</summary>
    public string HuespedNombre { get; set; } = string.Empty;

    /// <summary>Documento del huésped (DNI/CE/Pasaporte). Requerido por recepción.</summary>
    public string HuespedDocumento { get; set; } = string.Empty;

    /// <summary>Teléfono/WhatsApp del huésped (opcional).</summary>
    public string? HuespedTelefono { get; set; }

    /// <summary>Cantidad de huéspedes.</summary>
    public int Personas { get; set; } = 1;

    /// <summary>Modalidad de cobro (noche/hora).</summary>
    public TipoCobroHospedaje TipoCobro { get; set; } = TipoCobroHospedaje.Noche;

    /// <summary>Tarifa unitaria pactada (precio noche o precio hora al momento del check-in).</summary>
    public decimal PrecioUnitario { get; set; }

    /// <summary>Momento del check-in (UTC).</summary>
    public DateTime CheckInUtc { get; set; } = DateTime.UtcNow;

    /// <summary>Momento del check-out (UTC). Null mientras la estadía está activa.</summary>
    public DateTime? CheckOutUtc { get; set; }

    /// <summary>Unidades cobradas (noches u horas) calculadas/confirmadas al cerrar.</summary>
    public decimal Unidades { get; set; } = 1;

    /// <summary>Importe del hospedaje (unidades × precio unitario) al cerrar.</summary>
    public decimal MontoHospedaje { get; set; }

    /// <summary>Importe acumulado de consumos cargados a la habitación.</summary>
    public decimal MontoConsumos { get; set; }

    /// <summary>Total cobrado al check-out (hospedaje + consumos).</summary>
    public decimal Total { get; set; }

    /// <summary>Método de pago del check-out (Efectivo/Yape/Tarjeta…). Ver MetodoPago.</summary>
    public int MetodoPago { get; set; }

    /// <summary>Estado de la estadía (activa/cerrada/anulada).</summary>
    public EstadoEstadia Estado { get; set; } = EstadoEstadia.Activa;

    /// <summary>Notas de recepción (placa de auto, observaciones, etc.).</summary>
    public string? Notas { get; set; }
}
