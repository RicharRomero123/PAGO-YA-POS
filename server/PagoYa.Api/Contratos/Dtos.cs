using System.ComponentModel.DataAnnotations;
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
        ExpUnix = l.ExpUnix,
        CreadoUtc = l.CreadoUtc
    };
}

/// <summary>Respuesta de error uniforme.</summary>
public sealed class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public ErrorResponse() { }
    public ErrorResponse(string error) => Error = error;
}
