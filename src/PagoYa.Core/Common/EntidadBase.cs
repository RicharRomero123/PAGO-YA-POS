namespace PagoYa.Core.Common;

/// <summary>
/// Base para todas las entidades del dominio.
///
/// Decisión de arquitectura: usamos <see cref="Guid"/> como identidad (PK)
/// almacenado como TEXT en SQLite. Motivo: evitar colisiones de IDs entre
/// múltiples cajas/sedes que operan offline y luego sincronizan a la nube
/// (multi-site). Un autoincrement local generaría IDs duplicados al
/// consolidar. El UUID se genera en el cliente en el momento de creación.
/// </summary>
public abstract class EntidadBase
{
    /// <summary>Identificador único global. Se genera en el cliente (offline-first).</summary>
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>Fecha/hora de creación en UTC. Base para orden y sincronización.</summary>
    public DateTime CreadoUtc { get; set; } = DateTime.UtcNow;

    /// <summary>Fecha/hora de última modificación en UTC. Útil para resolución de conflictos (last-write-wins).</summary>
    public DateTime ActualizadoUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Identidad de la caja/sede que originó el registro. Clave para el
    /// escenario multi-site: permite rastrear el origen al consolidar.
    /// </summary>
    public string OrigenCajaId { get; set; } = string.Empty;
}
