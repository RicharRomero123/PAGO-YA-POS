using PagoYa.Core.Common;
using PagoYa.Core.Enums;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Mesa del salón (rubro restaurante). Se registra una vez (número, zona,
/// capacidad) y cambia de <see cref="Estado"/> según el mapa del salón. La cuenta
/// de consumo vive en un <see cref="Pedido"/> abierto asociado a la mesa.
/// </summary>
public class Mesa : EntidadBase
{
    /// <summary>Número/nombre visible de la mesa (ej. "1", "Terraza 2").</summary>
    public string Numero { get; set; } = string.Empty;

    /// <summary>Zona/ambiente donde está (para agrupar el mapa): "Salón", "Terraza"…</summary>
    public string? Zona { get; set; }

    /// <summary>Capacidad de comensales (informativo).</summary>
    public int Capacidad { get; set; } = 4;

    /// <summary>Estado operativo actual (mapa del salón).</summary>
    public EstadoMesa Estado { get; set; } = EstadoMesa.Libre;

    /// <summary>Notas de la mesa (ubicación, observaciones).</summary>
    public string? Notas { get; set; }

    /// <summary>Mesa activa/visible en el mapa.</summary>
    public bool Activa { get; set; } = true;

    /// <summary>Zona para agrupar (nunca vacía; "Salón" por defecto).</summary>
    public string ZonaAgrupacion => string.IsNullOrWhiteSpace(Zona) ? "Salón" : Zona!;
}
