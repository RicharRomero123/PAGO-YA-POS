using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Xml;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;
using PagoYa.Invoicing.Sunat;
using PagoYa.Invoicing.Sunat.Firma;
using PagoYa.Invoicing.Sunat.Transporte;
using PagoYa.Invoicing.Sunat.Ubl;
using Xunit;

namespace PagoYa.Invoicing.Sunat.Tests;

/// <summary>
/// Pipeline de facturación SUNAT probado offline: construcción UBL 2.1, firma
/// XML-DSig, CDR simulado y poblado del Comprobante. Sin red ni Clave SOL.
/// </summary>
public sealed class FacturacionSunatTests
{
    private const string Cbc = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2";
    private const string Cac = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2";
    private const string Inv = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2";
    private const string Ext = "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";
    private const string Ds = "http://www.w3.org/2000/09/xmldsig#";

    // ------------------------------------------------------------- Fixtures ---

    private static OpcionesEmisor Emisor() => new()
    {
        Ruc = "20512345678",
        RazonSocial = "BODEGA DEMO SAC",
        Direccion = "AV. EJEMPLO 123 - LIMA",
        SerieBoleta = "B001",
        Ambiente = AmbienteSunat.Simulado,
        CarpetaSalida = Path.Combine(Path.GetTempPath(), "pagoya-tests-" + Guid.NewGuid().ToString("N"))
    };

    /// <summary>Certificado autofirmado de prueba con clave utilizable por SignedXml.</summary>
    private static X509Certificate2 CertDePrueba()
    {
        using var rsa = RSA.Create(2048);
        var req = new CertificateRequest("CN=PagoYa Test, SERIALNUMBER=20512345678",
            rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var temp = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(1));
        return new X509Certificate2(temp.Export(X509ContentType.Pfx));
    }

    private static Venta VentaConLineas(params (string desc, decimal cant, decimal precio, decimal importe)[] lineas)
    {
        var v = new Venta { Id = Guid.NewGuid(), Numero = "V-000001", FechaHora = new DateTime(2026, 8, 25, 12, 30, 0) };
        foreach (var (desc, cant, precio, importe) in lineas)
            v.Detalles.Add(new DetalleVenta
            {
                DescripcionProducto = desc, Cantidad = cant, PrecioUnitario = precio, Importe = importe
            });
        var total = v.Detalles.Sum(d => d.Importe);
        v.Total = total;
        v.SubTotal = decimal.Round(total / 1.18m, 2);
        v.Igv = total - v.SubTotal;
        return v;
    }

    private static SunatInvoiceEngine Motor(OpcionesEmisor emisor, X509Certificate2 cert, IContadorComprobantes? contador = null)
        => new(emisor, new UblInvoiceBuilder(emisor), new FirmadorXml(),
               new TransporteSimulado(), contador ?? new ContadorEnMemoria(), cert);

    private static XmlNamespaceManager Nsm(XmlDocument doc)
    {
        var nsm = new XmlNamespaceManager(doc.NameTable);
        nsm.AddNamespace("cbc", Cbc);
        nsm.AddNamespace("cac", Cac);
        nsm.AddNamespace("inv", Inv);
        nsm.AddNamespace("ext", Ext);
        nsm.AddNamespace("ds", Ds);
        return nsm;
    }

    // ------------------------------------------------------- Motor completo ---

    [Fact]
    public async Task Emitir_ProduceComprobanteAceptado_ConHashSerieYCdr()
    {
        var emisor = Emisor();
        using var cert = CertDePrueba();
        var venta = VentaConLineas(("Inca Kola 500ml", 2, 3.50m, 7.00m), ("Pan frances", 10, 0.30m, 3.00m));

        var res = await Motor(emisor, cert).EmitirComprobanteAsync(venta);

        Assert.True(res.Aceptado, res.Mensaje);
        Assert.Equal("0", res.CodigoCdr);
        Assert.NotNull(res.Comprobante);
        Assert.Equal(TipoComprobante.Boleta, res.Comprobante!.Tipo);
        Assert.Equal("B001", res.Comprobante.Serie);
        Assert.Equal(1, res.Comprobante.Correlativo);
        Assert.Equal("ACEPTADO", res.Comprobante.EstadoSunat);
        Assert.False(string.IsNullOrWhiteSpace(res.Comprobante.HashXml));
        Assert.Equal(10.00m, res.Comprobante.Total);
        Assert.Equal(venta.Id, res.Comprobante.VentaId);

        // El XML firmado quedó en disco.
        Assert.NotNull(res.Comprobante.RutaXml);
        Assert.True(File.Exists(res.Comprobante.RutaXml));
        File.Delete(res.Comprobante.RutaXml!);
    }

    [Fact]
    public async Task Correlativos_SonConsecutivosPorSerie()
    {
        var emisor = Emisor();
        using var cert = CertDePrueba();
        var contador = new ContadorEnMemoria();
        var motor = Motor(emisor, cert, contador);

        var r1 = await motor.EmitirComprobanteAsync(VentaConLineas(("A", 1, 5m, 5m)));
        var r2 = await motor.EmitirComprobanteAsync(VentaConLineas(("B", 1, 5m, 5m)));

        Assert.Equal(1, r1.Comprobante!.Correlativo);
        Assert.Equal(2, r2.Comprobante!.Correlativo);
        if (r1.Comprobante.RutaXml is { } p1 && File.Exists(p1)) File.Delete(p1);
        if (r2.Comprobante.RutaXml is { } p2 && File.Exists(p2)) File.Delete(p2);
    }

    [Fact]
    public async Task SinLineas_NoFactura()
    {
        var emisor = Emisor();
        using var cert = CertDePrueba();
        var res = await Motor(emisor, cert).EmitirComprobanteAsync(new Venta { Id = Guid.NewGuid() });
        Assert.False(res.Aceptado);
    }

    [Fact]
    public async Task Deshabilitado_RechazaEmisionConMensajeComercial()
    {
        var res = await new InvoiceEngineDeshabilitado().EmitirComprobanteAsync(new Venta());
        Assert.False(res.Aceptado);
        Assert.Contains("Facturador Pro", res.Mensaje);
    }

    // --------------------------------------------------------- UBL + firma ---

    [Fact]
    public void Ubl_EstructuraCorrecta_ConLineasYTotales()
    {
        var emisor = Emisor();
        var builder = new UblInvoiceBuilder(emisor);
        // 118.00 con IGV => valor venta 100.00, IGV 18.00.
        var venta = VentaConLineas(("Producto gravado", 1, 118.00m, 118.00m));

        var ubl = builder.Construir(venta, TipoComprobante.Boleta, "B001", 7, DatosReceptor.Generico());
        var doc = ubl.Documento;
        var nsm = Nsm(doc);

        Assert.Equal("Invoice", doc.DocumentElement!.LocalName);
        Assert.Equal("B001-00000007", doc.SelectSingleNode("/inv:Invoice/cbc:ID", nsm)!.InnerText);
        Assert.Equal("03", doc.SelectSingleNode("//cbc:InvoiceTypeCode", nsm)!.InnerText);
        Assert.Equal("20512345678", doc.SelectSingleNode("//cac:AccountingSupplierParty//cbc:ID", nsm)!.InnerText);

        var lineasXml = doc.SelectNodes("//cac:InvoiceLine", nsm)!;
        Assert.Equal(1, lineasXml.Count);

        // Desagregación de IGV correcta.
        Assert.Equal(100.00m, ubl.ValorVenta);
        Assert.Equal(18.00m, ubl.Igv);
        Assert.Equal(118.00m, ubl.Total);

        var payable = doc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:PayableAmount", nsm)!;
        Assert.Equal("118.00", payable.InnerText);
        var igvDoc = doc.SelectSingleNode("//cac:TaxTotal/cbc:TaxAmount", nsm)!;
        Assert.Equal("18.00", igvDoc.InnerText);
    }

    [Fact]
    public void Firma_SeInsertaEnExtensionContent_yVerifica()
    {
        var emisor = Emisor();
        using var cert = CertDePrueba();
        var venta = VentaConLineas(("Item", 3, 10m, 30m));

        var ubl = new UblInvoiceBuilder(emisor).Construir(venta, TipoComprobante.Boleta, "B001", 1, DatosReceptor.Generico());
        var hash = new FirmadorXml().Firmar(ubl.Documento, cert);

        Assert.False(string.IsNullOrWhiteSpace(hash));

        var nsm = Nsm(ubl.Documento);
        var firmaEnExtension = ubl.Documento.SelectSingleNode("//ext:ExtensionContent/ds:Signature", nsm);
        Assert.NotNull(firmaEnExtension); // la firma vive dentro de la extensión UBL

        Assert.True(FirmadorXml.Verificar(ubl.Documento));
    }

    [Fact]
    public void FirmaManipulada_NoVerifica()
    {
        var emisor = Emisor();
        using var cert = CertDePrueba();
        var ubl = new UblInvoiceBuilder(emisor).Construir(
            VentaConLineas(("Item", 1, 50m, 50m)), TipoComprobante.Boleta, "B001", 1, DatosReceptor.Generico());
        new FirmadorXml().Firmar(ubl.Documento, cert);

        // Alteramos el total tras firmar: la firma debe dejar de validar.
        var nsm = Nsm(ubl.Documento);
        var payable = (XmlElement)ubl.Documento.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:PayableAmount", nsm)!;
        payable.InnerText = "999.00";

        Assert.False(FirmadorXml.Verificar(ubl.Documento));
    }
}
