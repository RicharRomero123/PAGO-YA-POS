namespace PagoYa.Invoicing.Sunat;

/// <summary>
/// Ambiente de emisión SUNAT. Controla a dónde se transmite el comprobante.
/// </summary>
public enum AmbienteSunat
{
    /// <summary>Sin red: se firma el UBL y se genera un CDR ACEPTADO local. Para
    /// operar/probar antes de tener credenciales SOL o durante cortes de internet.</summary>
    Simulado = 0,

    /// <summary>Homologación SUNAT (beta). Endpoints de pruebas.</summary>
    Beta = 1,

    /// <summary>Producción SUNAT / OSE real.</summary>
    Produccion = 2
}

/// <summary>
/// Datos del emisor y parámetros de facturación electrónica. En una app real se
/// alimentan desde Configuración (RUC, razón social) + el certificado digital
/// (.pfx) y la Clave SOL del cliente. NUNCA se versionan credenciales.
/// </summary>
public sealed class OpcionesEmisor
{
    /// <summary>RUC del emisor (11 dígitos).</summary>
    public string Ruc { get; set; } = string.Empty;

    /// <summary>Razón social del emisor.</summary>
    public string RazonSocial { get; set; } = string.Empty;

    /// <summary>Nombre comercial (opcional).</summary>
    public string? NombreComercial { get; set; }

    /// <summary>Dirección fiscal (línea completa).</summary>
    public string Direccion { get; set; } = string.Empty;

    /// <summary>Ubigeo INEI de 6 dígitos del domicilio fiscal (ej. "150101" Lima).</summary>
    public string Ubigeo { get; set; } = "150101";

    /// <summary>Serie para Boletas (Catálogo: empieza con "B", ej. "B001").</summary>
    public string SerieBoleta { get; set; } = "B001";

    /// <summary>Serie para Facturas (empieza con "F", ej. "F001").</summary>
    public string SerieFactura { get; set; } = "F001";

    /// <summary>Moneda ISO-4217 (Perú: PEN).</summary>
    public string Moneda { get; set; } = "PEN";

    /// <summary>Tasa de IGV vigente (0.18 = 18%).</summary>
    public decimal TasaIgv { get; set; } = 0.18m;

    /// <summary>Ambiente de transmisión.</summary>
    public AmbienteSunat Ambiente { get; set; } = AmbienteSunat.Simulado;

    /// <summary>Ruta del certificado digital .pfx del emisor (fuera de git).</summary>
    public string? CertificadoPfxPath { get; set; }

    /// <summary>Clave del .pfx.</summary>
    public string? CertificadoPassword { get; set; }

    /// <summary>Carpeta donde se guardan los XML firmados y CDR emitidos.</summary>
    public string CarpetaSalida { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PagoYa", "comprobantes");
}

/// <summary>
/// Datos del receptor (cliente) del comprobante. Para Boletas de bajo monto se
/// admite un cliente genérico; para Facturas SUNAT exige RUC (6) del adquirente.
/// </summary>
public sealed class DatosReceptor
{
    /// <summary>Código de Catálogo 06 de SUNAT: 0=sin doc, 1=DNI, 6=RUC.</summary>
    public string TipoDocumento { get; set; } = "1";

    /// <summary>Número de documento (DNI/RUC). "00000000" para cliente varios.</summary>
    public string NumeroDocumento { get; set; } = "00000000";

    /// <summary>Nombre o razón social del receptor.</summary>
    public string Nombre { get; set; } = "CLIENTE VARIOS";

    /// <summary>Receptor genérico para boletas sin cliente identificado.</summary>
    public static DatosReceptor Generico() => new();
}
