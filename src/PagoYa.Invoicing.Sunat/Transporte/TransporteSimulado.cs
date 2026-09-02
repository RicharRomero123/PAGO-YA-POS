using System.Xml;
using PagoYa.Core.Enums;

namespace PagoYa.Invoicing.Sunat.Transporte;

/// <summary>
/// Transporte OFFLINE que no contacta a SUNAT: valida que el documento venga
/// firmado y emite un CDR ACEPTADO local (código "0"). Permite que el negocio
/// siga operando y guardando comprobantes firmados aunque no tenga aún su Clave
/// SOL/certificado o esté sin internet; luego pueden retransmitirse a SUNAT.
/// </summary>
public sealed class TransporteSimulado : ISunatTransport
{
    private const string DsNs = "http://www.w3.org/2000/09/xmldsig#";

    public Task<RespuestaCdr> EnviarAsync(string nombreArchivo, XmlDocument comprobanteFirmado, TipoComprobante tipo, CancellationToken ct = default)
    {
        var nsm = new XmlNamespaceManager(comprobanteFirmado.NameTable);
        nsm.AddNamespace("ds", DsNs);
        var firmado = comprobanteFirmado.SelectSingleNode("//ds:Signature", nsm) is not null;

        var etiqueta = tipo == TipoComprobante.Factura ? "La Factura" : "La Boleta";
        var respuesta = firmado
            ? new RespuestaCdr(true, "0", $"{etiqueta} {nombreArchivo} ha sido aceptada (modo simulado).")
            : new RespuestaCdr(false, "1033", "El comprobante no está firmado.");

        return Task.FromResult(respuesta);
    }
}
