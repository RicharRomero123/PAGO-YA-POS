using System.Security.Cryptography.X509Certificates;
using System.Security.Cryptography.Xml;
using System.Xml;

namespace PagoYa.Invoicing.Sunat.Firma;

/// <summary>
/// Firma un documento UBL con <b>XML-DSig enveloped (RSA-SHA256)</b> e inserta el
/// <c>ds:Signature</c> dentro de <c>ext:UBLExtensions/ext:UBLExtension/ext:ExtensionContent</c>,
/// como exige SUNAT. Devuelve el DigestValue (hash del comprobante) que se guarda
/// en <c>Comprobante.HashXml</c> y viaja en el resumen para soporte.
/// </summary>
public sealed class FirmadorXml
{
    private const string ExtNs = "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";
    private const string SignatureId = "SignPagoYa";

    /// <summary>
    /// Firma <paramref name="doc"/> en sitio y devuelve el DigestValue en base64.
    /// </summary>
    public string Firmar(XmlDocument doc, X509Certificate2 certificado)
    {
        var rsa = certificado.GetRSAPrivateKey()
            ?? throw new InvalidOperationException("El certificado no expone clave privada RSA.");

        var signedXml = new SignedXml(doc) { SigningKey = rsa };
        signedXml.SignedInfo!.CanonicalizationMethod = SignedXml.XmlDsigC14NTransformUrl;
        signedXml.SignedInfo.SignatureMethod = SignedXml.XmlDsigRSASHA256Url;

        // Referencia a todo el documento con transform enveloped (excluye la propia firma).
        var reference = new Reference { Uri = "", DigestMethod = SignedXml.XmlDsigSHA256Url };
        reference.AddTransform(new XmlDsigEnvelopedSignatureTransform());
        reference.AddTransform(new XmlDsigC14NTransform());
        signedXml.AddReference(reference);

        var keyInfo = new KeyInfo();
        keyInfo.AddClause(new KeyInfoX509Data(certificado));
        signedXml.KeyInfo = keyInfo;
        signedXml.Signature.Id = SignatureId;

        signedXml.ComputeSignature();
        var firma = signedXml.GetXml();

        var extensionContent = BuscarExtensionContent(doc);
        extensionContent.AppendChild(doc.ImportNode(firma, deep: true));

        var digest = ((Reference)signedXml.SignedInfo.References[0]!).DigestValue
            ?? throw new InvalidOperationException("La firma no produjo DigestValue.");
        return Convert.ToBase64String(digest);
    }

    /// <summary>
    /// Verifica la firma enveloped del documento (usa la clave del KeyInfo). SUNAT
    /// hace esto del lado servidor; lo exponemos para validación local/pruebas.
    /// </summary>
    public static bool Verificar(XmlDocument doc)
    {
        var nsm = new XmlNamespaceManager(doc.NameTable);
        nsm.AddNamespace("ds", SignedXml.XmlDsigNamespaceUrl);
        if (doc.SelectSingleNode("//ds:Signature", nsm) is not XmlElement firma)
            return false;

        var signedXml = new SignedXml(doc);
        signedXml.LoadXml(firma);
        return signedXml.CheckSignature();
    }

    private static XmlElement BuscarExtensionContent(XmlDocument doc)
    {
        var nsm = new XmlNamespaceManager(doc.NameTable);
        nsm.AddNamespace("ext", ExtNs);
        return doc.SelectSingleNode("//ext:ExtensionContent", nsm) as XmlElement
            ?? throw new InvalidOperationException(
                "El UBL no contiene ext:ExtensionContent para alojar la firma.");
    }
}
