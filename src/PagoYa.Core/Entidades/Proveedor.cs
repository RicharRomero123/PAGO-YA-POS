using PagoYa.Core.Common;

namespace PagoYa.Core.Entidades;

/// <summary>
/// Proveedor del negocio (distribuidor/mayorista). Los productos del inventario
/// pueden vincularse a un proveedor para saber a quién reabastecer.
/// </summary>
public class Proveedor : EntidadBase
{
    /// <summary>Razón social o nombre comercial del proveedor.</summary>
    public string Nombre { get; set; } = string.Empty;

    /// <summary>RUC del proveedor (opcional).</summary>
    public string? Ruc { get; set; }

    /// <summary>Persona de contacto (opcional).</summary>
    public string? Contacto { get; set; }

    /// <summary>Teléfono / WhatsApp del proveedor.</summary>
    public string? Telefono { get; set; }

    /// <summary>Dirección del proveedor (opcional).</summary>
    public string? Direccion { get; set; }

    /// <summary>Notas internas (condiciones de pago, días de reparto, etc.).</summary>
    public string? Notas { get; set; }

    /// <summary>Proveedor activo/visible.</summary>
    public bool Activo { get; set; } = true;
}
