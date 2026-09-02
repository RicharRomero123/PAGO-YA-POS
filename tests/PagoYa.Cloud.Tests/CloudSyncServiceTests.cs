using PagoYa.Cloud;
using PagoYa.Core.Contratos;
using Xunit;

namespace PagoYa.Cloud.Tests;

/// <summary>
/// Orquestación de <see cref="CloudSyncService"/> con outbox y transporte
/// simulados (control determinista de aceptación/fallo).
/// </summary>
public sealed class CloudSyncServiceTests
{
    private static EventoSyncLocal Evento(string n) =>
        new(Guid.NewGuid(), "producto", Guid.NewGuid(), "UPSERT", "{}", 0, "cajaA", DateTime.UtcNow);

    [Fact]
    public async Task Push_TodoAceptado_MarcaEnviadosYCuenta()
    {
        var outbox = new OutboxFake(Evento("a"), Evento("b"), Evento("c"));
        var transporte = new TransporteFake { AceptarTodo = true };
        var svc = new CloudSyncService(outbox, transporte, new OpcionesSync { TamanoLote = 100 });

        var res = await svc.SincronizarAsync();

        Assert.True(res.Exito, res.Mensaje);
        Assert.Equal(3, res.Enviados);
        Assert.Equal(3, outbox.Enviados.Count);
        Assert.Empty(outbox.Pendientes); // se vació la cola
    }

    [Fact]
    public async Task Push_FalloDeTransporte_NoMarcaEnviados_yRegistraFallo()
    {
        var outbox = new OutboxFake(Evento("a"), Evento("b"));
        var transporte = new TransporteFake { AceptarTodo = false, Falla = true };
        var svc = new CloudSyncService(outbox, transporte, new OpcionesSync { MaxIntentos = 5 });

        var res = await svc.SincronizarAsync();

        Assert.False(res.Exito);
        Assert.Empty(outbox.Enviados);
        Assert.Equal(2, outbox.FallosRegistrados); // los 2 del lote contaron intento
    }

    [Fact]
    public async Task Push_AceptacionParcial_MarcaAceptados_yFallaElResto()
    {
        var e1 = Evento("a");
        var e2 = Evento("b");
        var outbox = new OutboxFake(e1, e2);
        var transporte = new TransporteFake { SoloAceptar = new HashSet<Guid> { e1.Id } };
        var svc = new CloudSyncService(outbox, transporte);

        var res = await svc.SincronizarAsync();

        Assert.True(res.Exito, res.Mensaje);
        Assert.Equal(1, res.Enviados);
        Assert.Contains(e1.Id, outbox.Enviados);
        Assert.Equal(1, outbox.FallosRegistrados); // e2 no aceptado => intento
    }

    [Fact]
    public async Task Pull_AplicaCambios_yGuardaCursor()
    {
        var outbox = new OutboxFake();
        var transporte = new TransporteFake
        {
            AceptarTodo = true,
            CambiosBajada = new List<CambioRemoto>
            {
                new("producto", Guid.NewGuid(), "UPSERT", "{}", DateTime.UtcNow, "cajaB")
            },
            CursorBajada = "7"
        };
        var svc = new CloudSyncService(outbox, transporte);

        var res = await svc.SincronizarAsync();

        Assert.True(res.Exito);
        Assert.Equal(1, res.Recibidos);
        Assert.Equal("7", outbox.CursorGuardado);
    }

    // ------------------------------------------------------------- Fakes ---

    private sealed class OutboxFake : IOutboxStore
    {
        public List<EventoSyncLocal> Pendientes { get; }
        public List<Guid> Enviados { get; } = new();
        public int FallosRegistrados { get; private set; }
        public string? CursorGuardado { get; private set; }

        public OutboxFake(params EventoSyncLocal[] pendientes) => Pendientes = pendientes.ToList();

        public Task<IReadOnlyList<EventoSyncLocal>> LeerPendientesAsync(int max, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<EventoSyncLocal>>(Pendientes.Take(max).ToList());

        public Task MarcarEnviadosAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct = default)
        {
            Enviados.AddRange(ids);
            Pendientes.RemoveAll(e => ids.Contains(e.Id));
            return Task.CompletedTask;
        }

        public Task RegistrarFalloAsync(IReadOnlyCollection<Guid> ids, int maxIntentos, CancellationToken ct = default)
        {
            FallosRegistrados += ids.Count;
            Pendientes.RemoveAll(e => ids.Contains(e.Id)); // evita bucle infinito en el test
            return Task.CompletedTask;
        }

        public Task<int> AplicarCambiosRemotosAsync(IReadOnlyList<CambioRemoto> cambios, CancellationToken ct = default)
            => Task.FromResult(cambios.Count);

        public Task<string?> LeerCursorAsync(CancellationToken ct = default) => Task.FromResult<string?>(null);
        public Task GuardarCursorAsync(string cursor, CancellationToken ct = default)
        {
            CursorGuardado = cursor;
            return Task.CompletedTask;
        }
    }

    private sealed class TransporteFake : ISyncTransport
    {
        public bool AceptarTodo { get; set; }
        public bool Falla { get; set; }
        public HashSet<Guid>? SoloAceptar { get; set; }
        public List<CambioRemoto> CambiosBajada { get; set; } = new();
        public string CursorBajada { get; set; } = "0";

        public Task<ResultadoLote> EnviarLoteAsync(IReadOnlyList<EventoSyncLocal> lote, CancellationToken ct = default)
        {
            if (Falla) return Task.FromResult(ResultadoLote.Falla("sin conexión"));
            var ids = SoloAceptar is not null
                ? lote.Where(e => SoloAceptar.Contains(e.Id)).Select(e => e.Id).ToArray()
                : AceptarTodo ? lote.Select(e => e.Id).ToArray() : Array.Empty<Guid>();
            return Task.FromResult(ResultadoLote.Exito(ids));
        }

        public Task<PaqueteRemoto> DescargarCambiosAsync(string? cursor, CancellationToken ct = default)
            => Task.FromResult(new PaqueteRemoto(CambiosBajada, CursorBajada));
    }
}
