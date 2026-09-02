using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// SEED DE DEMO. Si la BD está vacía en el primer arranque, inserta unos pocos
/// productos de ejemplo y abre una caja para que la demo se vea poblada y sea
/// "vendible" de inmediato.
///
/// Marcado claramente como demo: en producción real el seed no debe ejecutarse
/// (o debe ser opt-in). Aquí solo corre cuando no hay ningún producto activo.
/// </summary>
public static class SeedDemo
{
    /// <summary>
    /// Siembra la plantilla del rubro elegido si el catálogo está vacío. Si el
    /// rubro es "otro" no siembra productos (catálogo en blanco). Abre una caja
    /// inicial para poder vender de inmediato.
    /// </summary>
    public static async Task EjecutarSiVacioAsync(
        IProductoRepository productos,
        ICajaRepository cajas,
        string rubro = "bodega",
        IHotelRepository? hotel = null,
        IMesaRepository? mesas = null,
        CancellationToken ct = default)
    {
        var existentes = await productos.BuscarAsync(null, ct);
        if (existentes.Count == 0)
        {
            foreach (var p in PlantillasRubro.Productos(rubro))
            {
                await productos.GuardarAsync(new Producto
                {
                    Codigo = p.Codigo,
                    Nombre = p.Nombre,
                    Descripcion = p.Categoria,   // categoría reutiliza 'descripcion'
                    PrecioVenta = p.Precio,
                    PrecioIncluyeIgv = true,
                    UnidadMedida = "NIU",
                    StockActual = p.Stock,
                    ControlaStock = p.Stock > 0, // servicios (stock 0) no controlan stock
                    Activo = true,
                    StockMinimo = p.StockMinimo,
                    // Campos farmacéuticos (null/false en rubros no farmacia).
                    PrincipioActivo = p.PrincipioActivo,
                    RegistroSanitario = p.RegistroSanitario,
                    RequiereReceta = p.RequiereReceta,
                    // Vence dentro de N meses desde hoy (0 = sin vencimiento sembrado).
                    FechaVencimiento = p.MesesVence > 0 ? DateTime.Today.AddMonths(p.MesesVence) : (DateTime?)null,
                    // Personalización (modificadores) del rubro restaurante; null en el resto.
                    PersonalizacionJson = PersonalizacionSerializer.Serializar(p.Personalizacion)
                }, ct);
            }
        }

        // --- Habitaciones de ejemplo para el rubro hotel/hostal ---
        if (hotel is not null && string.Equals(rubro, "hotel", StringComparison.OrdinalIgnoreCase))
        {
            var habs = await hotel.ListarHabitacionesAsync(true, ct);
            if (habs.Count == 0)
            {
                // 2 pisos, mezcla de tipos, con tarifa por noche y por hora (hostal del paso).
                var plantilla = new (string Num, int Piso, TipoHabitacion Tipo, decimal Noche, decimal Hora, int Cap)[]
                {
                    ("101", 1, TipoHabitacion.Simple,      60m, 20m, 1),
                    ("102", 1, TipoHabitacion.Matrimonial, 80m, 25m, 2),
                    ("103", 1, TipoHabitacion.Matrimonial, 80m, 25m, 2),
                    ("104", 1, TipoHabitacion.Doble,       90m, 30m, 2),
                    ("201", 2, TipoHabitacion.Doble,       90m, 30m, 2),
                    ("202", 2, TipoHabitacion.Triple,     120m, 35m, 3),
                    ("203", 2, TipoHabitacion.Familiar,   140m, 40m, 4),
                    ("301", 3, TipoHabitacion.Suite,      200m,  0m, 2),
                };
                foreach (var h in plantilla)
                {
                    await hotel.GuardarHabitacionAsync(new Habitacion
                    {
                        Numero = h.Num, Piso = h.Piso, Tipo = h.Tipo,
                        PrecioNoche = h.Noche, PrecioHora = h.Hora, Capacidad = h.Cap,
                        Estado = EstadoHabitacion.Disponible, Activa = true
                    }, ct);
                }
            }
        }

        // --- Mesas de ejemplo para el rubro de comida (restaurante/pollería/cafetería) ---
        if (mesas is not null && PlantillasRubro.EsRubroComida(rubro))
        {
            var existentesMesas = await mesas.ListarMesasAsync(true, ct);
            if (existentesMesas.Count == 0)
            {
                // 2 zonas: Salón (1–6) y Terraza (T1–T2); capacidades 2/4/6.
                var plantilla = new (string Num, string Zona, int Cap)[]
                {
                    ("1", "Salón", 4), ("2", "Salón", 2), ("3", "Salón", 4),
                    ("4", "Salón", 6), ("5", "Salón", 4), ("6", "Salón", 2),
                    ("T1", "Terraza", 4), ("T2", "Terraza", 6),
                };
                foreach (var m in plantilla)
                    await mesas.GuardarMesaAsync(new Mesa
                    {
                        Numero = m.Num, Zona = m.Zona, Capacidad = m.Cap,
                        Estado = EstadoMesa.Libre, Activa = true
                    }, ct);
            }
        }

        // --- Abrir una caja inicial si no hay ninguna abierta ---
        var abierta = await cajas.ObtenerCajaAbiertaAsync(ct);
        if (abierta is null)
        {
            await cajas.AbrirCajaAsync(new Caja
            {
                Nombre = "Caja 1",
                Cajero = "Cajero",
                MontoApertura = 100m,
                FechaApertura = DateTime.Now
            }, ct);
        }
    }
}
