using System.IO;
using System.Text.Json;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Configuración local persistente del POS (datos del negocio + impresora).
/// Es data de la MÁQUINA (no roaming): vive junto a la BD en %LocalAppData%.
/// Los datos del negocio encabezan el ticket ESC/POS; la impresora y el ancho
/// de papel determinan a dónde y cómo se imprime.
/// </summary>
public sealed class ConfiguracionNegocio
{
    public string NombreNegocio { get; set; } = "PagoYa Demo";

    /// <summary>
    /// Rubro/giro del negocio elegido al crear la cuenta (clave: bodega,
    /// restaurante, cafeteria, polleria, farmacia, ferreteria, licoreria, hotel,
    /// otro). Determina la plantilla precargada y algunos textos del POS.
    /// </summary>
    public string Rubro { get; set; } = "bodega";

    /// <summary>
    /// Categorías de producto creadas por el dueño (además de las sugeridas por el
    /// rubro). Persisten aquí para reaparecer en el selector de categoría del
    /// inventario en cada arranque. Se guardan en orden de creación, sin duplicar.
    /// </summary>
    public List<string> CategoriasPersonalizadas { get; set; } = new();

    public string Ruc { get; set; } = "";
    public string Direccion { get; set; } = "";
    public string Telefono { get; set; } = "";
    public string PieTicket { get; set; } = "¡Gracias por su compra!";

    /// <summary>Ruta local al logo del negocio (se muestra en la vista previa del ticket).</summary>
    public string? LogoRuta { get; set; }

    /// <summary>Nombre exacto de la impresora en Windows. Vacío/null = predeterminada.</summary>
    public string? NombreImpresora { get; set; }

    /// <summary>Ancho de papel térmico en mm: 58 o 80. Define las columnas del ticket.</summary>
    public int AnchoPapelMm { get; set; } = 80;

    /// <summary>
    /// Si al cobrar en efectivo la impresora debe pulsar la apertura del cajón
    /// portamonedas (ESC/POS). true por defecto. Desactívalo si el negocio no
    /// tiene cajón conectado a la impresora térmica.
    /// </summary>
    public bool AbrirCajonEnEfectivo { get; set; } = true;

    /// <summary>
    /// Modo táctil: muestra un teclado numérico en pantalla en Cobro Rápido para
    /// digitar montos rápido en monitores táctiles. Se puede activar desde la
    /// misma pantalla de cobro o en Configuración.
    /// </summary>
    public bool ModoTactil { get; set; }

    /// <summary>
    /// URL base del backend de sincronización Cloud (ej. https://api.pagoya.pe).
    /// Si está vacía, el respaldo opera en modo local/simulado (offline). La fija
    /// el despliegue/soporte; no es un ajuste típico del dueño de la bodega.
    /// </summary>
    public string? SyncUrlBase { get; set; }

    /// <summary>Columnas de texto según el ancho de papel (58mm≈32, 80mm≈42).</summary>
    public int ColumnasTicket => AnchoPapelMm <= 58 ? 32 : 42;
}

/// <summary>
/// Lee y persiste la <see cref="ConfiguracionNegocio"/>. Implementa: desktop-dev.
/// </summary>
public interface IConfiguracionStore
{
    /// <summary>Carga la configuración guardada, o null si aún no existe.</summary>
    ConfiguracionNegocio? Leer();

    /// <summary>Persiste la configuración (sobrescribe).</summary>
    void Guardar(ConfiguracionNegocio config);
}

/// <summary>
/// Implementación de <see cref="IConfiguracionStore"/> basada en un archivo JSON
/// en %LocalAppData%\PagoYa\config.json. No se cifra: son datos del negocio que
/// el propio dueño imprime en cada ticket (a diferencia del token de licencia,
/// que sí va cifrado con DPAPI en <see cref="LicenseStoreArchivo"/>).
/// </summary>
public sealed class ConfiguracionStoreArchivo : IConfiguracionStore
{
    private static readonly JsonSerializerOptions Opciones = new() { WriteIndented = true };

    private readonly string _rutaArchivo;

    public ConfiguracionStoreArchivo()
    {
        var carpeta = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PagoYa");
        Directory.CreateDirectory(carpeta);
        _rutaArchivo = Path.Combine(carpeta, "config.json");
    }

    /// <inheritdoc />
    public ConfiguracionNegocio? Leer()
    {
        if (!File.Exists(_rutaArchivo)) return null;
        try
        {
            var json = File.ReadAllText(_rutaArchivo);
            return string.IsNullOrWhiteSpace(json)
                ? null
                : JsonSerializer.Deserialize<ConfiguracionNegocio>(json, Opciones);
        }
        catch (Exception ex) when (ex is IOException or JsonException)
        {
            // Config corrupta o ilegible: se degrada a valores por defecto.
            return null;
        }
    }

    /// <inheritdoc />
    public void Guardar(ConfiguracionNegocio config)
    {
        var json = JsonSerializer.Serialize(config, Opciones);
        File.WriteAllText(_rutaArchivo, json);
    }
}
