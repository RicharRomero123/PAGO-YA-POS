using PagoYa.Core.Contratos;

namespace PagoYa.Cloud;

/// <summary>
/// Canal de transporte hacia el backend de sincronización. Abstrae el HTTP/JSON
/// para poder probar el motor sin red (ver <see cref="TransporteSyncEnMemoria"/>)
/// y cambiar el backend sin tocar <see cref="CloudSyncService"/>.
/// </summary>
public interface ISyncTransport
{
    /// <summary>
    /// Sube un lote de eventos del outbox. Devuelve qué ids aceptó el backend
    /// (idempotente: reenviar un id ya aceptado debe volver a aceptarlo).
    /// </summary>
    Task<ResultadoLote> EnviarLoteAsync(IReadOnlyList<EventoSyncLocal> lote, CancellationToken ct = default);

    /// <summary>
    /// Descarga los cambios remotos posteriores a <paramref name="cursor"/> (null =
    /// desde el inicio) y devuelve el nuevo cursor para la próxima bajada.
    /// </summary>
    Task<PaqueteRemoto> DescargarCambiosAsync(string? cursor, CancellationToken ct = default);
}

/// <summary>
/// Resultado de subir un lote: ids aceptados o error de transporte.
///
/// <see cref="Codigo"/> es el <c>ErrorResponse.codigo</c> del backend (catálogo
/// estable de <c>server/README.md §10</c>) cuando vino; null si el server es
/// anterior al catálogo o el fallo fue de red. Es el campo por el que se debe
/// ramificar — <see cref="Error"/> es texto para el usuario y se reescribe.
/// </summary>
public sealed record ResultadoLote(
    bool Ok,
    IReadOnlyCollection<Guid> AceptadosIds,
    string? Error,
    string? Codigo = null)
{
    public static ResultadoLote Exito(IReadOnlyCollection<Guid> ids) => new(true, ids, null);

    public static ResultadoLote Falla(string error, string? codigo = null) =>
        new(false, Array.Empty<Guid>(), error, codigo);
}

/// <summary>
/// Códigos de error machine-readable que <c>/sync/*</c> puede devolver, espejo de
/// <c>CodigosError</c> en <c>server/PagoYa.Api/Contratos/Dtos.cs</c>
/// (catálogo completo en <c>server/README.md §10</c>).
///
/// Se ramifica SIEMPRE por estos códigos, nunca por el texto de <c>error</c>: ese
/// texto es para el usuario y puede reescribirse, acortarse o traducirse sin
/// aviso. Un código publicado, en cambio, no cambia de significado ni se recicla.
///
/// Los dos 403 no se confunden: <see cref="SinFlagCloudSync"/> es "el plan no
/// incluye la nube" → upsell; <see cref="AsientoRevocado"/> es "esta caja perdió
/// su asiento" → volver a vincular el equipo. Mostrar upsell a quien solo
/// necesita re-vincular es un ticket de soporte garantizado.
/// </summary>
public static class CodigosErrorSync
{
    public const string TokenAusente = "token_ausente";
    public const string TokenInvalido = "token_invalido";
    public const string TokenExpirado = "token_expirado";
    public const string LicenciaNoIdentificada = "licencia_no_identificada";
    public const string SinFlagCloudSync = "sin_flag_cloud_sync";
    public const string AsientoRevocado = "asiento_revocado";
}

/// <summary>Cambios remotos descargados + cursor para la siguiente bajada.</summary>
public sealed record PaqueteRemoto(IReadOnlyList<CambioRemoto> Cambios, string Cursor);

/// <summary>Parámetros del ciclo de sincronización.</summary>
public sealed class OpcionesSync
{
    /// <summary>Máximo de eventos por lote de subida.</summary>
    public int TamanoLote { get; set; } = 100;

    /// <summary>Intentos máximos por evento antes de moverlo a dead-letter.</summary>
    public int MaxIntentos { get; set; } = 5;

    /// <summary>URL base del backend de sync (para el transporte HTTP).</summary>
    public string? UrlBase { get; set; }

    /// <summary>Token/clave para autenticar la sincronización con el backend.</summary>
    public string? TokenLicencia { get; set; }

    /// <summary>
    /// Identidad de sincronización de ESTA caja: el mismo valor que se estampa en
    /// <c>origen_caja_id</c> de cada fila de negocio y de cada evento del outbox.
    ///
    /// Se envía como <c>?origen=</c> en el <c>GET /sync/pull</c> para el
    /// <b>filtro de eco</b> del backend (que no nos devuelva nuestros propios
    /// eventos, <c>server/README.md §7.1</c>). Contrato: cadena opaca, estable y
    /// única por dispositivo dentro de la licencia; el server solo la compara.
    ///
    /// <b>Tiene que ser idéntico al que se sube</b>, o el filtro no filtra nada:
    /// la caja se re-aplica sus propias ventas, con el riesgo de que un snapshot
    /// viejo pise uno nuevo. Por eso sale de una sola fuente
    /// (<c>ConfiguracionNegocio.OrigenCajaId</c> en el escritorio) y no se
    /// recalcula en cada capa.
    ///
    /// El valor recomendado es el prefijo que asigna el SERVER al vincular
    /// (<c>C01</c>..<c>C99</c> en escritorio): el cliente lo persiste, no lo
    /// genera. Vacío = no se manda el parámetro y el backend no filtra
    /// (comportamiento anterior, compatible).
    /// </summary>
    public string OrigenCajaId { get; set; } = string.Empty;
}
