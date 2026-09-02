using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Contratos;

/// <summary>
/// Persistencia del módulo de salón (rubro restaurante): mesas, comandas/pedidos
/// abiertos y sus líneas de consumo. Implementa: PagoYa.Data (SQLite: tablas
/// 'mesas', 'pedidos', 'pedido_lineas').
/// </summary>
public interface IMesaRepository
{
    // --- Mesas (maestro) ---

    /// <summary>Lista las mesas (por defecto solo activas), ordenadas por zona y número.</summary>
    Task<IReadOnlyList<Mesa>> ListarMesasAsync(bool soloActivas = true, CancellationToken ct = default);

    /// <summary>Obtiene una mesa por Id, o null.</summary>
    Task<Mesa?> ObtenerMesaAsync(Guid id, CancellationToken ct = default);

    /// <summary>Inserta o actualiza una mesa (upsert por Id).</summary>
    Task GuardarMesaAsync(Mesa mesa, CancellationToken ct = default);

    /// <summary>Marca una mesa como inactiva (no la borra).</summary>
    Task DesactivarMesaAsync(Guid id, CancellationToken ct = default);

    /// <summary>Cambia solo el estado operativo de la mesa (mapa del salón).</summary>
    Task CambiarEstadoMesaAsync(Guid id, EstadoMesa estado, CancellationToken ct = default);

    // --- Pedidos (comandas / cuentas) ---

    /// <summary>Pedido abierto de una mesa (con sus líneas cargadas), o null si está libre.</summary>
    Task<Pedido?> ObtenerPedidoAbiertoAsync(Guid mesaId, CancellationToken ct = default);

    /// <summary>Obtiene un pedido por Id (con líneas), o null.</summary>
    Task<Pedido?> ObtenerPedidoAsync(Guid pedidoId, CancellationToken ct = default);

    /// <summary>Inserta o actualiza la cabecera del pedido (upsert por Id).</summary>
    Task GuardarPedidoAsync(Pedido pedido, CancellationToken ct = default);

    // --- Líneas de la comanda ---

    /// <summary>Lista las líneas de un pedido, en orden de creación.</summary>
    Task<IReadOnlyList<PedidoLinea>> ListarLineasAsync(Guid pedidoId, CancellationToken ct = default);

    /// <summary>Agrega una línea al pedido.</summary>
    Task AgregarLineaAsync(PedidoLinea linea, CancellationToken ct = default);

    /// <summary>Quita una línea del pedido.</summary>
    Task QuitarLineaAsync(Guid lineaId, CancellationToken ct = default);

    /// <summary>Marca como enviadas a cocina todas las líneas pendientes del pedido.</summary>
    Task MarcarLineasEnviadasAsync(Guid pedidoId, CancellationToken ct = default);

    /// <summary>Suma de los importes de las líneas del pedido.</summary>
    Task<decimal> TotalPedidoAsync(Guid pedidoId, CancellationToken ct = default);
}
