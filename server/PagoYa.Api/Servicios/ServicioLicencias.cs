using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;
using PagoYa.Api.Firma;

namespace PagoYa.Api.Servicios;

/// <summary>Resultado de una operación de negocio (evita excepciones para control de flujo).</summary>
public readonly record struct Resultado<T>(bool Ok, T? Valor, string? Error, int Http)
{
    public static Resultado<T> Exito(T valor) => new(true, valor, null, 200);
    public static Resultado<T> Falla(string error, int http) => new(false, default, error, http);
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
            return Resultado<EmitirLicenciaResponse>.Falla($"Tier inválido: '{req.Tier}'. Use base|cloud|facturador.", 400);

        var features = req.Features ?? FeaturesPorDefecto(tier);
        if (!FeaturesValidos(features, out var invalido))
            return Resultado<EmitirLicenciaResponse>.Falla($"Feature inválido: '{invalido}'.", 400);

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
            HwidActual = string.IsNullOrWhiteSpace(req.Hwid) ? null : req.Hwid.Trim()
        };

        if (licencia.HwidActual is not null)
        {
            licencia.Estado = EstadoLicencia.Activa;
            licencia.Dispositivos.Add(new Dispositivo { Hwid = licencia.HwidActual, Activo = true });
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
            return Resultado<TokenResponse>.Falla("Clave de licencia no encontrada.", 404);

        if (!EstadoOperable(lic, out var motivoEstado))
        {
            RegistrarLog(lic.Id, "rechazo", hwid, motivoEstado, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(motivoEstado, 409);
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
                return Resultado<TokenResponse>.Falla(msg, 409);
            }

            DesvincularHwidActual(lic);
            VincularHwid(lic, hwid);
            lic.TrasladosUsados++;
            RegistrarLog(lic.Id, "traslado", hwid,
                $"Traslado {lic.TrasladosUsados}/{lic.MaxTraslados} a nuevo equipo", true, ip);
        }

        lic.ActualizadoUtc = DateTime.UtcNow;
        var token = EmitirToken(lic);
        await _db.SaveChangesAsync(ct);

        return Resultado<TokenResponse>.Exito(RespuestaToken(lic, token));
    }

    // ---------------------------------------------------- Validar/renovar ---

    public async Task<Resultado<TokenResponse>> ValidarAsync(ValidarRequest req, string? ip, CancellationToken ct)
    {
        var hwid = req.Hwid.Trim();
        var lic = await BuscarPorClaveAsync(req.LicenseKey, ct);
        if (lic is null)
            return Resultado<TokenResponse>.Falla("Clave de licencia no encontrada.", 404);

        if (!EstadoOperable(lic, out var motivoEstado))
        {
            RegistrarLog(lic.Id, "rechazo", hwid, motivoEstado, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(motivoEstado, 409);
        }

        // El HWID debe coincidir con el vinculado (la revalidación no traslada).
        if (!string.IsNullOrEmpty(lic.HwidActual) &&
            !string.Equals(lic.HwidActual, hwid, StringComparison.OrdinalIgnoreCase))
        {
            var msg = "El HWID no coincide con el equipo vinculado. Use /activate para trasladar.";
            RegistrarLog(lic.Id, "rechazo", hwid, msg, false, ip);
            await _db.SaveChangesAsync(ct);
            return Resultado<TokenResponse>.Falla(msg, 409);
        }

        if (string.IsNullOrEmpty(lic.HwidActual))
            VincularHwid(lic, hwid);

        // Renovación: para suscripciones con periodo pagado vigente, extendemos el
        // exp del token hasta el fin de periodo. Base permanece perpetua.
        var token = EmitirToken(lic);
        RegistrarLog(lic.Id, "validacion", hwid, "Revalidación/renovación", true, ip);
        lic.ActualizadoUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return Resultado<TokenResponse>.Exito(RespuestaToken(lic, token));
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
                ? Resultado<LicenciaResumen>.Falla("Evento ya procesado; licencia no encontrada.", 200)
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
            return Resultado<LicenciaResumen>.Falla("Clave de licencia del pago no encontrada.", 404);
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

    private string EmitirToken(Licencia lic)
    {
        var payload = new PayloadToken
        {
            LicenseId = lic.Id.ToString(),
            Tier = lic.Tier.ToString().ToLowerInvariant(),
            Features = lic.Features,
            Hwid = lic.HwidActual ?? string.Empty,
            Iat = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            Exp = lic.ExpUnix,
            Sub = string.IsNullOrWhiteSpace(lic.Ruc) ? null : lic.Ruc
        };
        return _emisor.Emitir(payload);
    }

    private static TokenResponse RespuestaToken(Licencia lic, string token) => new()
    {
        Token = token,
        Tier = lic.Tier.ToString().ToLowerInvariant(),
        Features = lic.Features,
        ExpUnix = lic.ExpUnix
    };

    private Task<Licencia?> BuscarPorClaveAsync(string clave, CancellationToken ct)
    {
        var norm = clave.Trim().ToUpperInvariant();
        return _db.Licencias
            .Include(l => l.Dispositivos)
            .Include(l => l.Suscripciones)
            .FirstOrDefaultAsync(l => l.ClaveLicencia == norm, ct);
    }

    private static bool EstadoOperable(Licencia lic, out string motivo)
    {
        switch (lic.Estado)
        {
            case EstadoLicencia.Suspendida:
                motivo = "Licencia suspendida. Contacte a soporte.";
                return false;
            case EstadoLicencia.Revocada:
                motivo = "Licencia revocada.";
                return false;
            default:
                motivo = string.Empty;
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
            var nuevo = new Dispositivo { Licencia = lic, Hwid = hwid, Activo = true };
            _db.Dispositivos.Add(nuevo);
            lic.Dispositivos.Add(nuevo);
        }
        else
        {
            disp.Activo = true;
            disp.DesvinculadoUtc = null;
        }
    }

    private static void DesvincularHwidActual(Licencia lic)
    {
        var actual = lic.Dispositivos.FirstOrDefault(d => d.Activo);
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
