using System.Collections.Concurrent;
using PagoYa.Core.Enums;

namespace PagoYa.Invoicing.Sunat;

/// <summary>
/// Provee el siguiente correlativo para una (tipo, serie). Los correlativos SUNAT
/// deben ser CONSECUTIVOS y sin huecos por serie; la implementación de producción
/// debe persistirlos de forma atómica (p. ej. una tabla/secuencia en SQLite del
/// cliente). Se abstrae aquí para no acoplar el motor a la capa de datos.
/// </summary>
public interface IContadorComprobantes
{
    /// <summary>Reserva y devuelve el siguiente correlativo para la serie dada.</summary>
    int SiguienteCorrelativo(TipoComprobante tipo, string serie);
}

/// <summary>
/// Contador en memoria (no persistente). Útil para pruebas y para el modo
/// Simulado. NO usar en producción: al reiniciar reinicia los correlativos.
/// </summary>
public sealed class ContadorEnMemoria : IContadorComprobantes
{
    private readonly ConcurrentDictionary<string, int> _contadores = new();

    public ContadorEnMemoria(int inicio = 0) => Inicio = inicio;

    /// <summary>Último correlativo previo (se devuelve inicio+1 en la primera llamada).</summary>
    public int Inicio { get; }

    public int SiguienteCorrelativo(TipoComprobante tipo, string serie)
        => _contadores.AddOrUpdate($"{(int)tipo}-{serie}", Inicio + 1, (_, prev) => prev + 1);
}
