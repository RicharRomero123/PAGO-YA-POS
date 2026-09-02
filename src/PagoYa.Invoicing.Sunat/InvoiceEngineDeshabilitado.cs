using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;

namespace PagoYa.Invoicing.Sunat;

/// <summary>
/// Patrón <b>Null Object</b> de <see cref="IInvoiceEngine"/>. Se inyecta cuando
/// la licencia NO habilita el flag "invoicing". Permite que el resto de la app
/// dependa siempre de <see cref="IInvoiceEngine"/> sin ramificar por licencia:
/// simplemente este objeto rechaza la emisión con un mensaje comercial.
///
/// Así, el core y la UI nunca necesitan comprobar el tier antes de resolver la
/// dependencia; el feature-gating queda en la composición (DI).
/// </summary>
public sealed class InvoiceEngineDeshabilitado : IInvoiceEngine
{
    /// <inheritdoc />
    public bool PuedeEmitir => false;

    /// <inheritdoc />
    public Task<ResultadoEmision> EmitirComprobanteAsync(Venta venta, CancellationToken ct = default)
        => Task.FromResult(ResultadoEmision.NoHabilitado());
}
