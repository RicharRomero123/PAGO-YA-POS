using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PagoYa.Core.Contratos;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// Pantalla "Nube y respaldo" (tier Cloud). Muestra el estado de sincronización,
/// cuántos cambios locales están pendientes de subir y permite ejecutar un
/// respaldo/consolidación bajo demanda contra <see cref="ISyncService"/>.
///
/// Solo es navegable cuando la licencia habilita "cloud_sync"; en modo Base el
/// menú la muestra bloqueada (upsell). Runtime: usa el motor real; diseño: mock.
/// </summary>
public partial class NubeViewModel : ObservableObject
{
    private readonly ISyncService? _sync;
    private readonly IOutboxStore? _outbox;

    [ObservableProperty] private bool _habilitada;
    [ObservableProperty] private int _pendientesLocales;
    [ObservableProperty] private int _enviados;
    [ObservableProperty] private int _recibidos;
    [ObservableProperty] private bool _sincronizando;
    [ObservableProperty] private string _ultimaSync = "Nunca";
    [ObservableProperty] private string _mensajeEstado = "";

    /// <summary>Constructor de DISEÑO.</summary>
    public NubeViewModel()
    {
        Habilitada = true;
        PendientesLocales = 12;
        UltimaSync = "Hoy 12:45 p. m.";
        MensajeEstado = "Respaldo al día.";
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public NubeViewModel(ISyncService sync, IOutboxStore outbox)
    {
        _sync = sync;
        _outbox = outbox;
        Habilitada = sync.SincronizacionHabilitada;
    }

    /// <summary>Refresca el conteo de cambios locales pendientes de subir.</summary>
    [RelayCommand]
    public async Task CargarAsync(CancellationToken ct = default)
    {
        if (_outbox is null) return;
        try
        {
            var pend = await _outbox.LeerPendientesAsync(5000, ct);
            PendientesLocales = pend.Count;
        }
        catch (Exception ex)
        {
            MensajeEstado = $"No se pudo leer la cola local: {ex.Message}";
        }
    }

    /// <summary>Ejecuta un ciclo de sincronización (subir pendientes + bajar cambios).</summary>
    [RelayCommand]
    private async Task SincronizarAhoraAsync(CancellationToken ct = default)
    {
        if (_sync is null || Sincronizando) return;

        Sincronizando = true;
        MensajeEstado = "Respaldando en la nube…";
        try
        {
            var r = await _sync.SincronizarAsync(ct);
            Enviados = r.Enviados;
            Recibidos = r.Recibidos;
            if (r.Exito)
            {
                UltimaSync = DateTime.Now.ToString("dd/MM/yyyy HH:mm");
                MensajeEstado = r.Mensaje ?? "Respaldo completo.";
            }
            else
            {
                MensajeEstado = r.Mensaje ?? "No se pudo sincronizar.";
            }
            await CargarAsync(ct);
        }
        catch (Exception ex)
        {
            MensajeEstado = $"Error al sincronizar: {ex.Message}";
        }
        finally
        {
            Sincronizando = false;
        }
    }
}
