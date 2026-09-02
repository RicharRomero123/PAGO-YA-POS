using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Contratos;

// ============================ Emisión (/licenses) ============================

/// <summary>Solicitud de emisión manual de una licencia (venta WhatsApp/Facebook).</summary>
public sealed class EmitirLicenciaRequest
{
    /// <summary>Tier comercial: "base" | "cloud" | "facturador".</summary>
    [Required]
    public string Tier { get; set; } = "base";

    /// <summary>
    /// Features a habilitar. Si es null, se usan los defaults del tier
    /// (base: [], cloud: cloud_sync+multi_site, facturador: +invoicing).
    /// </summary>
    public string[]? Features { get; set; }

    /// <summary>Nombre del negocio/cliente (para identificarlo en el panel).</summary>
    public string? NombreNegocio { get; set; }

    /// <summary>RUC/identificador del negocio (claim sub, informativo).</summary>
    public string? Ruc { get; set; }

    /// <summary>HWID a pre-vincular en la emisión (opcional).</summary>
    public string? Hwid { get; set; }

    /// <summary>
    /// Días de vigencia para suscripciones. Si null y tier != base, se usa 30.
    /// Ignorado para base (perpetua, exp=0).
    /// </summary>
    public int? DiasVigencia { get; set; }

    /// <summary>Canal de venta para métricas (whatsapp/facebook/...).</summary>
    public string? CanalVenta { get; set; }

    /// <summary>Máximo de traslados de HWID sin aprobación manual (default 2).</summary>
    public int? MaxTraslados { get; set; }

    /// <summary>
    /// Cupo de dispositivos ACTIVOS simultáneos (principal + secundarios).
    /// Si es null se usa el default del tier: base 1, cloud 3, facturador 5.
    /// </summary>
    public int? MaxDispositivos { get; set; }

    public string? Notas { get; set; }
}

/// <summary>Respuesta de emisión: la clave que se entrega al cliente.</summary>
public sealed class EmitirLicenciaResponse
{
    public Guid LicenciaId { get; set; }
    public string ClaveLicencia { get; set; } = string.Empty;
    public string Tier { get; set; } = string.Empty;
    public string[] Features { get; set; } = Array.Empty<string>();
    public long ExpUnix { get; set; }
    public string Estado { get; set; } = string.Empty;
}

// ============================ Activación (/activate) =========================

/// <summary>El cliente presenta su clave + el HWID del equipo.</summary>
public sealed class ActivarRequest
{
    [Required]
    public string LicenseKey { get; set; } = string.Empty;

    [Required]
    public string Hwid { get; set; } = string.Empty;
}

/// <summary>Respuesta con el token firmado listo para persistir en el cliente.</summary>
public sealed class TokenResponse
{
    public string Token { get; set; } = string.Empty;
    public string Tier { get; set; } = string.Empty;
    public string[] Features { get; set; } = Array.Empty<string>();
    public long ExpUnix { get; set; }
    public bool EsPerpetua => ExpUnix == 0;

    /// <summary>
    /// Id del asiento (fila de <c>Devices</c>) al que corresponde este token.
    /// Es el <c>{id}</c> de <c>DELETE /devices/{id}</c>. Campo aditivo: los
    /// clientes que no lo conocen simplemente lo ignoran.
    /// </summary>
    public Guid? DeviceId { get; set; }

    /// <summary>
    /// Prefijo asignado por el server a este dispositivo (<c>C01</c>, <c>M01</c>).
    /// El cliente lo usa como <c>origen_caja_id</c> y como prefijo de correlativos
    /// (<c>&lt;prefijo&gt;-&lt;correlativo&gt;</c>).
    /// </summary>
    public string? DevicePrefix { get; set; }
}

// ====================== Asientos / dispositivos (/devices) ===================

/// <summary>
/// Vinculación de un dispositivo SECUNDARIO (típicamente el móvil del mozo).
/// No toca <c>HwidActual</c> ni consume traslados: solo ocupa un cupo de
/// <c>MaxDispositivos</c>. Se autentica con la misma clave de licencia que
/// <c>/activate</c> (mismo rate limiting).
/// </summary>
public sealed class VincularDispositivoRequest
{
    [Required]
    public string LicenseKey { get; set; } = string.Empty;

    /// <summary>
    /// Id estable del dispositivo (Android ID / identifierForVendor / HWID).
    /// Se firma en el claim <c>hwid</c> del token del asiento, así que el cliente
    /// debe poder recalcularlo idénticamente en cada arranque.
    /// </summary>
    [Required]
    public string DeviceId { get; set; } = string.Empty;

    /// <summary>Nombre legible para el panel admin ("Celular de Juan").</summary>
    public string? Nombre { get; set; }

    /// <summary>Plataforma: android | ios | windows. Decide la familia del prefijo (M/C).</summary>
    public string? Plataforma { get; set; }
}

/// <summary>Vista de un asiento para el panel admin y para /devices.</summary>
public sealed class DispositivoResumen
{
    public Guid Id { get; set; }

    /// <summary>Huella del equipo (HWID o id del móvil).</summary>
    public string Hwid { get; set; } = string.Empty;

    /// <summary>principal | secundario</summary>
    public string Tipo { get; set; } = string.Empty;

    public string? Nombre { get; set; }
    public string? Plataforma { get; set; }

    /// <summary>Prefijo de correlativos/origen asignado por el server (C01, M01...).</summary>
    public string Prefijo { get; set; } = string.Empty;

    public bool Activo { get; set; }
    public DateTime VinculadoUtc { get; set; }
    public DateTime? DesvinculadoUtc { get; set; }
    public DateTime? UltimoVistoUtc { get; set; }

    public static DispositivoResumen De(Dispositivo d) => new()
    {
        Id = d.Id,
        Hwid = d.Hwid,
        Tipo = d.Tipo.ToString().ToLowerInvariant(),
        Nombre = d.Nombre,
        Plataforma = d.Plataforma,
        Prefijo = d.Prefijo,
        Activo = d.Activo,
        VinculadoUtc = d.VinculadoUtc,
        DesvinculadoUtc = d.DesvinculadoUtc,
        UltimoVistoUtc = d.UltimoVistoUtc
    };
}

/// <summary>Resultado de revocar un asiento.</summary>
public sealed class RevocarDispositivoResponse
{
    public Guid DeviceId { get; set; }
    public bool Revocado { get; set; }

    /// <summary>Asientos activos restantes tras la revocación.</summary>
    public int DispositivosActivos { get; set; }
    public int MaxDispositivos { get; set; }
}

// ============================ Validación (/validate) ========================

/// <summary>Revalidación/renovación silenciosa desde el cliente.</summary>
public sealed class ValidarRequest
{
    [Required]
    public string LicenseKey { get; set; } = string.Empty;

    [Required]
    public string Hwid { get; set; } = string.Empty;
}

// ============================ Webhook de pago ===============================

/// <summary>Payload del webhook de la pasarela (forma simplificada de dev).</summary>
public sealed class WebhookPagoRequest
{
    /// <summary>Id único del evento en el proveedor (idempotencia).</summary>
    [Required]
    public string EventId { get; set; } = string.Empty;

    /// <summary>Tipo: payment.succeeded | subscription.renewed | ...</summary>
    [Required]
    public string Type { get; set; } = string.Empty;

    /// <summary>Clave de licencia asociada al pago.</summary>
    [Required]
    public string LicenseKey { get; set; } = string.Empty;

    /// <summary>Días a extender la suscripción (default 30).</summary>
    public int? Dias { get; set; }

    public decimal Monto { get; set; }
    public string? Moneda { get; set; }
}

// ============================ Sincronización (/sync) ========================

/// <summary>Lote de eventos del outbox del cliente (espejo de EventoSyncLocal).</summary>
public sealed class SyncPushRequest
{
    public List<EventoSyncDto> Eventos { get; set; } = new();
}

/// <summary>Evento del outbox subido por el cliente.</summary>
public sealed class EventoSyncDto
{
    public Guid Id { get; set; }
    public string Entidad { get; set; } = string.Empty;
    public Guid EntidadId { get; set; }
    public string Operacion { get; set; } = string.Empty;
    public string PayloadJson { get; set; } = string.Empty;
    public int Intentos { get; set; }
    public string OrigenCajaId { get; set; } = string.Empty;
    public DateTime CreadoUtc { get; set; }
}

/// <summary>Respuesta del push: ids aceptados (idempotente).</summary>
public sealed class SyncPushResponse
{
    public List<Guid> Aceptados { get; set; } = new();

    /// <summary>
    /// Nombres de entidad recibidos que NO están en el catálogo de sync
    /// (<see cref="Servicios.EntidadesSync.Catalogo"/>). Se almacenan igual —el
    /// server nunca descarta datos del cliente— pero se reportan para detectar
    /// desalineación de contrato entre PC, móvil y backend.
    /// </summary>
    public List<string> EntidadesDesconocidas { get; set; } = new();
}

/// <summary>Respuesta del pull: cambios remotos + nuevo cursor (espejo de PaqueteRemoto).</summary>
public sealed class SyncPullResponse
{
    public List<CambioRemotoDto> Cambios { get; set; } = new();
    public string Cursor { get; set; } = "0";
}

/// <summary>Cambio remoto para aplicar en el cliente (espejo de CambioRemoto).</summary>
public sealed class CambioRemotoDto
{
    public string Entidad { get; set; } = string.Empty;
    public Guid EntidadId { get; set; }
    public string Operacion { get; set; } = string.Empty;
    public string PayloadJson { get; set; } = string.Empty;
    public DateTime ActualizadoUtc { get; set; }
    public string OrigenCajaId { get; set; } = string.Empty;
}

// ============================ Admin =========================================

/// <summary>Vista resumida de una licencia para el panel admin.</summary>
public sealed class LicenciaResumen
{
    public Guid Id { get; set; }
    public string ClaveLicencia { get; set; } = string.Empty;
    public string Tier { get; set; } = string.Empty;
    public string[] Features { get; set; } = Array.Empty<string>();
    public string Estado { get; set; } = string.Empty;
    public string? NombreNegocio { get; set; }
    public string? Ruc { get; set; }
    public string? Notas { get; set; }
    public string? CanalVenta { get; set; }
    public string? HwidActual { get; set; }
    public int TrasladosUsados { get; set; }
    public int MaxTraslados { get; set; }

    /// <summary>Cupo de dispositivos activos (principal + secundarios) ya resuelto por tier.</summary>
    public int MaxDispositivos { get; set; }

    /// <summary>Asientos activos ocupados en este momento.</summary>
    public int DispositivosActivos { get; set; }

    /// <summary>
    /// Dispositivos de la licencia. Sólo viene poblado en el detalle
    /// (<c>GET /admin/licenses/{id}</c>); en el listado queda vacío.
    /// </summary>
    public List<DispositivoResumen> Dispositivos { get; set; } = new();

    public long ExpUnix { get; set; }
    public DateTime CreadoUtc { get; set; }

    public static LicenciaResumen De(Licencia l) => new()
    {
        Id = l.Id,
        ClaveLicencia = l.ClaveLicencia,
        Tier = l.Tier.ToString().ToLowerInvariant(),
        Features = l.Features,
        Estado = l.Estado.ToString(),
        NombreNegocio = l.NombreNegocio,
        Ruc = l.Ruc,
        Notas = l.Notas,
        CanalVenta = l.CanalVenta,
        HwidActual = l.HwidActual,
        TrasladosUsados = l.TrasladosUsados,
        MaxTraslados = l.MaxTraslados,
        MaxDispositivos = l.MaxDispositivosEfectivo,
        DispositivosActivos = l.Dispositivos.Count(d => d.Activo),
        ExpUnix = l.ExpUnix,
        CreadoUtc = l.CreadoUtc
    };

    /// <summary>Detalle: igual que <see cref="De"/> pero listando los dispositivos.</summary>
    public static LicenciaResumen ConDispositivos(Licencia l)
    {
        var r = De(l);
        r.Dispositivos = l.Dispositivos
            .OrderByDescending(d => d.Activo).ThenBy(d => d.Prefijo).ThenBy(d => d.VinculadoUtc)
            .Select(DispositivoResumen.De)
            .ToList();
        return r;
    }
}

/// <summary>
/// Códigos de error <b>estables y machine-readable</b>. Son un CONTRATO: una vez
/// publicado, un código no cambia de significado ni se reutiliza para otra
/// condición. Los clientes (móvil y escritorio) deben ramificar por
/// <c>ErrorResponse.Codigo</c>, nunca por subcadenas de <c>Error</c>: ese texto es
/// para el usuario y puede reescribirse o traducirse en cualquier momento.
///
/// Ver la tabla completa en <c>server/README.md §10</c>.
/// </summary>
public static class CodigosError
{
    // --- Token / autenticación de sync (401/403) ---
    public const string TokenAusente = "token_ausente";
    public const string TokenInvalido = "token_invalido";
    public const string TokenExpirado = "token_expirado";
    public const string LicenciaNoIdentificada = "licencia_no_identificada";

    /// <summary>403: el token es válido pero la licencia no habilita <c>cloud_sync</c>
    /// → camino de UPSELL al tier Cloud.</summary>
    public const string SinFlagCloudSync = "sin_flag_cloud_sync";

    /// <summary>403: el asiento (device_id del token) fue revocado
    /// → camino de "vuelve a vincular este equipo".</summary>
    public const string AsientoRevocado = "asiento_revocado";

    // --- Licencia (404/409) ---
    public const string ClaveNoEncontrada = "clave_no_encontrada";
    public const string LicenciaSuspendida = "licencia_suspendida";
    public const string LicenciaRevocada = "licencia_revocada";
    public const string LicenciaNoEncontrada = "licencia_no_encontrada";
    public const string LimiteTraslados = "limite_traslados";
    public const string HwidNoCoincide = "hwid_no_coincide";

    // --- Asientos / dispositivos ---
    public const string CupoDispositivosLleno = "cupo_dispositivos_lleno";
    public const string DispositivoYaEsPrincipal = "dispositivo_ya_es_principal";
    public const string PrincipalNoRevocable = "principal_no_revocable";
    public const string DispositivoNoEncontrado = "dispositivo_no_encontrado";
    public const string DeviceIdRequerido = "device_id_requerido";
    public const string PrefijosAgotados = "prefijos_agotados";
    public const string CredencialesRequeridas = "credenciales_requeridas";
    public const string ClaveNoCorresponde = "clave_no_corresponde";

    // --- Emisión / admin ---
    public const string TierInvalido = "tier_invalido";
    public const string FeatureInvalido = "feature_invalido";
    public const string NoAutorizado = "no_autorizado";
    public const string PayloadInvalido = "payload_invalido";
    public const string FirmaWebhookInvalida = "firma_webhook_invalida";
}

/// <summary>
/// Respuesta de error uniforme. <see cref="Error"/> es el texto legible (puede
/// cambiar de redacción o traducirse); <see cref="Codigo"/> es el identificador
/// estable por el que los clientes deben ramificar (<see cref="CodigosError"/>).
///
/// El campo <c>codigo</c> es <b>aditivo</b>: se omite del JSON cuando es null, así
/// que los clientes que ya leían solo <c>error</c> no cambian.
/// </summary>
public sealed class ErrorResponse
{
    public string Error { get; set; } = string.Empty;

    /// <summary>Código estable del catálogo <see cref="CodigosError"/>. Null en
    /// errores genéricos aún sin clasificar.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Codigo { get; set; }

    public ErrorResponse() { }
    public ErrorResponse(string error) => Error = error;
    public ErrorResponse(string error, string? codigo)
    {
        Error = error;
        Codigo = string.IsNullOrWhiteSpace(codigo) ? null : codigo;
    }
}
