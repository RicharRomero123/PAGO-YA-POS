using System;
using System.IO;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PagoYa.Core.Contratos;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// ViewModel de la pantalla de <b>activación</b> (gate de arranque del modelo
/// "Base exige licencia"). Muestra el HWID de la máquina para que el dueño lo
/// envíe (WhatsApp) y reciba su token, y valida/activa el token pegado. La app
/// no entra al POS hasta que <see cref="ILicenseService.EstadoActual"/> quede
/// <c>EstaActivada = true</c> (cualquier tier, incluido Base).
/// </summary>
public partial class ActivacionViewModel : ObservableObject
{
    private readonly ILicenseService? _licencia;

    /// <summary>Huella de hardware de esta máquina (a enviar para emitir la licencia).</summary>
    [ObservableProperty] private string _hwid = "";

    /// <summary>Token de licencia firmado que el dueño pega para activar.</summary>
    [ObservableProperty] private string _tokenLicencia = "";

    /// <summary>Mensaje de error (activación fallida). Rojo en la UI.</summary>
    [ObservableProperty] private string _mensajeError = "";

    /// <summary>Mensaje neutro (ej. "HWID copiado").</summary>
    [ObservableProperty] private string _mensajeEstado = "";

    /// <summary>La fija la ventana: se invoca cuando la activación fue exitosa.</summary>
    public Action? ActivacionExitosa { get; set; }

    /// <summary>Constructor de DISEÑO.</summary>
    public ActivacionViewModel()
    {
        Hwid = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";
    }

    /// <summary>Constructor de PRODUCCIÓN (DI).</summary>
    public ActivacionViewModel(ILicenseService licencia, IHardwareId hardwareId)
    {
        _licencia = licencia;
        try { Hwid = hardwareId.ObtenerHwid(); }
        catch { Hwid = "(no disponible)"; }
    }

    /// <summary>Copia el HWID al portapapeles para enviarlo por WhatsApp.</summary>
    [RelayCommand]
    private void CopiarHwid()
    {
        try
        {
            Clipboard.SetText(Hwid);
            MensajeError = "";
            MensajeEstado = "Código copiado. Envíalo por WhatsApp para recibir tu licencia.";
        }
        catch
        {
            MensajeEstado = "";
            MensajeError = "No se pudo copiar el código.";
        }
    }

    /// <summary>
    /// Guarda el HWID en un archivo de texto (para copiarlo a una USB y enviarlo
    /// desde otro equipo). Pensado para cajas SIN internet.
    /// </summary>
    [RelayCommand]
    private void GuardarHwidArchivo()
    {
        var dlg = new SaveFileDialog
        {
            Title = "Guardar mi código de equipo (HWID)",
            Filter = "Texto (*.txt)|*.txt",
            FileName = "mi-hwid-pagoya.txt"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            File.WriteAllText(dlg.FileName, Hwid);
            MensajeError = "";
            MensajeEstado = "Código guardado. Cópialo a una USB y envíamelo para generar tu licencia.";
        }
        catch (Exception ex)
        {
            MensajeEstado = "";
            MensajeError = $"No se pudo guardar el archivo: {ex.Message}";
        }
    }

    /// <summary>
    /// Importa el token desde un archivo (.lic/.txt) que llegó por USB y lo activa.
    /// Evita tener que escribir a mano el token largo en equipos sin internet.
    /// </summary>
    [RelayCommand]
    private void ImportarLicenciaArchivo()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Importar licencia desde archivo",
            Filter = "Licencia PagoYa (*.lic;*.txt)|*.lic;*.txt|Todos los archivos (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var contenido = File.ReadAllText(dlg.FileName).Trim();
            if (string.IsNullOrWhiteSpace(contenido))
            {
                MensajeEstado = "";
                MensajeError = "El archivo está vacío.";
                return;
            }
            TokenLicencia = contenido;
            Activar(); // valida y activa igual que el token pegado
        }
        catch (Exception ex)
        {
            MensajeEstado = "";
            MensajeError = $"No se pudo leer el archivo: {ex.Message}";
        }
    }

    /// <summary>Valida y activa el token pegado; si es auténtico, deja entrar al POS.</summary>
    [RelayCommand]
    private void Activar()
    {
        if (_licencia is null) return;

        var token = TokenLicencia?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(token))
        {
            MensajeEstado = "";
            MensajeError = "Pega el token de licencia que recibiste.";
            return;
        }

        var estado = _licencia.ActivarLicencia(token);
        if (estado.EstaActivada)
        {
            MensajeError = "";
            ActivacionExitosa?.Invoke();
        }
        else
        {
            MensajeEstado = "";
            MensajeError = $"No se pudo activar: {estado.Motivo}";
        }
    }
}
