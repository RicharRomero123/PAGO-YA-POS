using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.Servicios;

/// <summary>
/// Metadatos de un rubro para la pantalla de selección (onboarding).
/// <paramref name="Icono"/> es el emoji de respaldo; <paramref name="IconoImagen"/>
/// es la URI pack del PNG (vacía si el rubro no tiene icono propio y usa el emoji).
/// </summary>
public sealed record RubroInfo(string Clave, string Nombre, string Icono, string Descripcion, string IconoImagen = "");

/// <summary>
/// Producto de plantilla precargada (código, nombre, categoría, precio, stock).
/// Los campos farmacéuticos son opcionales: solo la plantilla de farmacia los usa
/// (principio activo/DCI, registro sanitario DIGEMID, si requiere receta, stock
/// mínimo de reposición y meses hasta el vencimiento del lote sembrado).
/// </summary>
public sealed record ProductoPlantilla(
    string Codigo, string Nombre, string Categoria, decimal Precio, decimal Stock,
    string? PrincipioActivo = null, string? RegistroSanitario = null,
    bool RequiereReceta = false, decimal StockMinimo = 0m, int MesesVence = 0,
    PersonalizacionProducto? Personalizacion = null);

/// <summary>
/// Plantillas de negocio por rubro (mercado peruano). Al crear la cuenta, el
/// usuario elige su rubro y se precargan categorías + productos de ejemplo para
/// que el POS quede usable de inmediato y adaptado a su nicho.
/// </summary>
public static class PlantillasRubro
{
    public static IReadOnlyList<RubroInfo> Todos { get; } = new[]
    {
        new RubroInfo("bodega", "Bodega / Minimarket", "\U0001F6D2", "Abarrotes, bebidas, snacks y golosinas.", IconosPos.RubroBodega),
        new RubroInfo("restaurante", "Restaurante / Menú", "\U0001F37D", "Entradas, platos de fondo, bebidas y postres.", IconosPos.RubroRestaurante),
        new RubroInfo("cafeteria", "Cafetería / Juguería", "☕", "Cafés, jugos, sándwiches y postres."),
        new RubroInfo("polleria", "Pollería / Parrilla", "\U0001F357", "Pollos a la brasa, parrillas y guarniciones."),
        new RubroInfo("farmacia", "Farmacia / Botica", "\U0001F48A", "Medicamentos, cuidado personal e higiene.", IconosPos.RubroFarmacia),
        new RubroInfo("ferreteria", "Ferretería", "\U0001F528", "Herramientas, gasfitería, electricidad.", IconosPos.RubroFerreteria),
        new RubroInfo("licoreria", "Licorería", "\U0001F37B", "Cervezas, licores, vinos y gaseosas."),
        new RubroInfo("hotel", "Hotel / Hospedaje", "\U0001F3E8", "Habitaciones, consumos y servicios.", IconosPos.RubroHotel),
        new RubroInfo("otro", "Otro giro", "\U0001F3EA", "Empieza con el catálogo vacío y agrégalo tú."),
    };

    public static RubroInfo Info(string clave) =>
        Todos.FirstOrDefault(r => r.Clave == clave) ?? Todos[0];

    /// <summary>
    /// Rubros de "comida" que atienden en salón: habilitan la personalización de
    /// productos (modificadores) y el módulo de Mesas + comandas a cocina.
    /// </summary>
    public static bool EsRubroComida(string? clave) =>
        (clave ?? "").ToLowerInvariant() is "restaurante" or "polleria" or "cafeteria";

    /// <summary>
    /// Categorías sugeridas para el rubro (para autocompletar el campo Categoría del
    /// producto). Se derivan de las categorías de la plantilla, en orden de aparición,
    /// más algunas genéricas útiles para que el negocio no empiece de cero.
    /// </summary>
    public static IReadOnlyList<string> Categorias(string? clave)
    {
        var cats = new List<string>();
        void Add(string c) { if (!string.IsNullOrWhiteSpace(c) && !cats.Contains(c)) cats.Add(c); }

        foreach (var p in Productos(clave ?? "bodega")) Add(p.Categoria);

        // Refuerzos por rubro (categorías comunes que la plantilla podría no cubrir).
        switch ((clave ?? "").ToLowerInvariant())
        {
            case "bodega":
                Add("Bebidas"); Add("Abarrotes"); Add("Snacks"); Add("Golosinas");
                Add("Limpieza"); Add("Panadería"); Add("Lácteos"); Add("Cigarros"); break;
            case "restaurante":
                Add("Entradas"); Add("Platos de fondo"); Add("Bebidas"); Add("Postres"); Add("Menú"); break;
            case "cafeteria":
                Add("Cafés"); Add("Jugos"); Add("Sándwiches"); Add("Postres"); Add("Bebidas"); break;
            case "polleria":
                Add("Pollos"); Add("Parrillas"); Add("Guarniciones"); Add("Bebidas"); break;
            case "farmacia":
                Add("Analgésicos"); Add("Antibióticos"); Add("Antigripales"); Add("Gastrointestinal");
                Add("Vitaminas"); Add("Primeros auxilios"); Add("Higiene"); Add("Cuidado personal");
                Add("Bebé"); Add("Genéricos"); Add("Medicamentos"); break;
            case "ferreteria":
                Add("Herramientas manuales"); Add("Herramientas eléctricas"); Add("Electricidad");
                Add("Iluminación"); Add("Gasfitería / Plomería"); Add("Pinturas y accesorios");
                Add("Fijación (clavos y tornillos)"); Add("Adhesivos y pegamentos"); Add("Cerrajería y candados");
                Add("Seguridad y protección"); Add("Construcción"); Add("Abrasivos y discos");
                Add("Jardinería"); Add("Automotriz"); Add("Limpieza"); Add("Menaje / hogar"); break;
            case "licoreria":
                Add("Cervezas"); Add("Licores"); Add("Vinos"); Add("Gaseosas"); Add("Piqueos"); break;
            case "hotel":
                Add("Habitaciones"); Add("Minibar"); Add("Restaurante"); Add("Servicios"); Add("Lavandería"); break;
        }

        Add("General");
        return cats;
    }

    /// <summary>Pie de ticket sugerido por rubro.</summary>
    public static string PieTicket(string clave) => clave switch
    {
        "restaurante" or "polleria" or "cafeteria" => "¡Gracias por su preferencia! Vuelva pronto.",
        "hotel" => "Gracias por hospedarse con nosotros.",
        "farmacia" => "Cuidamos tu salud. ¡Gracias!",
        _ => "¡Gracias por su compra!"
    };

    // ------------------------------------------------------------------
    // Helpers para armar la personalización de ejemplo (rubro restaurante).
    // ------------------------------------------------------------------

    private static OpcionModificador Op(string nombre, decimal extra = 0m) => new() { Nombre = nombre, PrecioExtra = extra };

    /// <summary>Grupo "elige uno" (presentación/tamaño): la primera suele ser +0.</summary>
    private static GrupoModificador Tamano(string nombre, params OpcionModificador[] opciones)
        => new() { Nombre = nombre, Multiple = false, Obligatorio = true, Opciones = opciones.ToList() };

    /// <summary>Grupo "elige varios" con precio (agregados/extras).</summary>
    private static GrupoModificador Extras(string nombre, params OpcionModificador[] opciones)
        => new() { Nombre = nombre, Multiple = true, Obligatorio = false, Opciones = opciones.ToList() };

    /// <summary>Grupo "elige varios" sin costo (quitar ingredientes / notas de cocina).</summary>
    private static GrupoModificador Notas(string nombre, params string[] opciones)
        => new() { Nombre = nombre, Multiple = true, Obligatorio = false, Opciones = opciones.Select(o => Op(o)).ToList() };

    private static PersonalizacionProducto Pers(params GrupoModificador[] grupos)
        => new() { PermiteNota = true, Grupos = grupos.ToList() };

    /// <summary>Productos de ejemplo del rubro (vacío para "otro").</summary>
    public static IReadOnlyList<ProductoPlantilla> Productos(string clave) => clave switch
    {
        "restaurante" => new[]
        {
            new ProductoPlantilla("PLT-001", "Ceviche de pescado", "Entradas", 22.00m, 0,
                Personalizacion: Pers(
                    Tamano("Presentación", Op("Personal"), Op("Fuente para 2", 18m)),
                    Extras("Agregados", Op("+ Chicharrón de pescado", 8m), Op("+ Porción de camote", 3m), Op("+ Choclo", 2m)),
                    Notas("Preparación", "Sin cebolla", "Más picante", "Sin ají"))),
            new ProductoPlantilla("PLT-002", "Papa a la huancaína", "Entradas", 12.00m, 0),
            new ProductoPlantilla("PLT-003", "Lomo saltado", "Platos de fondo", 28.00m, 0,
                Personalizacion: Pers(
                    Tamano("Tamaño", Op("Normal"), Op("Grande", 6m)),
                    Extras("Agregados", Op("+ Huevo frito", 2m), Op("+ Porción de papas", 5m), Op("+ Porción de arroz", 4m)),
                    Notas("Preparación", "Sin cebolla", "Término bien cocido", "Para llevar"))),
            new ProductoPlantilla("PLT-004", "Ají de gallina", "Platos de fondo", 24.00m, 0,
                Personalizacion: Pers(
                    Extras("Agregados", Op("+ Presa de pollo", 6m), Op("+ Porción de arroz", 4m)),
                    Notas("Preparación", "Sin ají", "Poca crema", "Para llevar"))),
            new ProductoPlantilla("PLT-005", "Arroz con pollo", "Platos de fondo", 20.00m, 0,
                Personalizacion: Pers(
                    Tamano("Tamaño", Op("Personal"), Op("Familiar", 14m)),
                    Notas("Preparación", "Sin culantro", "Para llevar"))),
            new ProductoPlantilla("PLT-006", "Menú del día", "Platos de fondo", 15.00m, 0,
                Personalizacion: Pers(
                    Notas("Preparación", "Sin ensalada", "Para llevar"))),
            new ProductoPlantilla("PLT-007", "Chicha morada", "Bebidas", 4.00m, 0,
                Personalizacion: Pers(Tamano("Presentación", Op("Vaso"), Op("Jarra 1L", 8m)))),
            new ProductoPlantilla("PLT-008", "Inca Kola", "Bebidas", 4.00m, 40,
                Personalizacion: Pers(Tamano("Presentación", Op("500ml"), Op("1L", 2.50m), Op("1.5L", 4m)))),
            new ProductoPlantilla("PLT-009", "Cerveza Pilsen", "Bebidas", 9.00m, 24),
            new ProductoPlantilla("PLT-010", "Mazamorra morada", "Postres", 6.00m, 0),
            new ProductoPlantilla("PLT-011", "Arroz con leche", "Postres", 6.00m, 0),
        },
        "cafeteria" => new[]
        {
            new ProductoPlantilla("CAF-001", "Café pasado", "Cafés", 5.00m, 0),
            new ProductoPlantilla("CAF-002", "Capuchino", "Cafés", 8.00m, 0),
            new ProductoPlantilla("CAF-003", "Café americano", "Cafés", 6.00m, 0),
            new ProductoPlantilla("CAF-004", "Jugo de naranja", "Jugos", 7.00m, 0),
            new ProductoPlantilla("CAF-005", "Jugo surtido", "Jugos", 8.00m, 0),
            new ProductoPlantilla("CAF-006", "Sándwich de pollo", "Sándwiches", 10.00m, 0),
            new ProductoPlantilla("CAF-007", "Sándwich mixto", "Sándwiches", 9.00m, 0),
            new ProductoPlantilla("CAF-008", "Torta de chocolate", "Postres", 9.00m, 0),
            new ProductoPlantilla("CAF-009", "Empanada", "Postres", 4.50m, 0),
            new ProductoPlantilla("CAF-010", "Agua San Luis 625ml", "Bebidas", 2.00m, 30),
        },
        "polleria" => new[]
        {
            new ProductoPlantilla("POL-001", "Pollo a la brasa entero", "Pollos", 55.00m, 0),
            new ProductoPlantilla("POL-002", "1/2 Pollo a la brasa", "Pollos", 30.00m, 0),
            new ProductoPlantilla("POL-003", "1/4 Pollo a la brasa", "Pollos", 18.00m, 0),
            new ProductoPlantilla("POL-004", "Parrilla personal", "Parrillas", 32.00m, 0),
            new ProductoPlantilla("POL-005", "Anticuchos (2 palos)", "Parrillas", 15.00m, 0),
            new ProductoPlantilla("POL-006", "Porción de papas fritas", "Guarniciones", 8.00m, 0),
            new ProductoPlantilla("POL-007", "Ensalada", "Guarniciones", 6.00m, 0),
            new ProductoPlantilla("POL-008", "Chicha morada (jarra)", "Bebidas", 12.00m, 0),
            new ProductoPlantilla("POL-009", "Inca Kola 1.5L", "Bebidas", 8.00m, 24),
            new ProductoPlantilla("POL-010", "Cerveza Cusqueña", "Bebidas", 10.00m, 24),
        },
        // Farmacia / botica (Perú). Se siembran principio activo (DCI), registro
        // sanitario DIGEMID, si requiere receta, stock mínimo y meses al vencimiento
        // (algunos "por vencer" para que el módulo de Vencimientos se vea poblado).
        "farmacia" => new[]
        {
            new ProductoPlantilla("FAR-001", "Paracetamol 500mg (blíster x10)", "Analgésicos", 3.50m, 60,
                PrincipioActivo: "Paracetamol", RegistroSanitario: "EN-01234", StockMinimo: 20m, MesesVence: 18),
            new ProductoPlantilla("FAR-002", "Ibuprofeno 400mg (blíster x10)", "Analgésicos", 5.00m, 50,
                PrincipioActivo: "Ibuprofeno", RegistroSanitario: "EN-02345", StockMinimo: 15m, MesesVence: 12),
            new ProductoPlantilla("FAR-003", "Naproxeno 550mg (blíster x10)", "Analgésicos", 7.00m, 30,
                PrincipioActivo: "Naproxeno sódico", RegistroSanitario: "EN-03456", StockMinimo: 10m, MesesVence: 2),
            new ProductoPlantilla("FAR-004", "Panadol Antigripal (caja x12)", "Antigripales", 8.00m, 40,
                PrincipioActivo: "Paracetamol + Clorfenamina + Fenilefrina", RegistroSanitario: "EE-04567", StockMinimo: 12m, MesesVence: 10),
            new ProductoPlantilla("FAR-005", "Amoxicilina 500mg (caja x100)", "Antibióticos", 25.00m, 20,
                PrincipioActivo: "Amoxicilina", RegistroSanitario: "EG-05678", RequiereReceta: true, StockMinimo: 8m, MesesVence: 8),
            new ProductoPlantilla("FAR-006", "Azitromicina 500mg (blíster x3)", "Antibióticos", 15.00m, 15,
                PrincipioActivo: "Azitromicina", RegistroSanitario: "EG-06789", RequiereReceta: true, StockMinimo: 6m, MesesVence: 1),
            new ProductoPlantilla("FAR-007", "Omeprazol 20mg (blíster x14)", "Gastrointestinal", 6.00m, 35,
                PrincipioActivo: "Omeprazol", RegistroSanitario: "EN-07890", StockMinimo: 12m, MesesVence: 14),
            new ProductoPlantilla("FAR-008", "Sales de rehidratación oral", "Gastrointestinal", 2.50m, 50,
                PrincipioActivo: "Electrolitos orales", RegistroSanitario: "EN-08901", StockMinimo: 15m, MesesVence: 20),
            new ProductoPlantilla("FAR-009", "Vitamina C 1g (tubo efervescente)", "Vitaminas", 18.00m, 25,
                PrincipioActivo: "Ácido ascórbico", RegistroSanitario: "EE-09012", StockMinimo: 8m, MesesVence: 9),
            new ProductoPlantilla("FAR-010", "Complejo B (blíster x10)", "Vitaminas", 9.00m, 25,
                PrincipioActivo: "Vitaminas B1 B6 B12", RegistroSanitario: "EE-09123", StockMinimo: 8m, MesesVence: 15),
            new ProductoPlantilla("FAR-011", "Alcohol 96° 250ml", "Primeros auxilios", 6.00m, 30,
                StockMinimo: 10m, MesesVence: 24),
            new ProductoPlantilla("FAR-012", "Alcohol en gel 250ml", "Primeros auxilios", 9.00m, 30,
                StockMinimo: 10m, MesesVence: 24),
            new ProductoPlantilla("FAR-013", "Agua oxigenada 120ml", "Primeros auxilios", 4.00m, 25,
                StockMinimo: 8m, MesesVence: 16),
            new ProductoPlantilla("FAR-014", "Curitas (caja x100)", "Primeros auxilios", 5.00m, 20, StockMinimo: 6m),
            new ProductoPlantilla("FAR-015", "Mascarilla quirúrgica (unidad)", "Higiene", 0.50m, 200, StockMinimo: 50m),
            new ProductoPlantilla("FAR-016", "Jabón antibacterial", "Higiene", 4.50m, 40, StockMinimo: 12m),
            new ProductoPlantilla("FAR-017", "Shampoo 400ml", "Cuidado personal", 15.00m, 20, StockMinimo: 6m),
            new ProductoPlantilla("FAR-018", "Pañales talla M (paquete)", "Bebé", 35.00m, 15, StockMinimo: 5m),
            new ProductoPlantilla("FAR-019", "Termómetro digital", "Primeros auxilios", 22.00m, 10, StockMinimo: 3m),
            new ProductoPlantilla("FAR-020", "Preservativos (caja x3)", "Cuidado personal", 6.00m, 30, StockMinimo: 10m),
        },
        // Ferretería (Perú). Categorías alineadas con las sugeridas del rubro; se
        // siembra stock mínimo para que las alertas de reposición tengan sentido.
        "ferreteria" => new[]
        {
            new ProductoPlantilla("FER-001", "Martillo carpintero 25oz", "Herramientas manuales", 25.00m, 15, StockMinimo: 3m),
            new ProductoPlantilla("FER-002", "Desarmador estrella", "Herramientas manuales", 8.00m, 30, StockMinimo: 6m),
            new ProductoPlantilla("FER-003", "Alicate universal 8\"", "Herramientas manuales", 18.00m, 20, StockMinimo: 4m),
            new ProductoPlantilla("FER-004", "Cinta métrica 5m", "Herramientas manuales", 12.00m, 20, StockMinimo: 5m),
            new ProductoPlantilla("FER-005", "Taladro percutor 650W", "Herramientas eléctricas", 150.00m, 8, StockMinimo: 2m),
            new ProductoPlantilla("FER-006", "Disco de corte 4-1/2\"", "Abrasivos y discos", 3.50m, 60, StockMinimo: 15m),
            new ProductoPlantilla("FER-007", "Foco LED 9W", "Iluminación", 7.00m, 50, StockMinimo: 12m),
            new ProductoPlantilla("FER-008", "Interruptor simple", "Electricidad", 5.00m, 40, StockMinimo: 10m),
            new ProductoPlantilla("FER-009", "Cable mellizo 14 AWG (metro)", "Electricidad", 2.50m, 200, StockMinimo: 50m),
            new ProductoPlantilla("FER-010", "Tomacorriente doble", "Electricidad", 6.50m, 40, StockMinimo: 10m),
            new ProductoPlantilla("FER-011", "Caño PVC 1/2\" (3m)", "Gasfitería / Plomería", 6.00m, 40, StockMinimo: 8m),
            new ProductoPlantilla("FER-012", "Cinta teflón", "Gasfitería / Plomería", 1.50m, 100, StockMinimo: 20m),
            new ProductoPlantilla("FER-013", "Pintura látex blanco 1gal", "Pinturas y accesorios", 45.00m, 12, StockMinimo: 3m),
            new ProductoPlantilla("FER-014", "Brocha 3\"", "Pinturas y accesorios", 6.00m, 30, StockMinimo: 6m),
            new ProductoPlantilla("FER-015", "Silicona transparente", "Adhesivos y pegamentos", 10.00m, 25, StockMinimo: 5m),
            new ProductoPlantilla("FER-016", "Pegamento para PVC 1/4", "Adhesivos y pegamentos", 12.00m, 20, StockMinimo: 4m),
            new ProductoPlantilla("FER-017", "Clavos 2\" (kg)", "Fijación (clavos y tornillos)", 8.00m, 30, StockMinimo: 6m),
            new ProductoPlantilla("FER-018", "Tornillo autorroscante (caja x100)", "Fijación (clavos y tornillos)", 9.00m, 25, StockMinimo: 5m),
            new ProductoPlantilla("FER-019", "Candado 40mm", "Cerrajería y candados", 15.00m, 20, StockMinimo: 4m),
            new ProductoPlantilla("FER-020", "Guantes de seguridad", "Seguridad y protección", 5.00m, 40, StockMinimo: 10m),
            new ProductoPlantilla("FER-021", "Cemento Sol 42.5kg", "Construcción", 32.00m, 30, StockMinimo: 8m),
        },
        "licoreria" => new[]
        {
            new ProductoPlantilla("LIC-001", "Cerveza Pilsen 630ml", "Cervezas", 7.50m, 48),
            new ProductoPlantilla("LIC-002", "Cerveza Cristal 630ml", "Cervezas", 7.50m, 48),
            new ProductoPlantilla("LIC-003", "Cerveza Cusqueña 620ml", "Cervezas", 8.50m, 36),
            new ProductoPlantilla("LIC-004", "Pisco Quebranta 750ml", "Licores", 45.00m, 12),
            new ProductoPlantilla("LIC-005", "Ron Cartavio 750ml", "Licores", 38.00m, 12),
            new ProductoPlantilla("LIC-006", "Vino Tacama tinto", "Vinos", 35.00m, 15),
            new ProductoPlantilla("LIC-007", "Whisky Johnnie Walker", "Licores", 75.00m, 8),
            new ProductoPlantilla("LIC-008", "Inca Kola 1.5L", "Gaseosas", 8.00m, 30),
            new ProductoPlantilla("LIC-009", "Hielo (bolsa)", "Otros", 5.00m, 40),
            new ProductoPlantilla("LIC-010", "Piqueo surtido", "Otros", 6.00m, 30),
        },
        // Hotel: las HABITACIONES NO son productos (se administran aparte y se
        // alquilan desde Cobrar). Aquí solo van los consumibles/servicios que se
        // venden en el POS o se cargan a la habitación (minibar, restaurante, etc.).
        "hotel" => new[]
        {
            new ProductoPlantilla("HAB-005", "Desayuno buffet", "Restaurante", 25.00m, 0),
            new ProductoPlantilla("HAB-006", "Agua mineral", "Minibar", 4.00m, 50),
            new ProductoPlantilla("HAB-007", "Gaseosa lata", "Minibar", 5.00m, 50),
            new ProductoPlantilla("HAB-008", "Cerveza", "Minibar", 10.00m, 40),
            new ProductoPlantilla("HAB-009", "Snack / piqueo", "Minibar", 6.00m, 40),
            new ProductoPlantilla("HAB-010", "Lavandería (prenda)", "Servicios", 8.00m, 0),
        },
        "otro" => Array.Empty<ProductoPlantilla>(),
        _ => new[] // bodega (por defecto)
        {
            new ProductoPlantilla("7501055", "Inca Kola 500ml", "Bebidas", 3.50m, 48),
            new ProductoPlantilla("7501056", "Coca Cola 500ml", "Bebidas", 3.50m, 40),
            new ProductoPlantilla("7501099", "Cerveza Pilsen 630ml", "Bebidas", 7.50m, 24),
            new ProductoPlantilla("7502001", "Arroz Costeño 1kg", "Abarrotes", 5.80m, 30),
            new ProductoPlantilla("7502002", "Aceite Primor 1L", "Abarrotes", 9.90m, 18),
            new ProductoPlantilla("7502003", "Leche Gloria tarro", "Abarrotes", 4.20m, 36),
            new ProductoPlantilla("7503010", "Papas Lay's", "Snacks", 3.80m, 22),
            new ProductoPlantilla("7503011", "Galleta Soda Field", "Snacks", 1.50m, 60),
            new ProductoPlantilla("7503012", "Chocolate Sublime", "Golosinas", 2.00m, 50),
            new ProductoPlantilla("7504020", "Detergente Bolívar 780g", "Limpieza", 8.50m, 14),
            new ProductoPlantilla("7506001", "Pan francés (und)", "Panadería", 0.30m, 200),
        }
    };
}
