using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.Servicios.Impresion;

/// <summary>
/// Servicio de impresión de tickets térmicos (nota de venta interna).
/// Implementa: desktop-dev (ESC/POS crudo por spooler).
/// </summary>
public interface ITicketPrinter
{
    /// <summary>
    /// Imprime el ticket de una <see cref="Venta"/>. No lanza si la impresión
    /// falla por hardware; devuelve el resultado para que la UI decida si
    /// avisar (la venta ya está persistida, el ticket es secundario).
    /// </summary>
    Task<ResultadoImpresion> ImprimirTicketVentaAsync(Venta venta, CancellationToken ct = default);

    /// <summary>
    /// Envía el pulso de apertura del cajón portamonedas (ESC/POS "ESC p"). El
    /// cajón cuelga del conector RJ11/RJ12 de la impresora térmica, así que abrirlo
    /// es enviar un pulso a la misma impresora. Se usa para el botón "Probar cajón"
    /// y de forma automática al cobrar en efectivo (ver <see cref="DatosNegocio.AbrirCajonEnEfectivo"/>).
    /// </summary>
    Task<ResultadoImpresion> AbrirCajonAsync(CancellationToken ct = default);
}

/// <summary>Resultado de un intento de impresión de ticket.</summary>
public sealed record ResultadoImpresion(bool Exito, string? Mensaje)
{
    public static ResultadoImpresion Ok() => new(true, null);
    public static ResultadoImpresion Fallo(string mensaje) => new(false, mensaje);
}

/// <summary>
/// Datos del negocio que encabezan el ticket. Se persisten vía
/// <see cref="Servicios.IConfiguracionStore"/> y se materializan como singleton en
/// CompositionRoot. Las propiedades son mutables a propósito: al guardar la
/// pantalla de Configuración se actualiza ESTA MISMA instancia, de modo que la
/// impresión refleja los cambios sin reiniciar la app.
/// </summary>
public sealed class DatosNegocio
{
    public string Nombre { get; set; } = "PagoYa";
    public string Ruc { get; set; } = "";
    public string Direccion { get; set; } = "";
    public string Telefono { get; set; } = "";
    public string PieTicket { get; set; } = "¡Gracias por su compra!";

    /// <summary>Ruta local al logo del negocio (para la vista previa del ticket).</summary>
    public string? LogoRuta { get; set; }

    /// <summary>
    /// Nombre de la impresora térmica en Windows. Si es null/vacío se usa la
    /// impresora predeterminada del sistema.
    /// </summary>
    public string? NombreImpresora { get; set; }

    /// <summary>Columnas de texto del ticket (58mm≈32, 80mm≈42). Ver ancho de papel.</summary>
    public int ColumnasTicket { get; set; } = 42;

    /// <summary>
    /// Si la impresora debe pulsar la apertura del cajón portamonedas al cobrar en
    /// efectivo. true por defecto (comportamiento esperado en una bodega). Si el
    /// negocio no tiene cajón conectado, se puede desactivar en Configuración.
    /// </summary>
    public bool AbrirCajonEnEfectivo { get; set; } = true;
}
