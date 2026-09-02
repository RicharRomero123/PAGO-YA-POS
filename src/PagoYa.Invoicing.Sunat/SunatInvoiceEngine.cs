using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Invoicing.Sunat.Firma;
using PagoYa.Invoicing.Sunat.Transporte;
using PagoYa.Invoicing.Sunat.Ubl;

namespace PagoYa.Invoicing.Sunat;

/// <summary>
/// Motor real de facturación electrónica SUNAT. Orquesta el pipeline completo:
///   1. Construye el XML UBL 2.1 (Boleta/Factura) desde la <see cref="Venta"/>.
///   2. Lo firma con XML-DSig (certificado X509).
///   3. Guarda el XML firmado en disco.
///   4. Lo transmite (SUNAT/OSE, PSE o modo simulado) y lee el CDR.
///   5. Puebla el <see cref="Comprobante"/> (serie, correlativo, hash, estado, CDR).
///
/// Se instancia SOLO cuando la licencia habilita el flag "invoicing"
/// (feature-gating en CompositionRoot).
/// </summary>
public sealed class SunatInvoiceEngine : IInvoiceEngine
{
    private readonly OpcionesEmisor _emisor;
    private readonly UblInvoiceBuilder _builder;
    private readonly FirmadorXml _firmador;
    private readonly ISunatTransport _transporte;
    private readonly IContadorComprobantes _contador;
    private readonly X509Certificate2? _certificadoInyectado;

    /// <summary>Constructor completo (DI / pruebas).</summary>
    public SunatInvoiceEngine(
        OpcionesEmisor emisor,
        UblInvoiceBuilder builder,
        FirmadorXml firmador,
        ISunatTransport transporte,
        IContadorComprobantes contador,
        X509Certificate2? certificado = null)
    {
        _emisor = emisor;
        _builder = builder;
        _firmador = firmador;
        _transporte = transporte;
        _contador = contador;
        _certificadoInyectado = certificado;
    }

    /// <summary>Constructor de conveniencia: arma las dependencias por defecto
    /// según el ambiente configurado. Base para el wiring en el cliente.</summary>
    public SunatInvoiceEngine(OpcionesEmisor emisor)
        : this(emisor, new UblInvoiceBuilder(emisor), new FirmadorXml(),
               CrearTransporte(emisor), new ContadorEnMemoria())
    {
    }

    /// <inheritdoc />
    public bool PuedeEmitir => true;

    /// <inheritdoc />
    public async Task<ResultadoEmision> EmitirComprobanteAsync(Venta venta, CancellationToken ct = default)
    {
        if (venta.Detalles.Count == 0)
            return new ResultadoEmision { Aceptado = false, Mensaje = "La venta no tiene líneas para facturar." };

        // Por ahora emitimos Boleta (la Venta no captura RUC del cliente). El
        // gancho para Factura queda listo vía el receptor con RUC.
        var tipo = TipoComprobante.Boleta;
        var serie = _emisor.SerieBoleta;
        var correlativo = _contador.SiguienteCorrelativo(tipo, serie);
        var receptor = DatosReceptor.Generico();

        var ubl = _builder.Construir(venta, tipo, serie, correlativo, receptor);

        var (certificado, propio) = ResolverCertificado();
        string hash;
        try
        {
            hash = _firmador.Firmar(ubl.Documento, certificado);
        }
        finally
        {
            if (propio) certificado.Dispose();
        }

        var nombreArchivo = $"{_emisor.Ruc}-{CodigoDoc(tipo)}-{serie}-{correlativo:D8}";
        var rutaXml = GuardarXml(ubl.Documento.OuterXml, nombreArchivo);

        var cdr = await _transporte.EnviarAsync(nombreArchivo, ubl.Documento, tipo, ct);

        var comprobante = new Comprobante
        {
            VentaId = venta.Id,
            Tipo = tipo,
            Serie = serie,
            Correlativo = correlativo,
            DocumentoCliente = receptor.NumeroDocumento,
            NombreCliente = receptor.Nombre,
            Total = ubl.Total,
            HashXml = hash,
            EstadoSunat = cdr.Aceptado ? "ACEPTADO" : "RECHAZADO",
            CodigoCdr = cdr.Codigo,
            RutaXml = rutaXml
        };

        return new ResultadoEmision
        {
            Aceptado = cdr.Aceptado,
            Comprobante = comprobante,
            CodigoCdr = cdr.Codigo,
            Mensaje = cdr.Descripcion
        };
    }

    /// <summary>Guarda el XML firmado; si el disco falla no aborta la emisión.</summary>
    private string? GuardarXml(string xml, string nombreArchivo)
    {
        try
        {
            Directory.CreateDirectory(_emisor.CarpetaSalida);
            var ruta = Path.Combine(_emisor.CarpetaSalida, nombreArchivo + ".xml");
            File.WriteAllText(ruta, xml);
            return ruta;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    /// Resuelve el certificado firmante: el .pfx del emisor si está configurado; en
    /// su defecto (modo Simulado / demo) genera uno autofirmado efímero para que el
    /// pipeline produzca una firma y un DigestValue reales. 'propio' indica si el
    /// motor debe liberarlo.
    /// </summary>
    private (X509Certificate2 cert, bool propio) ResolverCertificado()
    {
        if (_certificadoInyectado is not null)
            return (_certificadoInyectado, false);

        if (!string.IsNullOrWhiteSpace(_emisor.CertificadoPfxPath) && File.Exists(_emisor.CertificadoPfxPath))
            return (new X509Certificate2(_emisor.CertificadoPfxPath, _emisor.CertificadoPassword), true);

        return (GenerarCertificadoEfimero(_emisor.Ruc, _emisor.RazonSocial), true);
    }

    private static X509Certificate2 GenerarCertificadoEfimero(string ruc, string razonSocial)
    {
        using var rsa = RSA.Create(2048);
        var nombre = string.IsNullOrWhiteSpace(razonSocial) ? "PagoYa" : razonSocial;
        var req = new CertificateRequest($"CN={nombre}, SERIALNUMBER={ruc}",
            rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var temporal = req.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(2));
        // Reimportar vía PFX hace la clave privada utilizable por SignedXml.
        return new X509Certificate2(temporal.Export(X509ContentType.Pfx));
    }

    private static ISunatTransport CrearTransporte(OpcionesEmisor emisor) => emisor.Ambiente switch
    {
        AmbienteSunat.Simulado => new TransporteSimulado(),
        // Beta/Producción real requieren inyectar un transporte SOAP-SUNAT o PSE
        // (Nubefact/ApisPeru) con las credenciales del cliente. Ver ISunatTransport.
        _ => throw new NotSupportedException(
            $"El ambiente {emisor.Ambiente} requiere inyectar un ISunatTransport (SOAP SUNAT o PSE). " +
            "Use el constructor completo con el transporte configurado.")
    };

    private static string CodigoDoc(TipoComprobante tipo) => tipo switch
    {
        TipoComprobante.Factura => "01",
        TipoComprobante.Boleta => "03",
        _ => "03"
    };
}
