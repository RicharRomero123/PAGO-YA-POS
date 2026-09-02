using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using PagoYa.Api.Contratos;
using PagoYa.Api.Datos;
using PagoYa.Api.Firma;
using PagoYa.Api.Seguridad;
using PagoYa.Api.Servicios;

// ---------------------------------------------------------------------------
// Subcomando de utilidad: generación del par de claves RSA-2048 de desarrollo.
//   dotnet run -- gen-keys [carpetaSalida]
// Imprime la clave pública (para embeber en el cliente) y guarda la privada
// fuera de git. NUNCA se registra en logs de la app.
// ---------------------------------------------------------------------------
if (args.Length > 0 && args[0] is "gen-keys" or "genkeys")
{
    GenerarClaves(args.Length > 1 ? args[1] : Path.Combine(AppContext.BaseDirectory, "keys"));
    return;
}

var builder = WebApplication.CreateBuilder(args);

// --- Configuración de secciones ---
builder.Services.Configure<OpcionesFirma>(builder.Configuration.GetSection("Firma"));
builder.Services.AddSingleton(sp =>
{
    var cfg = builder.Configuration.GetSection("Firma");
    return new OpcionesFirma
    {
        PrivateKeyPem = cfg["PrivateKeyPem"],
        PrivateKeyPath = cfg["PrivateKeyPath"]
    };
});
builder.Services.AddSingleton<EmisorTokens>();
builder.Services.AddSingleton<VerificadorToken>();

// --- Persistencia SQLite ---
var cs = builder.Configuration.GetConnectionString("Licencias")
         ?? "Data Source=pagoya-licencias.db";
builder.Services.AddDbContext<LicenciasDbContext>(o =>
{
    o.UseSqlite(cs);
    if (builder.Environment.IsDevelopment())
        o.EnableSensitiveDataLogging();
});

builder.Services.AddScoped<ServicioLicencias>();
builder.Services.AddScoped<ServicioAdmin>();
builder.Services.AddScoped<ServicioSync>();
builder.Services.AddScoped<ServicioAuthAdmin>();

// --- CORS para el panel web (Next.js). Orígenes configurables; por defecto el
//     dev server de Next en localhost:3000. Sin cookies (token por cabecera). ---
const string PoliticaSpa = "spa";
var origenesSpa = builder.Configuration.GetSection("Cors:Origenes").Get<string[]>()
                  ?? new[] { "http://localhost:3000", "http://127.0.0.1:3000" };
builder.Services.AddCors(o => o.AddPolicy(PoliticaSpa, p =>
    p.WithOrigins(origenesSpa).AllowAnyHeader().AllowAnyMethod()));

// --- Rate limiting básico (por IP) ---
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    // Global: protege endpoints públicos (activate/validate/webhook).
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
    {
        var key = ctx.Connection.RemoteIpAddress?.ToString() ?? "desconocida";
        return RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 60,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        });
    });

    // Política estricta para activación (anti fuerza bruta de claves).
    options.AddPolicy("activacion", ctx =>
    {
        var key = ctx.Connection.RemoteIpAddress?.ToString() ?? "desconocida";
        return RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 10,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        });
    });
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// --- Crear el esquema (dev): EnsureCreated. En prod usar migraciones. ---
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<LicenciasDbContext>();
    db.Database.EnsureCreated();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRateLimiter();
app.UseCors(PoliticaSpa);

// Panel web de administración (SPA estática servida desde wwwroot).
app.UseDefaultFiles();
app.UseStaticFiles();

var jsonOpts = new JsonSerializerOptions(JsonSerializerDefaults.Web);

// Helper local: exige API key de admin (vía cabecera). Ruta programática/legacy.
bool EsAdmin(HttpContext ctx)
{
    var esperada = app.Configuration["Admin:ApiKey"];
    if (string.IsNullOrWhiteSpace(esperada)) return false; // sin key configurada => denegar
    var recibida = ctx.Request.Headers["X-Admin-ApiKey"].ToString();
    return CryptographicOperations.FixedTimeEquals(
        System.Text.Encoding.UTF8.GetBytes(recibida),
        System.Text.Encoding.UTF8.GetBytes(esperada));
}

// Auth de los endpoints admin: acepta la API key (legacy/scripts) O una sesión
// válida del panel web (cabecera X-Admin-Token emitida al iniciar sesión).
async Task<bool> EsAdminAsync(HttpContext ctx, ServicioAuthAdmin auth)
{
    if (EsAdmin(ctx)) return true;
    var token = ctx.Request.Headers["X-Admin-Token"].ToString();
    return await auth.ValidarSesionAsync(token, ctx.RequestAborted);
}

IResult NoAutorizado() => Results.Json(new ErrorResponse("Sesión de administrador inválida o ausente."), statusCode: 401);

static IResult DesdeResultado<T>(Resultado<T> r) =>
    r.Ok
        ? Results.Ok(r.Valor)
        : Results.Json(new ErrorResponse(r.Error ?? "Error"), statusCode: r.Http);

static string? Ip(HttpContext ctx) => ctx.Connection.RemoteIpAddress?.ToString();

// Autentica una petición de sync por el token de licencia (Bearer). Exige firma
// válida, no expirado y flag "cloud_sync". Devuelve la licencia (tenant) del token.
static bool AutenticarSync(HttpContext ctx, VerificadorToken verificador, out Guid licenciaId, out IResult? error)
{
    licenciaId = Guid.Empty;
    error = null;

    var auth = ctx.Request.Headers.Authorization.ToString();
    var token = auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? auth[7..].Trim() : auth.Trim();

    if (!verificador.TryVerificar(token, out var payload, out var motivo) || payload is null)
    {
        error = Results.Json(new ErrorResponse(motivo ?? "Token inválido."), statusCode: 401);
        return false;
    }
    if (!VerificadorToken.ExigeFeature(payload, "cloud_sync"))
    {
        error = Results.Json(new ErrorResponse("La licencia no habilita la sincronización en la nube."), statusCode: 403);
        return false;
    }
    if (!Guid.TryParse(payload.LicenseId, out licenciaId))
    {
        error = Results.Json(new ErrorResponse("El token no identifica una licencia válida."), statusCode: 401);
        return false;
    }
    return true;
}

// ======================================================================
//  ENDPOINTS
// ======================================================================

// Chequeo de salud en /health (la raíz "/" la sirve el panel web estático de wwwroot).
app.MapGet("/health", () => Results.Ok(new { servicio = "PagoYa Licensing API", version = "1.0", estado = "ok" }));

// --- POST /licenses : emisión manual (protegido con API key admin) ---
app.MapPost("/licenses", async (HttpContext ctx, EmitirLicenciaRequest req, ServicioLicencias svc, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    if (!await EsAdminAsync(ctx, auth)) return NoAutorizado();
    var r = await svc.EmitirAsync(req, ct);
    return r.Ok ? Results.Created($"/licenses/{r.Valor!.LicenciaId}", r.Valor) : DesdeResultado(r);
});

// --- POST /activate : vincula HWID y devuelve token firmado ---
app.MapPost("/activate", async (HttpContext ctx, ActivarRequest req, ServicioLicencias svc, CancellationToken ct) =>
{
    var r = await svc.ActivarAsync(req, Ip(ctx), ct);
    return DesdeResultado(r);
}).RequireRateLimiting("activacion");

// --- POST /validate : revalidación / renovación silenciosa ---
app.MapPost("/validate", async (HttpContext ctx, ValidarRequest req, ServicioLicencias svc, CancellationToken ct) =>
{
    var r = await svc.ValidarAsync(req, Ip(ctx), ct);
    return DesdeResultado(r);
}).RequireRateLimiting("activacion");

// --- POST /sync/push : sube el outbox del cliente (auth por token Cloud) ---
app.MapPost("/sync/push", async (HttpContext ctx, SyncPushRequest req, ServicioSync svc, VerificadorToken ver, CancellationToken ct) =>
{
    if (!AutenticarSync(ctx, ver, out var licenciaId, out var error)) return error!;
    var resp = await svc.ProcesarPushAsync(licenciaId, req, ct);
    return Results.Ok(resp);
});

// --- GET /sync/pull : descarga cambios remotos desde el cursor (auth por token Cloud) ---
app.MapGet("/sync/pull", async (HttpContext ctx, ServicioSync svc, VerificadorToken ver, string? cursor, CancellationToken ct) =>
{
    if (!AutenticarSync(ctx, ver, out var licenciaId, out var error)) return error!;
    var resp = await svc.ObtenerCambiosAsync(licenciaId, cursor, ct);
    return Results.Ok(resp);
});

// --- POST /webhooks/payment : confirma pago; idempotente + firma HMAC ---
app.MapPost("/webhooks/payment", async (HttpContext ctx, ServicioLicencias svc, CancellationToken ct) =>
{
    // Leemos el cuerpo crudo para (a) verificar HMAC y (b) auditar.
    ctx.Request.EnableBuffering();
    using var reader = new StreamReader(ctx.Request.Body, leaveOpen: true);
    var cuerpo = await reader.ReadToEndAsync(ct);
    ctx.Request.Body.Position = 0;

    var secreto = app.Configuration["Webhook:HmacSecret"];
    if (!string.IsNullOrWhiteSpace(secreto))
    {
        var firma = ctx.Request.Headers["X-PagoYa-Signature"].ToString();
        if (!VerificadorHmac.Verificar(secreto, cuerpo, firma))
            return Results.Json(new ErrorResponse("Firma HMAC del webhook inválida."), statusCode: 401);
    }

    WebhookPagoRequest? req;
    try { req = JsonSerializer.Deserialize<WebhookPagoRequest>(cuerpo, jsonOpts); }
    catch (JsonException) { return Results.Json(new ErrorResponse("JSON inválido."), statusCode: 400); }

    if (req is null || string.IsNullOrWhiteSpace(req.EventId) || string.IsNullOrWhiteSpace(req.LicenseKey))
        return Results.Json(new ErrorResponse("Faltan campos requeridos (event_id, license_key)."), statusCode: 400);

    var r = await svc.ProcesarPagoAsync(req, cuerpo, ct);
    return DesdeResultado(r);
});

// ---------------------- Autenticación del panel web --------------------

// Estado del bootstrap: ¿hay que crear la cuenta admin? (la web muestra registro).
app.MapGet("/admin/auth/setup-estado", async (ServicioAuthAdmin auth, CancellationToken ct) =>
    Results.Ok(new SetupEstadoResponse { NecesitaSetup = await auth.NecesitaSetupAsync(ct) }));

// Crear la cuenta admin inicial (solo si aún no existe ninguna).
app.MapPost("/admin/auth/registro", async (RegistroAdminRequest req, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    var r = await auth.RegistrarAsync(req, ct);
    return DesdeResultado(r);
}).RequireRateLimiting("activacion");

// Iniciar sesión: devuelve el token que el navegador guarda.
app.MapPost("/admin/auth/login", async (LoginAdminRequest req, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    var r = await auth.LoginAsync(req, ct);
    return DesdeResultado(r);
}).RequireRateLimiting("activacion");

// Cerrar sesión (invalida el token).
app.MapPost("/admin/auth/logout", async (HttpContext ctx, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    await auth.CerrarSesionAsync(ctx.Request.Headers["X-Admin-Token"].ToString(), ct);
    return Results.Ok(new { ok = true });
});

// ---------------------- Endpoints admin (protegidos) -------------------

app.MapGet("/admin/licenses", async (HttpContext ctx, ServicioAdmin svc, ServicioAuthAdmin auth, string? estado, int? limite, CancellationToken ct) =>
{
    if (!await EsAdminAsync(ctx, auth)) return NoAutorizado();
    var items = await svc.ListarAsync(estado, limite ?? 100, ct);
    return Results.Ok(items);
});

app.MapGet("/admin/licenses/{id:guid}", async (HttpContext ctx, Guid id, ServicioAdmin svc, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    if (!await EsAdminAsync(ctx, auth)) return NoAutorizado();
    var lic = await svc.ObtenerAsync(id, ct);
    return lic is null ? Results.NotFound(new ErrorResponse("Licencia no encontrada.")) : Results.Ok(lic);
});

app.MapPost("/admin/licenses/{id:guid}/suspend", async (HttpContext ctx, Guid id, ServicioAdmin svc, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    if (!await EsAdminAsync(ctx, auth)) return NoAutorizado();
    var motivo = ctx.Request.Query["motivo"].ToString();
    var r = await svc.SuspenderAsync(id, string.IsNullOrWhiteSpace(motivo) ? null : motivo, ct);
    return DesdeResultado(r);
});

app.MapPost("/admin/licenses/{id:guid}/reactivate", async (HttpContext ctx, Guid id, ServicioAdmin svc, ServicioAuthAdmin auth, CancellationToken ct) =>
{
    if (!await EsAdminAsync(ctx, auth)) return NoAutorizado();
    var r = await svc.ReactivarAsync(id, ct);
    return DesdeResultado(r);
});

app.Run();

// ---------------------------------------------------------------------------
// Utilidad local de generación de claves de desarrollo.
// ---------------------------------------------------------------------------
static void GenerarClaves(string carpeta)
{
    Directory.CreateDirectory(carpeta);
    using var rsa = RSA.Create(2048);
    var priv = rsa.ExportPkcs8PrivateKeyPem();
    var pub = rsa.ExportSubjectPublicKeyInfoPem();

    var rutaPriv = Path.Combine(carpeta, "pagoya_private_dev.pem");
    var rutaPub = Path.Combine(carpeta, "pagoya_public_dev.pem");
    File.WriteAllText(rutaPriv, priv);
    File.WriteAllText(rutaPub, pub);

    Console.WriteLine("== PagoYa: par de claves RSA-2048 de DESARROLLO generado ==");
    Console.WriteLine($"Privada (NO versionar): {rutaPriv}");
    Console.WriteLine($"Pública:                {rutaPub}");
    Console.WriteLine();
    Console.WriteLine("Configura la privada con user-secrets (recomendado):");
    Console.WriteLine("  dotnet user-secrets set \"Firma:PrivateKeyPath\" \"" + rutaPriv.Replace("\\", "\\\\") + "\"");
    Console.WriteLine();
    Console.WriteLine("Embebe ESTA clave pública en src/PagoYa.Licensing/ClavePublicaEmbebida.cs:");
    Console.WriteLine();
    Console.WriteLine(pub);
}

// Necesario para WebApplicationFactory / tests de integración (opcional).
public partial class Program { }
