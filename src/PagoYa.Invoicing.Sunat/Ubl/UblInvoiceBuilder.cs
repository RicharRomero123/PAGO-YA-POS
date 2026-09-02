using System.Globalization;
using System.Xml;
using System.Xml.Linq;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Invoicing.Sunat.Ubl;

/// <summary>
/// Construye el XML <b>UBL 2.1</b> de un comprobante (Boleta/Factura) a partir de
/// una <see cref="Venta"/>, siguiendo la estructura que exige SUNAT: extensión
/// para la firma, emisor/receptor, IGV desagregado por línea y totales.
///
/// Los precios de PagoYa YA incluyen IGV; aquí se desagrega el valor de venta
/// (sin IGV) y el IGV por línea, y se cuadran los totales del documento.
///
/// Nota: es un UBL representativo y bien formado (nodos esenciales del Catálogo
/// SUNAT). La conformidad total (todas las leyendas, montos y catálogos) es
/// iterativa; los ganchos están listos para extenderla.
/// </summary>
public sealed class UblInvoiceBuilder
{
    // Espacios de nombres UBL/SUNAT.
    private static readonly XNamespace Inv = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2";
    private static readonly XNamespace Cbc = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2";
    private static readonly XNamespace Cac = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2";
    private static readonly XNamespace Ext = "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";
    private static readonly XNamespace Ds = "http://www.w3.org/2000/09/xmldsig#";

    private static readonly CultureInfo Inv0 = CultureInfo.InvariantCulture;

    private readonly OpcionesEmisor _emisor;

    public UblInvoiceBuilder(OpcionesEmisor emisor) => _emisor = emisor;

    /// <summary>Resultado del armado: documento firmable + totales calculados.</summary>
    public sealed record Resultado(XmlDocument Documento, decimal ValorVenta, decimal Igv, decimal Total);

    /// <summary>
    /// Arma el UBL para la venta. El elemento de firma queda VACÍO
    /// (ext:ExtensionContent); lo llena el firmador con el ds:Signature.
    /// </summary>
    public Resultado Construir(Venta venta, TipoComprobante tipo, string serie, int correlativo, DatosReceptor receptor)
    {
        var tasa = _emisor.TasaIgv;
        var moneda = _emisor.Moneda;

        // --- Líneas: desagregar IGV desde el importe con IGV ---
        var lineas = new List<XElement>();
        decimal totValorVenta = 0m, totIgv = 0m;
        int i = 1;
        foreach (var d in venta.Detalles)
        {
            var importeConIgv = d.Importe;
            var valorVenta = decimal.Round(importeConIgv / (1 + tasa), 2, MidpointRounding.AwayFromZero);
            var igvLinea = importeConIgv - valorVenta;
            var cantidad = d.Cantidad == 0 ? 1 : d.Cantidad;
            var valorUnitario = decimal.Round(valorVenta / cantidad, 2, MidpointRounding.AwayFromZero);
            var precioUnitarioConIgv = decimal.Round(importeConIgv / cantidad, 2, MidpointRounding.AwayFromZero);

            totValorVenta += valorVenta;
            totIgv += igvLinea;

            lineas.Add(new XElement(Cac + "InvoiceLine",
                new XElement(Cbc + "ID", i),
                new XElement(Cbc + "InvoicedQuantity", new XAttribute("unitCode", "NIU"), Num(cantidad)),
                new XElement(Cbc + "LineExtensionAmount", MonedaAttr(moneda), Num(valorVenta)),
                new XElement(Cac + "PricingReference",
                    new XElement(Cac + "AlternativeConditionPrice",
                        new XElement(Cbc + "PriceAmount", MonedaAttr(moneda), Num(precioUnitarioConIgv)),
                        new XElement(Cbc + "PriceTypeCode", "01"))), // 01 = precio unitario (incluye IGV)
                LineaTaxTotal(valorVenta, igvLinea, tasa, moneda),
                new XElement(Cac + "Item",
                    new XElement(Cbc + "Description", new XCData(d.DescripcionProducto))),
                new XElement(Cac + "Price",
                    new XElement(Cbc + "PriceAmount", MonedaAttr(moneda), Num(valorUnitario)))));
            i++;
        }

        var total = totValorVenta + totIgv;

        var doc = new XDocument(
            new XDeclaration("1.0", "UTF-8", null),
            new XElement(Inv + "Invoice",
                new XAttribute(XNamespace.Xmlns + "cbc", Cbc.NamespaceName),
                new XAttribute(XNamespace.Xmlns + "cac", Cac.NamespaceName),
                new XAttribute(XNamespace.Xmlns + "ext", Ext.NamespaceName),
                new XAttribute(XNamespace.Xmlns + "ds", Ds.NamespaceName),

                // Extensión para la firma (ExtensionContent lo llena el firmador).
                new XElement(Ext + "UBLExtensions",
                    new XElement(Ext + "UBLExtension",
                        new XElement(Ext + "ExtensionContent"))),

                new XElement(Cbc + "UBLVersionID", "2.1"),
                new XElement(Cbc + "CustomizationID", "2.0"),
                new XElement(Cbc + "ID", $"{serie}-{correlativo:D8}"),
                new XElement(Cbc + "IssueDate", venta.FechaHora.ToString("yyyy-MM-dd", Inv0)),
                new XElement(Cbc + "IssueTime", venta.FechaHora.ToString("HH:mm:ss", Inv0)),
                new XElement(Cbc + "InvoiceTypeCode",
                    new XAttribute("listID", "0101"), CodigoTipo(tipo)),
                new XElement(Cbc + "DocumentCurrencyCode", moneda),

                Emisor(),
                Receptor(receptor),
                DocumentoTaxTotal(totIgv, totValorVenta, tasa, moneda),
                new XElement(Cac + "LegalMonetaryTotal",
                    new XElement(Cbc + "LineExtensionAmount", MonedaAttr(moneda), Num(totValorVenta)),
                    new XElement(Cbc + "TaxInclusiveAmount", MonedaAttr(moneda), Num(total)),
                    new XElement(Cbc + "PayableAmount", MonedaAttr(moneda), Num(total))),
                lineas));

        // XDocument -> XmlDocument para firmar (PreserveWhitespace estable para C14N).
        var xmlDoc = new XmlDocument { PreserveWhitespace = true };
        xmlDoc.LoadXml(doc.ToString(SaveOptions.DisableFormatting));

        return new Resultado(xmlDoc, totValorVenta, totIgv, total);
    }

    private XElement Emisor() =>
        new(Cac + "AccountingSupplierParty",
            new XElement(Cac + "Party",
                new XElement(Cac + "PartyIdentification",
                    new XElement(Cbc + "ID", new XAttribute("schemeID", "6"), _emisor.Ruc)),
                new XElement(Cac + "PartyName",
                    new XElement(Cbc + "Name", new XCData(_emisor.NombreComercial ?? _emisor.RazonSocial))),
                new XElement(Cac + "PartyLegalEntity",
                    new XElement(Cbc + "RegistrationName", new XCData(_emisor.RazonSocial)),
                    new XElement(Cac + "RegistrationAddress",
                        new XElement(Cbc + "ID", _emisor.Ubigeo),
                        new XElement(Cac + "AddressLine",
                            new XElement(Cbc + "Line", new XCData(_emisor.Direccion)))))));

    private XElement Receptor(DatosReceptor r) =>
        new(Cac + "AccountingCustomerParty",
            new XElement(Cac + "Party",
                new XElement(Cac + "PartyIdentification",
                    new XElement(Cbc + "ID", new XAttribute("schemeID", r.TipoDocumento), r.NumeroDocumento)),
                new XElement(Cac + "PartyLegalEntity",
                    new XElement(Cbc + "RegistrationName", new XCData(r.Nombre)))));

    /// <summary>TaxTotal a nivel de documento (total IGV + subtotal gravado).</summary>
    private XElement DocumentoTaxTotal(decimal igv, decimal gravado, decimal tasa, string moneda) =>
        new(Cac + "TaxTotal",
            new XElement(Cbc + "TaxAmount", MonedaAttr(moneda), Num(igv)),
            new XElement(Cac + "TaxSubtotal",
                new XElement(Cbc + "TaxableAmount", MonedaAttr(moneda), Num(gravado)),
                new XElement(Cbc + "TaxAmount", MonedaAttr(moneda), Num(igv)),
                CategoriaIgv(tasa)));

    /// <summary>TaxTotal a nivel de línea.</summary>
    private XElement LineaTaxTotal(decimal gravado, decimal igv, decimal tasa, string moneda) =>
        new(Cac + "TaxTotal",
            new XElement(Cbc + "TaxAmount", MonedaAttr(moneda), Num(igv)),
            new XElement(Cac + "TaxSubtotal",
                new XElement(Cbc + "TaxableAmount", MonedaAttr(moneda), Num(gravado)),
                new XElement(Cbc + "TaxAmount", MonedaAttr(moneda), Num(igv)),
                CategoriaIgv(tasa)));

    /// <summary>Categoría de impuesto IGV (Catálogo 05 SUNAT: IGV = 1000, afecto = "S").</summary>
    private static XElement CategoriaIgv(decimal tasa) =>
        new(Cac + "TaxCategory",
            new XElement(Cbc + "Percent", Num(tasa * 100)),
            new XElement(Cbc + "TaxExemptionReasonCode", "10"), // 10 = gravado - operación onerosa
            new XElement(Cac + "TaxScheme",
                new XElement(Cbc + "ID", "1000"),
                new XElement(Cbc + "Name", "IGV"),
                new XElement(Cbc + "TaxTypeCode", "VAT")));

    private static XAttribute MonedaAttr(string moneda) => new("currencyID", moneda);

    private static string Num(decimal v) => v.ToString("0.00", Inv0);

    /// <summary>Catálogo 01 SUNAT: Factura = "01", Boleta = "03".</summary>
    private static string CodigoTipo(TipoComprobante tipo) => tipo switch
    {
        TipoComprobante.Factura => "01",
        TipoComprobante.Boleta => "03",
        _ => "03"
    };
}
