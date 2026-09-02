using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Comanda / cuenta abierta de una mesa (rubro restaurante). Acumula las líneas de
/// consumo (<see cref="PedidoLinea"/>) mientras la mesa está ocupada; al cobrar se
/// genera la <see cref="Venta"/> y el pedido se marca <see cref="EstadoPedido.Cobrada"/>.
/// </summary>
public class Pedido : EntidadBase
{
    /// <summary>Mesa a la que pertenece la cuenta.</summary>
    public Guid MesaId { get; set; }

    /// <summary>Número/nombre de la mesa congelado (para mostrar e imprimir).</summary>
    public string NumeroMesa { get; set; } = string.Empty;

    /// <summary>Correlativo legible del pedido (ej. "P-240829-1230").</summary>
    public string Numero { get; set; } = string.Empty;

    /// <summary>Estado de la comanda.</summary>
    public EstadoPedido Estado { get; set; } = EstadoPedido.Abierta;

    /// <summary>Mozo/usuario que abrió la cuenta.</summary>
    public string Mozo { get; set; } = string.Empty;

    /// <summary>Cantidad de comensales (informativo).</summary>
    public int Comensales { get; set; } = 1;

    /// <summary>Apertura de la cuenta (hora local del negocio).</summary>
    public DateTime FechaApertura { get; set; } = DateTime.Now;

    /// <summary>Cierre de la cuenta (al cobrar o anular). Null mientras esté abierta.</summary>
    public DateTime? FechaCierre { get; set; }

    /// <summary>Total acumulado de la cuenta (cache desnormalizado; suma de líneas).</summary>
    public decimal Total { get; set; }

    /// <summary>Notas generales de la comanda.</summary>
    public string? Notas { get; set; }

    /// <summary>Venta generada al cobrar la mesa (null hasta cobrar).</summary>
    public Guid? VentaId { get; set; }

    /// <summary>Líneas de la cuenta (se cargan aparte por el repositorio).</summary>
    public List<PedidoLinea> Lineas { get; set; } = new();
}
