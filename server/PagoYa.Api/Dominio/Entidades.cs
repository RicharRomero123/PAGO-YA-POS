namespace PagoYa.Api.Dominio;

/// <summary>
/// Tier comercial de la licencia. Los strings viajan en el claim <c>tier</c> del
/// token exactamente como los espera el cliente (ver docs/LICENSE-TOKEN.md).
/// </summary>
public enum Tier
{
    Base = 0,
    Cloud = 1,
    Facturador = 2
}

/// <summary>Estado administrativo de una licencia.</summary>
public enum EstadoLicencia
{
    /// <summary>Emitida pero aún no activada en ningún equipo.</summary>
    Emitida = 0,

    /// <summary>Activada y vinculada a un HWID.</summary>
    Activa = 1,

    /// <summary>Suspendida por soporte/impago (no emite tokens válidos).</summary>
    Suspendida = 2,

    /// <summary>Expirada (suscripción vencida más allá del grace period).</summary>
    Expirada = 3,

    /// <summary>Revocada permanentemente (fraude/chargeback).</summary>
    Revocada = 4
}

/// <summary>
/// Rol de un dispositivo dentro de la licencia (modelo de asientos/seats).
///
/// <para><b>Principal</b>: el equipo vinculado en <c>Licencia.HwidActual</c> vía
/// <c>POST /activate</c>. Hay como máximo uno activo y su cambio consume traslados.</para>
///
/// <para><b>Secundario</b>: asiento adicional vinculado vía <c>POST /devices</c>
/// (típicamente el móvil del mozo). NO toca <c>HwidActual</c> ni consume traslados;
/// solo ocupa un cupo de <c>Licencia.MaxDispositivos</c>.</para>
///
/// Compatibilidad: el valor 0 = Principal, así que las filas de <c>Devices</c>
/// creadas antes de los seats se leen como principales sin migración de datos.
/// </summary>
public enum TipoDispositivo
{
    Principal = 0,
    Secundario = 1
}

/// <summary>Estado de una suscripción de pago recurrente (Cloud/Facturador).</summary>
public enum EstadoSuscripcion
{
    Pendiente = 0,
    Activa = 1,
    Vencida = 2,
    Cancelada = 3
}

/// <summary>
/// Licencia emitida. Es la raíz del agregado: contiene tier, features, estado,
/// la clave de licencia (secreto que el cliente presenta en /activate) y la
/// política de HWID.
/// </summary>
public sealed class Licencia
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Clave de licencia legible que el vendedor entrega al cliente por WhatsApp.
    /// El cliente la envía en /activate. Formato: PAGOYA-XXXX-XXXX-XXXX-XXXX.
    /// </summary>
    public string ClaveLicencia { get; set; } = string.Empty;

    public Tier Tier { get; set; } = Tier.Base;

    /// <summary>Features habilitados, separados por coma (contrato: invoicing,cloud_sync,multi_site).</summary>
    public string FeaturesCsv { get; set; } = string.Empty;

    public EstadoLicencia Estado { get; set; } = EstadoLicencia.Emitida;

    /// <summary>Nombre del negocio/cliente, para identificarlo en el panel admin.</summary>
    public string? NombreNegocio { get; set; }

    /// <summary>RUC/identificador del negocio (claim <c>sub</c>, informativo).</summary>
    public string? Ruc { get; set; }

    /// <summary>Canal de venta (whatsapp, facebook, etc.), para métricas.</summary>
    public string? CanalVenta { get; set; }

    /// <summary>Notas de soporte.</summary>
    public string? Notas { get; set; }

    /// <summary>
    /// Expiración de la licencia (Unix epoch segundos, UTC). 0 = perpetua (Base).
    /// Para suscripciones se sincroniza con la suscripción activa.
    /// </summary>
    public long ExpUnix { get; set; }

    /// <summary>
    /// HWID actualmente vinculado, o null si aún libre. Puede pre-vincularse en emisión.
    /// </summary>
    public string? HwidActual { get; set; }

    /// <summary>
    /// Máximo de traslados (re-vinculaciones a otro equipo) permitidos sin
    /// aprobación manual. Política HWID: Base = 1 equipo, N traslados.
    /// </summary>
    public int MaxTraslados { get; set; } = 2;

    /// <summary>Traslados de HWID ya consumidos.</summary>
    public int TrasladosUsados { get; set; }

    /// <summary>
    /// Máximo de dispositivos ACTIVOS simultáneos: el principal (HWID de la PC)
    /// MÁS los asientos secundarios (móviles). Default por tier:
    /// Base 1, Cloud 3, Facturador 5.
    ///
    /// <b>0 = "sin definir"</b> y se resuelve con el default del tier
    /// (<see cref="MaxDispositivosEfectivo"/>). Esto mantiene la compatibilidad
    /// con licencias emitidas antes del modelo de seats, cuyas filas traen 0.
    /// </summary>
    public int MaxDispositivos { get; set; }

    public DateTime CreadoUtc { get; set; } = DateTime.UtcNow;
    public DateTime ActualizadoUtc { get; set; } = DateTime.UtcNow;

    public List<Dispositivo> Dispositivos { get; set; } = new();
    public List<Suscripcion> Suscripciones { get; set; } = new();
    public List<LogActivacion> LogsActivacion { get; set; } = new();

    /// <summary>Cupo de dispositivos realmente aplicable (resuelve el 0 legacy).</summary>
    public int MaxDispositivosEfectivo =>
        MaxDispositivos > 0 ? MaxDispositivos : MaxDispositivosPorTier(Tier);

    /// <summary>Cupo de dispositivos por defecto de cada tier comercial.</summary>
    public static int MaxDispositivosPorTier(Tier tier) => tier switch
    {
        Tier.Cloud => 3,
        Tier.Facturador => 5,
        _ => 1
    };

    public string[] Features =>
        string.IsNullOrWhiteSpace(FeaturesCsv)
            ? Array.Empty<string>()
            : FeaturesCsv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}

/// <summary>
/// Equipo (HWID) vinculado a una licencia a lo largo del tiempo. Desde el modelo
/// de asientos también representa los dispositivos <b>secundarios</b> (móviles)
/// vinculados con <c>POST /devices</c>, distinguidos por <see cref="Tipo"/>.
/// </summary>
public sealed class Dispositivo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LicenciaId { get; set; }
    public Licencia? Licencia { get; set; }

    /// <summary>
    /// Huella del equipo. En la PC es el HWID (CPU + BaseBoard); en el móvil es el
    /// id estable del dispositivo (Android ID / identifierForVendor).
    /// </summary>
    public string Hwid { get; set; } = string.Empty;

    /// <summary>Principal (HWID de la licencia) o Secundario (asiento móvil).</summary>
    public TipoDispositivo Tipo { get; set; } = TipoDispositivo.Principal;

    /// <summary>Nombre legible para el panel admin ("Celular de Juan", "Caja 2").</summary>
    public string? Nombre { get; set; }

    /// <summary>Plataforma informativa: windows | android | ios.</summary>
    public string? Plataforma { get; set; }

    /// <summary>
    /// Prefijo de correlativos y de <c>origen_caja_id</c> asignado por el SERVER:
    /// <c>C01</c>, <c>C02</c> (equipos de escritorio), <c>M01</c>, <c>M02</c> (móviles).
    /// Es único dentro de la licencia y no se reutiliza mientras el asiento esté activo.
    /// Vacío en las filas anteriores al modelo de seats (el cliente conserva el suyo).
    /// </summary>
    public string Prefijo { get; set; } = string.Empty;

    /// <summary>True si el asiento está vigente (los revocados quedan como histórico).</summary>
    public bool Activo { get; set; } = true;

    public DateTime VinculadoUtc { get; set; } = DateTime.UtcNow;
    public DateTime? DesvinculadoUtc { get; set; }

    /// <summary>Último contacto conocido (activación/validación). Informativo.</summary>
    public DateTime? UltimoVistoUtc { get; set; }
}

/// <summary>Suscripción de pago recurrente (Cloud/Facturador).</summary>
public sealed class Suscripcion
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LicenciaId { get; set; }
    public Licencia? Licencia { get; set; }

    public EstadoSuscripcion Estado { get; set; } = EstadoSuscripcion.Pendiente;

    /// <summary>Periodo actual pagado hasta (Unix epoch segundos, UTC).</summary>
    public long PeriodoFinUnix { get; set; }

    /// <summary>Referencia del plan del proveedor de pagos.</summary>
    public string? PlanProveedor { get; set; }

    public DateTime CreadoUtc { get; set; } = DateTime.UtcNow;
    public DateTime ActualizadoUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Evento de pago recibido del webhook de la pasarela. Sirve para idempotencia:
/// el <see cref="EventoIdProveedor"/> es único.
/// </summary>
public sealed class EventoPago
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>Id del evento del proveedor (idempotencia: único).</summary>
    public string EventoIdProveedor { get; set; } = string.Empty;

    public Guid? LicenciaId { get; set; }

    public string Tipo { get; set; } = string.Empty;

    /// <summary>Monto en la moneda del proveedor (informativo).</summary>
    public decimal Monto { get; set; }
    public string? Moneda { get; set; }

    /// <summary>Payload crudo recibido (auditoría). Nunca contiene secretos del server.</summary>
    public string PayloadCrudo { get; set; } = string.Empty;

    public DateTime RecibidoUtc { get; set; } = DateTime.UtcNow;
    public bool Procesado { get; set; }
}

/// <summary>
/// Evento de sincronización recibido de un cliente Cloud (outbox → nube). Es el
/// log por licencia que consolida las escrituras de todas las cajas/sedes: en el
/// <b>pull</b>, cada caja descarga los eventos con <see cref="Secuencia"/> mayor a
/// su cursor. <see cref="Secuencia"/> es autoincremental y hace de cursor global.
/// La unicidad (LicenciaId, EventoIdCliente) da idempotencia al <b>push</b>.
/// </summary>
public sealed class EventoSync
{
    /// <summary>Secuencia global autoincremental (PK). Sirve de cursor de bajada.</summary>
    public long Secuencia { get; set; }

    /// <summary>Licencia (tenant) dueña del evento. Aísla los datos entre negocios.</summary>
    public Guid LicenciaId { get; set; }

    /// <summary>Id del evento en el outbox del cliente (idempotencia por licencia).</summary>
    public Guid EventoIdCliente { get; set; }

    public string Entidad { get; set; } = string.Empty;
    public Guid EntidadId { get; set; }
    public string Operacion { get; set; } = string.Empty;
    public string PayloadJson { get; set; } = string.Empty;
    public string OrigenCajaId { get; set; } = string.Empty;

    /// <summary>Marca de la entidad para last-write-wins (extraída del payload).</summary>
    public DateTime ActualizadoUtc { get; set; }

    /// <summary>Cuándo lo recibió la nube.</summary>
    public DateTime RecibidoUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>Log de auditoría de activaciones/validaciones/traslados de HWID.</summary>
public sealed class LogActivacion
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LicenciaId { get; set; }
    public Licencia? Licencia { get; set; }

    /// <summary>
    /// emision | activacion | traslado | validacion | rechazo | pago |
    /// suspension | reactivacion | vinculo_dispositivo | revocacion_dispositivo
    /// </summary>
    public string Accion { get; set; } = string.Empty;

    public string? Hwid { get; set; }
    public string? Detalle { get; set; }
    public string? IpOrigen { get; set; }
    public bool Exito { get; set; }

    public DateTime FechaUtc { get; set; } = DateTime.UtcNow;
}
