namespace PagoYa.Core.Enums;

/// <summary>Estado del ciclo de vida de una <see cref="Entidades.Venta"/>.</summary>
public enum EstadoVenta
{
    /// <summary>Venta registrada y pagada.</summary>
    Completada = 0,

    /// <summary>Venta anulada (reversa). Se conserva por trazabilidad.</summary>
    Anulada = 1
}
