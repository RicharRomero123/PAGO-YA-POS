using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Dominio;

namespace PagoYa.Api.Datos;

/// <summary>
/// Contexto EF Core (SQLite en dev). Tablas: Licenses, Devices, Subscriptions,
/// PaymentEvents, ActivationLogs. Ver docs/LICENSE-TOKEN.md para el contrato.
/// </summary>
public sealed class LicenciasDbContext : DbContext
{
    public LicenciasDbContext(DbContextOptions<LicenciasDbContext> options) : base(options) { }

    public DbSet<Licencia> Licencias => Set<Licencia>();
    public DbSet<Dispositivo> Dispositivos => Set<Dispositivo>();
    public DbSet<Suscripcion> Suscripciones => Set<Suscripcion>();
    public DbSet<EventoPago> EventosPago => Set<EventoPago>();
    public DbSet<LogActivacion> LogsActivacion => Set<LogActivacion>();
    public DbSet<EventoSync> EventosSync => Set<EventoSync>();
    public DbSet<AdminUsuario> AdminUsuarios => Set<AdminUsuario>();
    public DbSet<AdminSesion> AdminSesiones => Set<AdminSesion>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Licencia>(e =>
        {
            e.ToTable("Licenses");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.ClaveLicencia).IsUnique();
            e.Property(x => x.ClaveLicencia).IsRequired();
            e.Property(x => x.FeaturesCsv).HasDefaultValue(string.Empty);
            e.Ignore(x => x.Features);
        });

        b.Entity<Dispositivo>(e =>
        {
            e.ToTable("Devices");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.LicenciaId, x.Hwid });
            e.HasOne(x => x.Licencia)
                .WithMany(l => l.Dispositivos)
                .HasForeignKey(x => x.LicenciaId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Suscripcion>(e =>
        {
            e.ToTable("Subscriptions");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Licencia)
                .WithMany(l => l.Suscripciones)
                .HasForeignKey(x => x.LicenciaId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<EventoPago>(e =>
        {
            e.ToTable("PaymentEvents");
            e.HasKey(x => x.Id);
            // Idempotencia: el id de evento del proveedor es único.
            e.HasIndex(x => x.EventoIdProveedor).IsUnique();
        });

        b.Entity<LogActivacion>(e =>
        {
            e.ToTable("ActivationLogs");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Licencia)
                .WithMany(l => l.LogsActivacion)
                .HasForeignKey(x => x.LicenciaId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<EventoSync>(e =>
        {
            e.ToTable("SyncEvents");
            e.HasKey(x => x.Secuencia);
            e.Property(x => x.Secuencia).ValueGeneratedOnAdd(); // autoincremental = cursor
            // Idempotencia del push: un evento del cliente entra una sola vez por licencia.
            e.HasIndex(x => new { x.LicenciaId, x.EventoIdCliente }).IsUnique();
            // Pull eficiente por (tenant, cursor).
            e.HasIndex(x => new { x.LicenciaId, x.Secuencia });
        });

        b.Entity<AdminUsuario>(e =>
        {
            e.ToTable("AdminUsers");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Usuario).IsUnique();
            e.Property(x => x.Usuario).IsRequired();
        });

        b.Entity<AdminSesion>(e =>
        {
            e.ToTable("AdminSessions");
            e.HasKey(x => x.Token);
            e.HasIndex(x => x.ExpiraUtc); // purga de vencidas
        });
    }
}
