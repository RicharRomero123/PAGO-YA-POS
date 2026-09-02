using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;
using PagoYa.Api.Firma;

namespace PagoYa.Api.Servicios;

/// <summary>
/// Resultado de una operación de negocio (evita excepciones para control de flujo).
///
/// <paramref name="Codigo"/> es el código estable de <see cref="CodigosError"/> que
/// viaja al cliente en <c>ErrorResponse.Codigo</c>. Es opcional y por defecto null,
/// así que las llamadas antiguas de 4 argumentos siguen compilando igual.
/// </summary>
public readonly record struct Resultado<T>(bool Ok, T? Valor, string? Error, int Http, string? Codigo = null)
{
    public static Resultado<T> Exito(T valor) => new(true, valor, null, 200);

    public static Resultado<T> Falla(string error, int http, string? codigo = null) =>
        new(false, default, error, http, codigo);
}

/// <summary>
/// Lógica de negocio del licenciamiento: emisión, activación con política HWID,
/// revalidación/renovación y emisión del token firmado. No conoce HTTP.
/// </summary>
public sealed class ServicioLicencias
{
    private readonly LicenciasDbContext _db;
    private readonly EmisorTokens _emisor;
    private readonly ILogger<ServicioLicencias> _log;

    /// <summary>Días de gracia del cliente (docs/LICENSE-TOKEN.md). El exp del token
    /// se emite con margen para permitir revalidación silenciosa antes del corte.</summary>
    public const int DiasGraciaCliente = 7;

    public ServicioLicencias(LicenciasDbContext db, EmisorTokens emisor, ILogger<ServicioLicencias> log)
    {
        _db = db;
        _emisor = emisor;
        _log = log;
    }

    // ------------------------------------------------------------- Emisión ---

    public async Task<Resultado<EmitirLicenciaResponse>> EmitirAsync(EmitirLicenciaRequest req, CancellationToken ct)
    {
        if (!TryParseTier(req.Tier, out var tier))
            return Resultado<EmitirLicenciaResponse>.Falla(
                $"Tier inválido: '{req.Tier}'. Use base|cloud|facturador.", 400, CodigosError.TierInvalido);

        var features = req.Features ?? FeaturesPorDefecto(tier);
        if (!FeaturesValidos(features, out var invalido))
            return Resultado<EmitirLicenciaResponse>.Falla(
                $"Feature inválido: '{invalido}'.", 400, CodigosError.FeatureInvalido);

        long exp = 0;
        if (tier != Tier.Base)
        {
            var dias = req.DiasVigencia ?? 30;
            exp = DateTimeOffset.UtcNow.AddDays(dias).ToUnixTimeSeconds();
        }

        var licencia = new Licencia
        {
            ClaveLicencia = GenerarClaveLicencia(),
            Tier = tier,
            FeaturesCsv = string.Join(',', features),
            Estado = EstadoLicencia.Emitida,
            NombreNegocio = req.NombreNegocio,
            Ruc = req.Ruc,
            CanalVenta = req.CanalVenta,
            Notas = req.Notas,
            ExpUnix = exp,
            MaxTraslados = req.MaxTraslados ?? 2,
            MaxDispositivos = req.MaxDispositivos ?? Licencia.MaxDispositivosPorTier(tier),
            HwidActual = string.IsNullOrWhiteSpace(req.Hwid) ? null : req.Hwid.Trim()
        };

        if (licencia.HwidActual is not null)
        {
            licencia.Estado = EstadoLicencia.Activa;
            licencia.Dispositivos.Add(new Dispositivo
            {
                Hwid = licencia.HwidActual,
                Activo = true,
                Tipo = TipoDispositivo.Principal,
                Plataforma = "windows",
                Prefijo = AsignarPrefijo(licencia, "windows") ?? string.Empty
            });
        }

        if (tier != Tier.Base)
        {
            licencia.Suscripciones.Add(new Suscripcion
            {
                Estado = EstadoSuscripcion.Activa,
                PeriodoFinUnix = exp
            });
        }

        _db.Licencias.Add(licencia);
        RegistrarLog(licencia.Id, "emision", licencia.HwidActual, "Licencia emitida", true, null);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Licencia emitida {Id} tier {Tier}", licencia.Id, tier);

        return Resultado<EmitirLicenciaResponse>.Exito(new EmitirLicenciaResponse
        {
            LicenciaId = licencia.Id,
            ClaveLicencia = licencia.ClaveLicencia,
            Tier = tier.ToString().ToLowerInvariant(),
            Features = features,
            ExpUnix = exp,
            Estado = licencia.Estado.ToString()
        });
    }

    // ---------------------------------------------------------- Activación ---

    public async Task<Resultado<TokenResponse>> ActivarAsync(ActivarRequest req, string? ip, CancellationToken ct)
    {
        var hwid = req.Hwid.Trim();
        var lic = await BuscarPorClaveAsync(req.LicenseKey, ct);
        if (lic is null)
            return Resultado<TokenResponse>.Falla(
                "Clave de licencia no encontrada.", 404, CodigosError.ClaveNoEncontrada);

        if (!EstadoOperable(lic, out var motivoEstado, out var codigoEstado))
        {
            RegistrarLog(lic.Id, "rechazo", hwid, motivoEstado, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(motivoEstado, 409, codigoEstado);
        }

        // Política HWID: una licencia = un equipo. Traslados controlados.
        if (string.IsNullOrEmpty(lic.HwidActual))
        {
            // HWID libre: vincular.
            VincularHwid(lic, hwid);
            lic.Estado = EstadoLicencia.Activa;
            RegistrarLog(lic.Id, "activacion", hwid, "HWID vinculado por primera vez", true, ip);
        }
        else if (string.Equals(lic.HwidActual, hwid, StringComparison.OrdinalIgnoreCase))
        {
            // Reactivación en el mismo equipo: sin consumir traslado.
            RegistrarLog(lic.Id, "activacion", hwid, "Reactivación en el mismo equipo", true, ip);
        }
        else
        {
            // Traslado a otro equipo: consume un cupo o requiere aprobación manual.
            if (lic.TrasladosUsados >= lic.MaxTraslados)
            {
                var msg = $"Límite de traslados alcanzado ({lic.MaxTraslados}). Requiere aprobación manual de soporte.";
                RegistrarLog(lic.Id, "rechazo", hwid, msg, false, ip);
                await _db.SaveChangesAsync(ct);
                return Resultado<TokenResponse>.Falla(msg, 409, CodigosError.LimiteTraslados);
            }

            DesvincularHwidActual(lic);
            VincularHwid(lic, hwid);
            lic.TrasladosUsados++;
            RegistrarLog(lic.Id, "traslado", hwid,
                $"Traslado {lic.TrasladosUsados}/{lic.MaxTraslados} a nuevo equipo", true, ip);
        }

        lic.ActualizadoUtc = DateTime.UtcNow;
        var principal = DispositivoDe(lic, hwid);
        var token = EmitirToken(lic, principal);
        await _db.SaveChangesAsync(ct);

        return Resultado<TokenResponse>.Exito(RespuestaToken(lic, token, principal));
    }

    // ---------------------------------------------------- Validar/renovar ---

    public async Task<Resultado<TokenResponse>> ValidarAsync(ValidarRequest req, string? ip, CancellationToken ct)
    {
        var hwid = req.Hwid.Trim();
        var lic = await BuscarPorClaveAsync(req.LicenseKey, ct);
        if (lic is null)
            return Resultado<TokenResponse>.Falla(
                "Clave de licencia no encontrada.", 404, CodigosError.ClaveNoEncontrada);

        if (!EstadoOperable(lic, out var motivoEstado, out var codigoEstado))
        {
            RegistrarLog(lic.Id, "rechazo", hwid, motivoEstado, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(motivoEstado, 409, codigoEstado);
        }

        // El HWID debe coincidir con el vinculado (la revalidación no traslada).
        if (!string.IsNullOrEmpty(lic.HwidActual) &&
            !string.Equals(lic.HwidActual, hwid, StringComparison.OrdinalIgnoreCase))
        {
            var msg = "El HWID no coincide con el equipo vinculado. Use /activate para trasladar.";
            RegistrarLog(lic.Id, "rechazo", hwid, msg, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(msg, 409, CodigosError.HwidNoCoincide);
        }

        if (string.IsNullOrEmpty(lic.HwidActual))
            VincularHwid(lic, hwid);

        // Renovación: para suscripciones con periodo pagado vigente, extendemos el
        // exp del token hasta el fin de periodo. Base permanece perpetua.
        var principal = DispositivoDe(lic, hwid);
        if (principal is not null) principal.UltimoVistoUtc = DateTime.UtcNow;

        var token = EmitirToken(lic, principal);
        RegistrarLog(lic.Id, "validacion", hwid, "Revalidación/renovación", true, ip);
        lic.ActualizadoUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return Resultado<TokenResponse>.Exito(RespuestaToken(lic, token, principal));
    }

    // ------------------------------------------- Asientos / dispositivos ---

    /// <summary>
    /// Vincula un dispositivo <b>secundario</b> (móvil) como asiento de la licencia.
    ///
    /// Diferencias con <see cref="ActivarAsync"/> — y razón de ser de este endpoint:
    /// <list type="bullet">
    ///   <item>NO toca <c>HwidActual</c>: la PC del cliente sigue vinculada.</item>
    ///   <item>NO consume traslados (<c>MaxTraslados</c>).</item>
    ///   <item>Consume un cupo de <c>MaxDispositivos</c> (principal + secundarios).</item>
    /// </list>
    /// Devuelve un token firmado con <c>hwid</c> = id del móvil y los claims
    /// aditivos <c>device_id</c> / <c>device_prefix</c> (docs/LICENSE-TOKEN.md §4.1).
    /// Re-vincular el mismo dispositivo es idempotente: re-emite el token sin
    /// consumir otro cupo.
    /// </summary>
    public async Task<Resultado<TokenResponse>> VincularDispositivoAsync(
        VincularDispositivoRequest req, string? ip, CancellationToken ct)
    {
        var deviceId = req.DeviceId.Trim();
        if (deviceId.Length == 0)
            return Resultado<TokenResponse>.Falla(
                "El id del dispositivo es obligatorio.", 400, CodigosError.DeviceIdRequerido);

        var lic = await BuscarPorClaveAsync(req.LicenseKey, ct);
        if (lic is null)
            return Resultado<TokenResponse>.Falla(
                "Clave de licencia no encontrada.", 404, CodigosError.ClaveNoEncontrada);

        if (!EstadoOperable(lic, out var motivoEstado, out var codigoEstado))
        {
            RegistrarLog(lic.Id, "rechazo", deviceId, motivoEstado, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(motivoEstado, 409, codigoEstado);
        }

        // El equipo principal no se gestiona por aquí (evita que el móvil "robe" el HWID).
        if (!string.IsNullOrEmpty(lic.HwidActual) &&
            string.Equals(lic.HwidActual, deviceId, StringComparison.OrdinalIgnoreCase))
        {
            const string msg = "Ese equipo ya es el dispositivo principal de la licencia. Use /activate.";
            RegistrarLog(lic.Id, "rechazo", deviceId, msg, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(msg, 409, CodigosError.DispositivoYaEsPrincipal);
        }

        var existente = lic.Dispositivos
            .FirstOrDefault(d => string.Equals(d.Hwid, deviceId, StringComparison.OrdinalIgnoreCase));

        Dispositivo disp;
        if (existente is { Activo: true })
        {
            // Re-vinculación del mismo asiento: idempotente, no consume cupo.
            disp = existente;
            // Ya comprobamos que no es el HwidActual: por definición es un secundario.
            disp.Tipo = TipoDispositivo.Secundario;
            if (!string.IsNullOrWhiteSpace(req.Nombre)) disp.Nombre = req.Nombre.Trim();
            RegistrarLog(lic.Id, "vinculo_dispositivo", deviceId,
                $"Re-vinculación del asiento {disp.Prefijo}", true, ip);
        }
        else
        {
            var activos = lic.Dispositivos.Count(d => d.Activo);
            if (activos >= lic.MaxDispositivosEfectivo)
            {
                var msg = $"Límite de dispositivos alcanzado ({activos}/{lic.MaxDispositivosEfectivo}). " +
                          "Revoque un asiento en el panel o suba de plan.";
                RegistrarLog(lic.Id, "rechazo", deviceId, msg, false, ip);
                await _db.SaveChangesAsync(ct);
                return Resultado<TokenResponse>.Falla(msg, 409, CodigosError.CupoDispositivosLleno);
            }

            if (existente is not null)
            {
                // Asiento previamente revocado: se reactiva conservando su prefijo
                // (los correlativos ya emitidos con ese prefijo siguen siendo suyos).
                disp = existente;
                disp.Activo = true;
                disp.DesvinculadoUtc = null;
                disp.Tipo = TipoDispositivo.Secundario; // ya no es el HwidActual de la licencia
                if (!string.IsNullOrWhiteSpace(req.Nombre)) disp.Nombre = req.Nombre.Trim();
                if (!string.IsNullOrWhiteSpace(req.Plataforma)) disp.Plataforma = req.Plataforma.Trim().ToLowerInvariant();
                if (string.IsNullOrEmpty(disp.Prefijo))
                {
                    var p = AsignarPrefijo(lic, disp.Plataforma);
                    if (p is null) return await SinPrefijosAsync(lic, deviceId, ip, ct);
                    disp.Prefijo = p;
                }
                RegistrarLog(lic.Id, "vinculo_dispositivo", deviceId,
                    $"Reactivación del asiento {disp.Prefijo}", true, ip);
            }
            else
            {
                var plataforma = string.IsNullOrWhiteSpace(req.Plataforma)
                    ? "android"
                    : req.Plataforma.Trim().ToLowerInvariant();

                var prefijo = AsignarPrefijo(lic, plataforma);
                if (prefijo is null) return await SinPrefijosAsync(lic, deviceId, ip, ct);

                disp = new Dispositivo
                {
                    Licencia = lic,
                    Hwid = deviceId,
                    Tipo = TipoDispositivo.Secundario,
                    Nombre = string.IsNullOrWhiteSpace(req.Nombre) ? null : req.Nombre.Trim(),
                    Plataforma = plataforma,
                    Prefijo = prefijo,
                    Activo = true
                };
                _db.Dispositivos.Add(disp);
                lic.Dispositivos.Add(disp);

                RegistrarLog(lic.Id, "vinculo_dispositivo", deviceId,
                    $"Asiento secundario {prefijo} ({plataforma}) vinculado " +
                    $"[{lic.Dispositivos.Count(d => d.Activo)}/{lic.MaxDispositivosEfectivo}]", true, ip);
            }
        }

        disp.UltimoVistoUtc = DateTime.UtcNow;
        lic.ActualizadoUtc = DateTime.UtcNow;

        var token = EmitirToken(lic, disp);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Asiento {Prefijo} vinculado a licencia {Id}", disp.Prefijo, lic.Id);
        return Resultado<TokenResponse>.Exito(RespuestaToken(lic, token, disp));
    }

    /// <summary>
    /// Revoca un asiento. Lo puede hacer un admin o el dueño de la licencia
    /// (presentando su clave). El dispositivo <b>principal</b> NO se revoca por
    /// aquí: para eso está el traslado de <c>/activate</c> o la suspensión admin.
    ///
    /// <b>Importante:</b> la revocación libera el cupo e impide re-emitir tokens
    /// para ese asiento y sincronizar con él, pero un token ya emitido sigue
    /// validando <i>offline</i> en el dispositivo hasta su <c>exp</c> (el cliente
    /// verifica firma, no consulta al server). Para asientos de suscripción el
    /// corte efectivo llega al vencer el periodo.
    /// </summary>
    public async Task<Resultado<RevocarDispositivoResponse>> RevocarDispositivoAsync(
        Guid dispositivoId, string? claveLicencia, bool esAdmin, string? ip, CancellationToken ct)
    {
        var disp = await _db.Dispositivos.FirstOrDefaultAsync(d => d.Id == dispositivoId, ct);
        if (disp is null)
            return Resultado<RevocarDispositivoResponse>.Falla(
                "Dispositivo no encontrado.", 404, CodigosError.DispositivoNoEncontrado);

        // Se carga la licencia con TODOS sus dispositivos: el mismo `disp` rastreado
        // forma parte de la colección, así que el conteo de activos ya refleja la baja.
        var lic = await _db.Licencias
            .Include(l => l.Dispositivos)
            .FirstOrDefaultAsync(l => l.Id == disp.LicenciaId, ct);
        if (lic is null)
            return Resultado<RevocarDispositivoResponse>.Falla(
                "Licencia del dispositivo no encontrada.", 404, CodigosError.LicenciaNoEncontrada);

        if (!esAdmin)
        {
            var clave = (claveLicencia ?? string.Empty).Trim().ToUpperInvariant();
            if (clave.Length == 0)
                return Resultado<RevocarDispositivoResponse>.Falla(
                    "Se requiere la clave de licencia (cabecera X-License-Key) o credenciales de admin.",
                    401, CodigosError.CredencialesRequeridas);
            if (!string.Equals(clave, lic.ClaveLicencia, StringComparison.Ordinal))
                return Resultado<RevocarDispositivoResponse>.Falla(
                    "La clave de licencia no corresponde a este dispositivo.",
                    403, CodigosError.ClaveNoCorresponde);
        }

        if (disp.Tipo == TipoDispositivo.Principal)
            return Resultado<RevocarDispositivoResponse>.Falla(
                "No se puede revocar el dispositivo principal. Use /activate para trasladar la licencia " +
                "o suspéndala desde el panel admin.", 409, CodigosError.PrincipalNoRevocable);

        if (disp.Activo)
        {
            disp.Activo = false;
            disp.DesvinculadoUtc = DateTime.UtcNow;
            lic.ActualizadoUtc = DateTime.UtcNow;
            RegistrarLog(lic.Id, "revocacion_dispositivo", disp.Hwid,
                $"Asiento {disp.Prefijo} revocado por {(esAdmin ? "admin" : "el dueño de la licencia")}", true, ip);
            await _db.SaveChangesAsync(ct);
            _log.LogInformation("Asiento {Prefijo} revocado en licencia {Id}", disp.Prefijo, lic.Id);
        }

        return Resultado<RevocarDispositivoResponse>.Exito(new RevocarDispositivoResponse
        {
            DeviceId = disp.Id,
            Revocado = true,
            DispositivosActivos = lic.Dispositivos.Count(d => d.Activo),
            MaxDispositivos = lic.MaxDispositivosEfectivo
        });
    }

    /// <summary>
    /// ¿El asiento del token sigue vigente? Se consulta solo para tokens que traen
    /// el claim <c>device_id</c> (asientos secundarios): es lo que hace efectiva la
    /// revocación en los endpoints online (/sync). Los tokens de escritorio en campo
    /// no traen el claim y no pasan por aquí.
    /// </summary>
    public async Task<bool> AsientoVigenteAsync(Guid licenciaId, Guid dispositivoId, CancellationToken ct)
        => await _db.Dispositivos.AsNoTracking()
            .AnyAsync(d => d.Id == dispositivoId && d.LicenciaId == licenciaId && d.Activo, ct);

    private async Task<Resultado<TokenResponse>> SinPrefijosAsync(
        Licencia lic, string deviceId, string? ip, CancellationToken ct)
    {
        const string msg = "Se agotaron los prefijos de dispositivo (99) para esta licencia.";
        RegistrarLog(lic.Id, "rechazo", deviceId, msg, false, ip);
        await _db.SaveChangesAsync(ct);
        return Resultado<TokenResponse>.Falla(msg, 409, CodigosError.PrefijosAgotados);
    }

    // ------------------------------------------------------- Webhook pago ---

    /// <summary>
    /// Procesa un evento de pago idempotentemente: si el evento ya existe, no
    /// re-aplica. Activa/renueva la suscripción y sincroniza el exp de la licencia.
    /// </summary>
    public async Task<Resultado<LicenciaResumen>> ProcesarPagoAsync(WebhookPagoRequest req, string payloadCrudo, CancellationToken ct)
    {
        // Idempotencia: ¿ya procesamos este evento?
        var existente = await _db.EventosPago
            .FirstOrDefaultAsync(e => e.EventoIdProveedor == req.EventId, ct);
        if (existente is not null)
        {
            _log.LogInformation("Evento de pago {EventId} ya procesado (idempotente).", req.EventId);
            var licExist = existente.LicenciaId is Guid id
                ? await _db.Licencias.FindAsync(new object?[] { id }, ct)
                : null;
            return licExist is null
                ? Resultado<LicenciaResumen>.Falla(
                    "Evento ya procesado; licencia no encontrada.", 200, CodigosError.LicenciaNoEncontrada)
                : Resultado<LicenciaResumen>.Exito(LicenciaResumen.De(licExist));
        }

        var lic = await BuscarPorClaveAsync(req.LicenseKey, ct);

        var evento = new EventoPago
        {
            EventoIdProveedor = req.EventId,
            Tipo = req.Type,
            Monto = req.Monto,
            Moneda = req.Moneda,
            PayloadCrudo = payloadCrudo,
            LicenciaId = lic?.Id,
            Procesado = false
        };
        _db.EventosPago.Add(evento);

        if (lic is null)
        {
            await _db.SaveChangesAsync(ct);
            return Resultado<LicenciaResumen>.Falla(
                "Clave de licencia del pago no encontrada.", 404, CodigosError.ClaveNoEncontrada);
        }

        var dias = req.Dias ?? 30;
        var ahora = DateTimeOffset.UtcNow;

        // Renovación: extender desde el mayor entre ahora y el exp vigente.
        var baseUnix = lic.ExpUnix > ahora.ToUnixTimeSeconds() ? lic.ExpUnix : ahora.ToUnixTimeSeconds();
        var nuevoExp = DateTimeOffset.FromUnixTimeSeconds(baseUnix).AddDays(dias).ToUnixTimeSeconds();

        if (lic.Tier != Tier.Base)
        {
            lic.ExpUnix = nuevoExp;
            if (lic.Estado is EstadoLicencia.Expirada or EstadoLicencia.Suspendida)
                lic.Estado = EstadoLicencia.Activa;

            var sus = lic.Suscripciones.OrderByDescending(s => s.PeriodoFinUnix).FirstOrDefault();
            if (sus is null)
            {
                sus = new Suscripcion { Licencia = lic };
                _db.Suscripciones.Add(sus);
                lic.Suscripciones.Add(sus);
            }
            sus.Estado = EstadoSuscripcion.Activa;
            sus.PeriodoFinUnix = nuevoExp;
            sus.ActualizadoUtc = DateTime.UtcNow;
        }

        evento.Procesado = true;
        lic.ActualizadoUtc = DateTime.UtcNow;
        RegistrarLog(lic.Id, "pago", lic.HwidActual, $"Pago {req.Type} +{dias}d", true, null);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Pago {EventId} aplicado a licencia {Id}, nuevo exp {Exp}", req.EventId, lic.Id, nuevoExp);
        return Resultado<LicenciaResumen>.Exito(LicenciaResumen.De(lic));
    }

    // ------------------------------------------------------------- Helpers ---

    /// <summary>
    /// Firma el token de la licencia para un dispositivo concreto.
    ///
    /// El claim <c>hwid</c> es el del DISPOSITIVO (para un asiento secundario, el id
    /// del móvil; no el HWID de la PC), de modo que cada equipo valide contra su
    /// propia huella. Los claims <c>device_id</c>/<c>device_prefix</c> son ADITIVOS y
    /// se omiten cuando no hay dispositivo (el emisor ignora los nulos), así que el
    /// token de una licencia sin dispositivo sigue siendo idéntico al de siempre.
    /// </summary>
    private string EmitirToken(Licencia lic, Dispositivo? disp = null)
    {
        var payload = new PayloadToken
        {
            LicenseId = lic.Id.ToString(),
            Tier = lic.Tier.ToString().ToLowerInvariant(),
            Features = lic.Features,
            Hwid = disp?.Hwid ?? lic.HwidActual ?? string.Empty,
            Iat = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            Exp = lic.ExpUnix,
            Sub = string.IsNullOrWhiteSpace(lic.Ruc) ? null : lic.Ruc,
            DeviceId = disp?.Id.ToString(),
            DevicePrefix = string.IsNullOrEmpty(disp?.Prefijo) ? null : disp!.Prefijo
        };
        return _emisor.Emitir(payload);
    }

    private static TokenResponse RespuestaToken(Licencia lic, string token, Dispositivo? disp = null) => new()
    {
        Token = token,
        Tier = lic.Tier.ToString().ToLowerInvariant(),
        Features = lic.Features,
        ExpUnix = lic.ExpUnix,
        DeviceId = disp?.Id,
        DevicePrefix = string.IsNullOrEmpty(disp?.Prefijo) ? null : disp!.Prefijo
    };

    /// <summary>Dispositivo activo de la licencia con esa huella (o null).</summary>
    private static Dispositivo? DispositivoDe(Licencia lic, string hwid) =>
        lic.Dispositivos.FirstOrDefault(d =>
            d.Activo && string.Equals(d.Hwid, hwid, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Asigna el prefijo de dispositivo dentro de la licencia: <c>C01..C99</c> para
    /// equipos de escritorio y <c>M01..M99</c> para móviles. Es el prefijo de los
    /// correlativos (<c>M01-000123</c>) y el valor recomendado de <c>origen_caja_id</c>,
    /// por eso el SERVER es quien lo asigna: es el único que ve todos los dispositivos
    /// de la licencia y puede garantizar unicidad.
    ///
    /// Los prefijos de asientos revocados NO se reutilizan (sus correlativos ya
    /// existen en los tickets del negocio). Devuelve null si se agotaron los 99.
    /// </summary>
    private static string? AsignarPrefijo(Licencia lic, string? plataforma)
    {
        var letra = EsMovil(plataforma) ? 'M' : 'C';

        var usados = new HashSet<int>();
        foreach (var d in lic.Dispositivos)
        {
            var p = d.Prefijo;
            if (p.Length != 3 || char.ToUpperInvariant(p[0]) != letra) continue;
            if (int.TryParse(p.AsSpan(1), out var n)) usados.Add(n);
        }

        for (var i = 1; i <= 99; i++)
            if (!usados.Contains(i))
                return $"{letra}{i:00}";

        return null;
    }

    private static bool EsMovil(string? plataforma) =>
        plataforma?.Trim().ToLowerInvariant() is "android" or "ios" or "movil" or "móvil";

    private Task<Licencia?> BuscarPorClaveAsync(string clave, CancellationToken ct)
    {
        var norm = clave.Trim().ToUpperInvariant();
        return _db.Licencias
            .Include(l => l.Dispositivos)
            .Include(l => l.Suscripciones)
            .FirstOrDefaultAsync(l => l.ClaveLicencia == norm, ct);
    }

    private static bool EstadoOperable(Licencia lic, out string motivo, out string? codigo)
    {
        switch (lic.Estado)
        {
            case EstadoLicencia.Suspendida:
                motivo = "Licencia suspendida. Contacte a soporte.";
                codigo = CodigosError.LicenciaSuspendida;
                return false;
            case EstadoLicencia.Revocada:
                motivo = "Licencia revocada.";
                codigo = CodigosError.LicenciaRevocada;
                return false;
            default:
                motivo = string.Empty;
                codigo = null;
                return true;
        }
    }

    private void VincularHwid(Licencia lic, string hwid)
    {
        lic.HwidActual = hwid;
        var disp = lic.Dispositivos.FirstOrDefault(d => string.Equals(d.Hwid, hwid, StringComparison.OrdinalIgnoreCase));
        if (disp is null)
        {
            // Se agrega vía DbSet (no pre-seteamos la FK) para que EF lo marque
            // como Added y no como Modified sobre un padre ya rastreado.
            var nuevo = new Dispositivo
            {
                Licencia = lic,
                Hwid = hwid,
                Activo = true,
                Tipo = TipoDispositivo.Principal,
                Plataforma = "windows",
                Prefijo = AsignarPrefijo(lic, "windows") ?? string.Empty,
                UltimoVistoUtc = DateTime.UtcNow
            };
            _db.Dispositivos.Add(nuevo);
            lic.Dispositivos.Add(nuevo);
        }
        else
        {
            disp.Activo = true;
            disp.DesvinculadoUtc = null;
            disp.Tipo = TipoDispositivo.Principal; // el equipo del HWID siempre es el principal
            disp.UltimoVistoUtc = DateTime.UtcNow;
            // Filas anteriores al modelo de seats no traen prefijo: se asigna ahora.
            if (string.IsNullOrEmpty(disp.Prefijo))
                disp.Prefijo = AsignarPrefijo(lic, disp.Plataforma ?? "windows") ?? string.Empty;
        }
    }

    /// <summary>
    /// Desvincula el equipo principal (traslado). Sólo toca el dispositivo del
    /// <c>HwidActual</c>: los asientos secundarios (móviles) siguen vigentes, que es
    /// justamente lo que el modelo de seats vino a proteger.
    /// </summary>
    private static void DesvincularHwidActual(Licencia lic)
    {
        var actual = lic.Dispositivos.FirstOrDefault(d =>
            d.Activo && lic.HwidActual is not null &&
            string.Equals(d.Hwid, lic.HwidActual, StringComparison.OrdinalIgnoreCase))
            ?? lic.Dispositivos.FirstOrDefault(d => d.Activo && d.Tipo == TipoDispositivo.Principal);

        if (actual is not null)
        {
            actual.Activo = false;
            actual.DesvinculadoUtc = DateTime.UtcNow;
        }
        lic.HwidActual = null;
    }

    private void RegistrarLog(Guid licenciaId, string accion, string? hwid, string? detalle, bool exito, string? ip)
    {
        _db.LogsActivacion.Add(new LogActivacion
        {
            LicenciaId = licenciaId,
            Accion = accion,
            Hwid = hwid,
            Detalle = detalle,
            Exito = exito,
            IpOrigen = ip
        });
    }

    // ------------------------------------------------- Reglas de dominio ---

    public static bool TryParseTier(string? s, out Tier tier)
    {
        tier = Tier.Base;
        switch (s?.Trim().ToLowerInvariant())
        {
            case "base": tier = Tier.Base; return true;
            case "cloud": tier = Tier.Cloud; return true;
            case "facturador":
            case "facturador_pro": tier = Tier.Facturador; return true;
            default: return false;
        }
    }

    public static string[] FeaturesPorDefecto(Tier tier) => tier switch
    {
        Tier.Cloud => new[] { "cloud_sync", "multi_site" },
        Tier.Facturador => new[] { "cloud_sync", "multi_site", "invoicing" },
        _ => Array.Empty<string>()
    };

    private static readonly HashSet<string> FeaturesCanonicos =
        new(StringComparer.Ordinal) { "invoicing", "cloud_sync", "multi_site" };

    private static bool FeaturesValidos(string[] features, out string? invalido)
    {
        foreach (var f in features)
        {
            if (!FeaturesCanonicos.Contains(f))
            {
                invalido = f;
                return false;
            }
        }
        invalido = null;
        return true;
    }

    /// <summary>Genera una clave legible PAGOYA-XXXX-XXXX-XXXX-XXXX (base32 sin ambiguos).</summary>
    private static string GenerarClaveLicencia()
    {
        const string alfabeto = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sin I,O,0,1
        Span<byte> buf = stackalloc byte[16];
        RandomNumberGenerator.Fill(buf);
        var chars = new char[16];
        for (int i = 0; i < 16; i++) chars[i] = alfabeto[buf[i] % alfabeto.Length];
        return $"PAGOYA-{new string(chars, 0, 4)}-{new string(chars, 4, 4)}-{new string(chars, 8, 4)}-{new string(chars, 12, 4)}";
    }
}
