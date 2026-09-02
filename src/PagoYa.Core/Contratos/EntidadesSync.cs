namespace PagoYa.Core.Contratos;

/// <summary>
/// Catálogo <b>cerrado</b> de entidades que viajan por la sincronización, con sus
/// nombres canónicos (snake_case, singular). Los mismos diez, escritos igual, en
/// las tres implementaciones:
///
///   * PC:      <c>src/PagoYa.Data/Repositorios/OutboxStore.cs</c> (este catálogo)
///   * Móvil:   <c>mobile/packages/pagoya_core/lib/datos/</c> (<c>EntidadesSync</c>)
///   * Backend: <c>server/PagoYa.Api/Servicios/ServicioSync.cs</c> (<c>EntidadesSync</c>)
///
/// Ver <c>server/README.md §7.2</c>. Si un nombre no coincide entre las tres
/// partes, el evento viaja pero nadie lo aplica: se pierde en silencio. Por eso
/// son constantes y no literales sueltos.
///
/// <b>Deliberadamente FUERA del catálogo</b> (no se sincronizan, y así se quedan):
///   * <c>proveedor</c> y <c>usuario</c>: datos locales de cada instalación
///     (el usuario incluye hash de contraseña; no tiene por qué salir del equipo).
///   * <c>consumos_habitacion</c>: los consumos viajan ya consolidados en el
///     campo <c>monto_consumos</c> de la estadía.
///
/// Nota: el backend NO descarta un evento de una entidad desconocida (perder
/// datos del cliente sería peor); lo almacena y lo reporta en
/// <c>SyncPushResponse.entidadesDesconocidas</c>. Los clientes sí lo ignoran al
/// aplicar, porque no saben en qué tabla ponerlo.
/// </summary>
public static class EntidadesSync
{
    // --- Las cinco originales del escritorio ---
    public const string Producto = "producto";
    public const string Venta = "venta";
    public const string Caja = "caja";
    public const string MovimientoCaja = "movimiento_caja";
    public const string Inventario = "inventario";

    // --- Comandas (rubro restaurante/cafetería/pollería) ---
    public const string Mesa = "mesa";
    public const string Pedido = "pedido";
    public const string PedidoLinea = "pedido_linea";

    // --- Hotel/hostal ---
    public const string Habitacion = "habitacion";
    public const string EstadiaHabitacion = "estadia_habitacion";

    /// <summary>Las diez, para validaciones y tests de paridad.</summary>
    public static readonly IReadOnlyList<string> Todas = new[]
    {
        Producto, Venta, Caja, MovimientoCaja, Inventario,
        Mesa, Pedido, PedidoLinea, Habitacion, EstadiaHabitacion
    };

    /// <summary>True si <paramref name="entidad"/> está en el catálogo (case-insensitive).</summary>
    public static bool EsConocida(string? entidad) =>
        entidad is not null && Todas.Contains(entidad.Trim().ToLowerInvariant());
}
