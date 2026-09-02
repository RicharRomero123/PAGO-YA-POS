using System.Xml;
using PagoYa.Core.Enums;

namespace PagoYa.Invoicing.Sunat.Transporte;

/// <summary>Respuesta del CDR (Constancia de Recepción) de SUNAT/OSE.</summary>
public sealed record RespuestaCdr(bool Aceptado, string Codigo, string Descripcion);

/// <summary>
/// Canal de transmisión del comprobante firmado. Abstrae las dos estrategias de
/// CLAUDE.md: Vía Directa (SOAP a SUNAT, ZIP + WSSE) o PSE intermedio
/// (Nubefact/ApisPeru por REST). El modo <see cref="AmbienteSunat.Simulado"/>
/// permite operar/probar sin credenciales SOL ni internet.
/// </summary>
public interface ISunatTransport
{
    /// <summary>Transmite el comprobante firmado y devuelve el resultado del CDR.</summary>
    Task<RespuestaCdr> EnviarAsync(string nombreArchivo, XmlDocument comprobanteFirmado, TipoComprobante tipo, CancellationToken ct = default);
}
