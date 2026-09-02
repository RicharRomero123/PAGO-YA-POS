using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Sesión de caja (turno de arqueo). Representa el periodo entre la apertura
/// y el cierre de caja de un cajero. Agrupa ventas y movimientos de efectivo.
/// </summary>
public class Caja : EntidadBase
{
    /// <summary>Nombre/etiqueta de la caja física o terminal (ej. "Caja 1").</summary>
    public string Nombre { get; set; } = "Caja 1";

    /// <summary>Nombre del cajero/usuario que abrió la sesión.</summary>
    public string Cajero { get; set; } = string.Empty;

    /// <summary>Estado (Abierta / Cerrada).</summary>
    public EstadoCaja Estado { get; set; } = EstadoCaja.Abierta;

    /// <summary>Monto de apertura (fondo inicial en efectivo).</summary>
    public decimal MontoApertura { get; set; }

    /// <summary>Fecha/hora de apertura.</summary>
    public DateTime FechaApertura { get; set; } = DateTime.Now;

    /// <summary>Fecha/hora de cierre (null mientras esté abierta).</summary>
    public DateTime? FechaCierre { get; set; }

    /// <summary>Monto contado al cierre (arqueo real). Null hasta cerrar.</summary>
    public decimal? MontoCierre { get; set; }

    /// <summary>Diferencia entre lo esperado y lo contado (sobrante/faltante). Null hasta cerrar.</summary>
    public decimal? Diferencia { get; set; }
}
