using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Servicios;

/// <summary>Operaciones administrativas: listar, suspender, reactivar licencias.</summary>
public sealed class ServicioAdmin
{
    private readonly LicenciasDbContext _db;
    private readonly ILogger<ServicioAdmin> _log;

    public ServicioAdmin(LicenciasDbContext db, ILogger<ServicioAdmin> log)
    {
        _db = db;
        _log = log;
    }

    public async Task<IReadOnlyList<LicenciaResumen>> ListarAsync(string? estado, int limite, CancellationToken ct)
    {
        IQueryable<Licencia> q = _db.Licencias.AsNoTracking().OrderByDescending(l => l.CreadoUtc);

        if (!string.IsNullOrWhiteSpace(estado) && Enum.TryParse<EstadoLicencia>(estado, true, out var e))
            q = q.Where(l => l.Estado == e);

        var items = await q.Take(Math.Clamp(limite, 1, 500)).ToListAsync(ct);
        return items.Select(LicenciaResumen.De).ToList();
    }

    public async Task<LicenciaResumen?> ObtenerAsync(Guid id, CancellationToken ct)
    {
        var lic = await _db.Licencias.AsNoTracking().FirstOrDefaultAsync(l => l.Id == id, ct);
        return lic is null ? null : LicenciaResumen.De(lic);
    }

    public async Task<Resultado<LicenciaResumen>> SuspenderAsync(Guid id, string? motivo, CancellationToken ct)
        => await CambiarEstadoAsync(id, EstadoLicencia.Suspendida, "suspension", motivo ?? "Suspendida por admin", ct);

    public async Task<Resultado<LicenciaResumen>> ReactivarAsync(Guid id, CancellationToken ct)
        => await CambiarEstadoAsync(id, EstadoLicencia.Activa, "reactivacion", "Reactivada por admin", ct);

    private async Task<Resultado<LicenciaResumen>> CambiarEstadoAsync(
        Guid id, EstadoLicencia nuevo, string accion, string detalle, CancellationToken ct)
    {
        var lic = await _db.Licencias.FirstOrDefaultAsync(l => l.Id == id, ct);
        if (lic is null)
            return Resultado<LicenciaResumen>.Falla("Licencia no encontrada.", 404);

        if (lic.Estado == EstadoLicencia.Revocada)
            return Resultado<LicenciaResumen>.Falla("La licencia está revocada; no se puede cambiar.", 409);

        lic.Estado = nuevo;
        lic.ActualizadoUtc = DateTime.UtcNow;
        _db.LogsActivacion.Add(new LogActivacion
        {
            LicenciaId = lic.Id,
            Accion = accion,
            Detalle = detalle,
            Exito = true
        });
        await _db.SaveChangesAsync(ct);
        _log.LogInformation("Licencia {Id} -> {Estado}", id, nuevo);
        return Resultado<LicenciaResumen>.Exito(LicenciaResumen.De(lic));
    }
}
