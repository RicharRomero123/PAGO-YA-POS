using System.Net;
using PagoYa.Cloud;
using PagoYa.Core.Contratos;
using Xunit;

namespace PagoYa.Cloud.Tests;

/// <summary>
/// Verifica que <see cref="HttpSyncTransport"/> forma bien las peticiones HTTP
/// (método, ruta, Bearer, cuerpo) y parsea las respuestas, sin red real: usa un
/// <see cref="HttpMessageHandler"/> stub que captura la request y devuelve JSON fijo.
/// </summary>
public sealed class HttpSyncTransportTests
{
    private static HttpSyncTransport Crear(StubHandler stub, string origen = "") =>
        new(new HttpClient(stub), new OpcionesSync
        {
            UrlBase = "http://test.local/",
            TokenLicencia = "TOK123",
            OrigenCajaId = origen
        });

    private static EventoSyncLocal Evento(Guid id) =>
        new(id, "producto", Guid.NewGuid(), "UPSERT", "{\"Nombre\":\"X\"}", 0, "cajaA", DateTime.UtcNow);

    [Fact]
    public async Task Push_EnviaPostConBearerYBody_yParseaAceptados()
    {
        var id = Guid.NewGuid();
        var stub = new StubHandler((_, _) => (HttpStatusCode.OK, $"{{\"aceptados\":[\"{id}\"]}}"));
        var transporte = Crear(stub);

        var res = await transporte.EnviarLoteAsync(new[] { Evento(id) });

        // Request bien formada.
        Assert.Equal(HttpMethod.Post, stub.Ultima!.Method);
        Assert.Equal("/sync/push", stub.Ultima.RequestUri!.AbsolutePath);
        Assert.Equal("Bearer", stub.Ultima.Headers.Authorization!.Scheme);
        Assert.Equal("TOK123", stub.Ultima.Headers.Authorization.Parameter);
        Assert.Contains("eventos", stub.UltimoBody);
        Assert.Contains(id.ToString(), stub.UltimoBody);

        // Respuesta parseada.
        Assert.True(res.Ok, res.Error);
        Assert.Contains(id, res.AceptadosIds);
    }

    [Fact]
    public async Task Pull_UsaCursorEnQuery_yParseaCambiosYCursor()
    {
        var gid = Guid.NewGuid();
        var json = $$"""
            {"cambios":[{"entidad":"producto","entidadId":"{{gid}}","operacion":"UPSERT",
            "payloadJson":"{}","actualizadoUtc":"2026-08-26T10:00:00Z","origenCajaId":"cajaB"}],"cursor":"9"}
            """;
        var stub = new StubHandler((_, _) => (HttpStatusCode.OK, json));
        var transporte = Crear(stub);

        var paquete = await transporte.DescargarCambiosAsync("3");

        Assert.Equal("/sync/pull", stub.Ultima!.RequestUri!.AbsolutePath);
        Assert.Contains("cursor=3", stub.Ultima.RequestUri.Query);
        Assert.Single(paquete.Cambios);
        Assert.Equal("producto", paquete.Cambios[0].Entidad);
        Assert.Equal(gid, paquete.Cambios[0].EntidadId);
        Assert.Equal("9", paquete.Cursor);
    }

    [Fact]
    public async Task Push_ErrorHttp_DevuelveFalla()
    {
        var stub = new StubHandler((_, _) => (HttpStatusCode.InternalServerError, "{}"));
        var transporte = Crear(stub);

        var res = await transporte.EnviarLoteAsync(new[] { Evento(Guid.NewGuid()) });

        Assert.False(res.Ok);
        Assert.NotNull(res.Error);
    }

    // ======================================================================
    //  FILTRO DE ECO: ?origen= (server/README.md §7.1)
    // ======================================================================

    /// <summary>
    /// El pull manda `origen` con el MISMO valor que se estampa en
    /// `origen_caja_id` al subir. Sin él, el backend no filtra el eco y esta caja
    /// se baja y re-aplica sus propias ventas.
    /// </summary>
    [Fact]
    public async Task Pull_MandaOrigen_ParaElFiltroDeEco()
    {
        var stub = new StubHandler((_, _) => (HttpStatusCode.OK, """{"cambios":[],"cursor":"12"}"""));
        var transporte = Crear(stub, origen: "C01");

        await transporte.DescargarCambiosAsync("7");

        var query = stub.Ultima!.RequestUri!.Query;
        Assert.Contains("cursor=7", query);
        Assert.Contains("origen=C01", query);
    }

    /// <summary>Sin cursor (primer arranque) el origen igual viaja.</summary>
    [Fact]
    public async Task Pull_SinCursor_IgualMandaOrigen()
    {
        var stub = new StubHandler((_, _) => (HttpStatusCode.OK, """{"cambios":[],"cursor":"0"}"""));
        var transporte = Crear(stub, origen: "C01");

        await transporte.DescargarCambiosAsync(null);

        Assert.Equal("/sync/pull", stub.Ultima!.RequestUri!.AbsolutePath);
        Assert.Equal("?origen=C01", stub.Ultima.RequestUri.Query);
    }

    /// <summary>
    /// Equipo aún no vinculado (sin prefijo del server): no se inventa un origen,
    /// no se manda el parámetro y el backend no filtra — igual que antes.
    /// </summary>
    [Fact]
    public async Task Pull_SinOrigenConfigurado_NoMandaElParametro()
    {
        var stub = new StubHandler((_, _) => (HttpStatusCode.OK, """{"cambios":[],"cursor":"3"}"""));
        var transporte = Crear(stub); // origen vacío

        await transporte.DescargarCambiosAsync("3");

        Assert.DoesNotContain("origen=", stub.Ultima!.RequestUri!.Query);
    }

    // ======================================================================
    //  CÓDIGOS DE ERROR (server/README.md §10): se ramifica por `codigo`
    // ======================================================================

    /// <summary>
    /// Los dos 403 de /sync/* no se confunden: sin flag de nube → upsell;
    /// asiento revocado → volver a vincular. Se distinguen por `codigo`, no por
    /// el texto de `error` (que se reescribe sin aviso).
    /// </summary>
    [Theory]
    [InlineData(CodigosErrorSync.SinFlagCloudSync)]
    [InlineData(CodigosErrorSync.AsientoRevocado)]
    public async Task Push_403_PropagaElCodigoMachineReadable(string codigo)
    {
        var stub = new StubHandler((_, _) =>
            (HttpStatusCode.Forbidden, $$"""{"error":"texto que puede cambiar","codigo":"{{codigo}}"}"""));
        var transporte = Crear(stub, origen: "C01");

        var res = await transporte.EnviarLoteAsync(new[] { Evento(Guid.NewGuid()) });

        Assert.False(res.Ok);
        Assert.Equal(codigo, res.Codigo);
    }

    [Fact]
    public async Task Pull_401TokenExpirado_LanzaConElCodigo()
    {
        var stub = new StubHandler((_, _) =>
            (HttpStatusCode.Unauthorized, """{"error":"Token vencido","codigo":"token_expirado"}"""));
        var transporte = Crear(stub, origen: "C01");

        var ex = await Assert.ThrowsAsync<SyncTransporteException>(
            () => transporte.DescargarCambiosAsync("1"));

        Assert.Equal(CodigosErrorSync.TokenExpirado, ex.Codigo);
    }

    /// <summary>
    /// Backend anterior al catálogo (respuesta sin `codigo`): no se adivina por el
    /// texto — se degrada al status y `Codigo` queda null.
    /// </summary>
    [Fact]
    public async Task Push_ErrorSinCodigo_NoInventaUnCodigo()
    {
        var stub = new StubHandler((_, _) =>
            (HttpStatusCode.Forbidden, """{"error":"No autorizado"}"""));
        var transporte = Crear(stub);

        var res = await transporte.EnviarLoteAsync(new[] { Evento(Guid.NewGuid()) });

        Assert.False(res.Ok);
        Assert.Null(res.Codigo);
        Assert.Contains("No autorizado", res.Error);
    }

    /// <summary>Handler HTTP falso: captura la última request y su cuerpo, y responde según una función.</summary>
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, (HttpStatusCode, string)> _responder;

        public HttpRequestMessage? Ultima { get; private set; }
        public string? UltimoBody { get; private set; }

        public StubHandler(Func<HttpRequestMessage, CancellationToken, (HttpStatusCode, string)> responder)
            => _responder = responder;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Ultima = request;
            if (request.Content is not null)
                UltimoBody = await request.Content.ReadAsStringAsync(ct);

            var (code, body) = _responder(request, ct);
            return new HttpResponseMessage(code)
            {
                Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json")
            };
        }
    }
}
