// PagoYa Móvil — rubros/plantillas_rubro.dart
//
// PORT COMPLETO de `src/PagoYa.Desktop/Servicios/PlantillasRubro.cs`.
//
// Mismas claves de rubro, mismas categorías, mismos productos de ejemplo,
// mismo pie de ticket, misma regla `EsRubroComida`. Los códigos de producto
// (`PLT-001`, `FAR-014`, `7501055`…) también son idénticos: si el usuario tiene
// PagoYa en la PC y en el celular, el mismo producto sembrado debe tener el
// mismo código de barras en ambos, o al sincronizar el índice único
// `ix_productos_codigo` rechazará la fila y la nube quedará a medias.
//
// Este archivo es Dart PURO: no conoce widgets. Los iconos se exponen como
// RUTAS de asset (`assets/iconos/ico-tienda.png`), con los mismos nombres de
// archivo que `IconosPos` del escritorio, porque `mobile-ux` copia los mismos
// PNG (docs/MOBILE-ARQUITECTURA.md §1). Quien los pinta es la UI.

library;

import '../dominio/dinero.dart';
import '../dominio/personalizacion.dart';

/// Metadatos de un rubro para la pantalla de onboarding.
///
/// [icono] es el emoji de respaldo; [iconoImagen] es la ruta del PNG (vacía si
/// el rubro no tiene icono propio y usa el emoji), igual que en el escritorio.
final class RubroInfo {
  final String clave;
  final String nombre;
  final String icono;
  final String descripcion;
  final String iconoImagen;

  const RubroInfo(
    this.clave,
    this.nombre,
    this.icono,
    this.descripcion, [
    this.iconoImagen = '',
  ]);

  bool get tieneImagen => iconoImagen.isNotEmpty;
}

/// Producto de plantilla precargada.
///
/// Los campos farmacéuticos son opcionales: solo la plantilla de farmacia los
/// usa (DCI, registro sanitario DIGEMID, si requiere receta, stock mínimo y
/// meses hasta el vencimiento del lote sembrado).
final class ProductoPlantilla {
  final String codigo;
  final String nombre;
  final String categoria;
  final Dinero precio;
  final double stock;
  final String? principioActivo;
  final String? registroSanitario;
  final bool requiereReceta;
  final double stockMinimo;

  /// Meses desde hoy hasta el vencimiento del lote sembrado. 0 = sin fecha.
  final int mesesVence;

  final PersonalizacionProducto? personalizacion;

  const ProductoPlantilla(
    this.codigo,
    this.nombre,
    this.categoria,
    this.precio,
    this.stock, {
    this.principioActivo,
    this.registroSanitario,
    this.requiereReceta = false,
    this.stockMinimo = 0,
    this.mesesVence = 0,
    this.personalizacion,
  });

  /// Fecha de vencimiento a sembrar, o null si el rubro no la usa.
  ///
  /// Espeja `DateTime.Today.AddMonths(MesesVence)` de `SeedDemo`. OJO: hay una
  /// diferencia real entre .NET y Dart que hay que corregir a mano —
  /// `AddMonths` RECORTA el día al último del mes destino (31-ene + 1 mes =
  /// 28-feb), mientras que `DateTime(y, m + n, d)` de Dart DESBORDA (31-ene + 1
  /// mes = 3-mar). Sin este recorte, un lote sembrado el día 31 vencería en un
  /// mes distinto en el celular que en la PC.
  ///
  /// [hoy] se inyecta para que los tests no dependan del calendario.
  DateTime? fechaVencimiento([DateTime? hoy]) {
    if (mesesVence <= 0) return null;
    final h = hoy ?? DateTime.now();

    final totalMeses = h.month - 1 + mesesVence;
    final anio = h.year + totalMeses ~/ 12;
    final mes = totalMeses % 12 + 1;

    // Último día del mes destino: el día 0 del mes siguiente.
    final ultimoDia = DateTime(anio, mes + 1, 0).day;
    final dia = h.day <= ultimoDia ? h.day : ultimoDia;

    return DateTime(anio, mes, dia);
  }
}

/// Ruta de los PNG de rubro. Mismos nombres de archivo que `IconosPos`.
abstract final class IconosRubro {
  static const String _base = 'assets/iconos/';

  static const String bodega = '${_base}ico-tienda.png';
  static const String restaurante = '${_base}ico-restaurante.png';
  static const String farmacia = '${_base}ico-farmacia.png';
  static const String ferreteria = '${_base}ico-ferreteria.png';
  static const String hotel = '${_base}ico-hotel.png';

  /// Icono representativo del rubro. Espeja `IconosPos.DeRubro`.
  static String deRubro(String? clave) => switch ((clave ?? '').toLowerCase()) {
        'restaurante' || 'cafeteria' || 'polleria' => restaurante,
        'farmacia' => farmacia,
        'ferreteria' => ferreteria,
        'hotel' => hotel,
        // bodega, licoreria, otro y desconocidos
        _ => bodega,
      };
}

/// Plantillas de negocio por rubro (mercado peruano).
///
/// Al crear la cuenta el usuario elige su rubro y se precargan categorías +
/// productos de ejemplo, para que el POS quede usable de inmediato.
abstract final class PlantillasRubro {
  // Helpers de personalización (rubro comida). Espejan los privados de C#.
  static OpcionModificador _op(String nombre, [num extra = 0]) =>
      OpcionModificador(nombre: nombre, precioExtra: Dinero.deSoles(extra));

  /// Grupo "elige uno" (presentación/tamaño): la primera opción suele ser +0.
  static GrupoModificador _tamano(String nombre, List<OpcionModificador> ops) =>
      GrupoModificador(
          nombre: nombre, multiple: false, obligatorio: true, opciones: ops);

  /// Grupo "elige varios" con precio (agregados/extras).
  static GrupoModificador _extras(String nombre, List<OpcionModificador> ops) =>
      GrupoModificador(
          nombre: nombre, multiple: true, obligatorio: false, opciones: ops);

  /// Grupo "elige varios" sin costo (quitar ingredientes / notas de cocina).
  static GrupoModificador _notas(String nombre, List<String> ops) =>
      GrupoModificador(
        nombre: nombre,
        multiple: true,
        obligatorio: false,
        opciones: ops.map((o) => _op(o)).toList(),
      );

  static PersonalizacionProducto _pers(List<GrupoModificador> grupos) =>
      PersonalizacionProducto(permiteNota: true, grupos: grupos);

  /// Todos los rubros, en el orden en que se muestran en el onboarding.
  static final List<RubroInfo> todos = <RubroInfo>[
    const RubroInfo('bodega', 'Bodega / Minimarket', '\u{1F6D2}',
        'Abarrotes, bebidas, snacks y golosinas.', IconosRubro.bodega),
    const RubroInfo('restaurante', 'Restaurante / Menú', '\u{1F37D}',
        'Entradas, platos de fondo, bebidas y postres.', IconosRubro.restaurante),
    const RubroInfo('cafeteria', 'Cafetería / Juguería', '☕',
        'Cafés, jugos, sándwiches y postres.'),
    const RubroInfo('polleria', 'Pollería / Parrilla', '\u{1F357}',
        'Pollos a la brasa, parrillas y guarniciones.'),
    const RubroInfo('farmacia', 'Farmacia / Botica', '\u{1F48A}',
        'Medicamentos, cuidado personal e higiene.', IconosRubro.farmacia),
    const RubroInfo('ferreteria', 'Ferretería', '\u{1F528}',
        'Herramientas, gasfitería, electricidad.', IconosRubro.ferreteria),
    const RubroInfo('licoreria', 'Licorería', '\u{1F37B}',
        'Cervezas, licores, vinos y gaseosas.'),
    const RubroInfo('hotel', 'Hotel / Hospedaje', '\u{1F3E8}',
        'Habitaciones, consumos y servicios.', IconosRubro.hotel),
    const RubroInfo('otro', 'Otro giro', '\u{1F3EA}',
        'Empieza con el catálogo vacío y agrégalo tú.'),
  ];

  /// Metadatos del rubro; cae a `bodega` si la clave no existe.
  static RubroInfo info(String clave) => todos.firstWhere(
        (r) => r.clave == clave,
        orElse: () => todos[0],
      );

  /// Rubros de "comida" que atienden en salón: habilitan la personalización de
  /// productos (modificadores) y el módulo de Mesas + comandas a cocina.
  /// Espeja `PlantillasRubro.EsRubroComida`.
  static bool esRubroComida(String? clave) => switch ((clave ?? '').toLowerCase()) {
        'restaurante' || 'polleria' || 'cafeteria' => true,
        _ => false,
      };

  /// True si el rubro habilita el módulo de Habitaciones + estadías.
  static bool esRubroHotel(String? clave) =>
      (clave ?? '').toLowerCase() == 'hotel';

  /// Categorías sugeridas: las de la plantilla en orden de aparición, más los
  /// refuerzos por rubro, más "General" al final. Espeja `Categorias`.
  static List<String> categorias(String? clave) {
    final cats = <String>[];
    void add(String c) {
      if (c.trim().isNotEmpty && !cats.contains(c)) cats.add(c);
    }

    for (final p in productos(clave ?? 'bodega')) {
      add(p.categoria);
    }

    switch ((clave ?? '').toLowerCase()) {
      case 'bodega':
        add('Bebidas');
        add('Abarrotes');
        add('Snacks');
        add('Golosinas');
        add('Limpieza');
        add('Panadería');
        add('Lácteos');
        add('Cigarros');
      case 'restaurante':
        add('Entradas');
        add('Platos de fondo');
        add('Bebidas');
        add('Postres');
        add('Menú');
      case 'cafeteria':
        add('Cafés');
        add('Jugos');
        add('Sándwiches');
        add('Postres');
        add('Bebidas');
      case 'polleria':
        add('Pollos');
        add('Parrillas');
        add('Guarniciones');
        add('Bebidas');
      case 'farmacia':
        add('Analgésicos');
        add('Antibióticos');
        add('Antigripales');
        add('Gastrointestinal');
        add('Vitaminas');
        add('Primeros auxilios');
        add('Higiene');
        add('Cuidado personal');
        add('Bebé');
        add('Genéricos');
        add('Medicamentos');
      case 'ferreteria':
        add('Herramientas manuales');
        add('Herramientas eléctricas');
        add('Electricidad');
        add('Iluminación');
        add('Gasfitería / Plomería');
        add('Pinturas y accesorios');
        add('Fijación (clavos y tornillos)');
        add('Adhesivos y pegamentos');
        add('Cerrajería y candados');
        add('Seguridad y protección');
        add('Construcción');
        add('Abrasivos y discos');
        add('Jardinería');
        add('Automotriz');
        add('Limpieza');
        add('Menaje / hogar');
      case 'licoreria':
        add('Cervezas');
        add('Licores');
        add('Vinos');
        add('Gaseosas');
        add('Piqueos');
      case 'hotel':
        add('Habitaciones');
        add('Minibar');
        add('Restaurante');
        add('Servicios');
        add('Lavandería');
    }

    add('General');
    return cats;
  }

  /// Pie de ticket sugerido por rubro. Espeja `PieTicket`.
  ///
  /// OJO: el `switch` de C# compara la clave TAL CUAL (sin bajar a minúsculas),
  /// así que se replica igual para no cambiar el texto impreso.
  static String pieTicket(String clave) => switch (clave) {
        'restaurante' ||
        'polleria' ||
        'cafeteria' =>
          '¡Gracias por su preferencia! Vuelva pronto.',
        'hotel' => 'Gracias por hospedarse con nosotros.',
        'farmacia' => 'Cuidamos tu salud. ¡Gracias!',
        _ => '¡Gracias por su compra!',
      };

  /// Productos de ejemplo del rubro (lista vacía para "otro").
  static List<ProductoPlantilla> productos(String clave) => switch (clave) {
        'restaurante' => _restaurante,
        'cafeteria' => _cafeteria,
        'polleria' => _polleria,
        'farmacia' => _farmacia,
        'ferreteria' => _ferreteria,
        'licoreria' => _licoreria,
        'hotel' => _hotel,
        'otro' => const <ProductoPlantilla>[],
        _ => _bodega, // bodega por defecto
      };

  // ------------------------------------------------------------ Restaurante ---

  static final List<ProductoPlantilla> _restaurante = <ProductoPlantilla>[
    ProductoPlantilla('PLT-001', 'Ceviche de pescado', 'Entradas',
        Dinero.deSoles(22.00), 0,
        personalizacion: _pers([
          _tamano('Presentación', [_op('Personal'), _op('Fuente para 2', 18)]),
          _extras('Agregados', [
            _op('+ Chicharrón de pescado', 8),
            _op('+ Porción de camote', 3),
            _op('+ Choclo', 2),
          ]),
          _notas('Preparación', ['Sin cebolla', 'Más picante', 'Sin ají']),
        ])),
    ProductoPlantilla(
        'PLT-002', 'Papa a la huancaína', 'Entradas', Dinero.deSoles(12.00), 0),
    ProductoPlantilla('PLT-003', 'Lomo saltado', 'Platos de fondo',
        Dinero.deSoles(28.00), 0,
        personalizacion: _pers([
          _tamano('Tamaño', [_op('Normal'), _op('Grande', 6)]),
          _extras('Agregados', [
            _op('+ Huevo frito', 2),
            _op('+ Porción de papas', 5),
            _op('+ Porción de arroz', 4),
          ]),
          _notas('Preparación',
              ['Sin cebolla', 'Término bien cocido', 'Para llevar']),
        ])),
    ProductoPlantilla('PLT-004', 'Ají de gallina', 'Platos de fondo',
        Dinero.deSoles(24.00), 0,
        personalizacion: _pers([
          _extras('Agregados', [
            _op('+ Presa de pollo', 6),
            _op('+ Porción de arroz', 4),
          ]),
          _notas('Preparación', ['Sin ají', 'Poca crema', 'Para llevar']),
        ])),
    ProductoPlantilla('PLT-005', 'Arroz con pollo', 'Platos de fondo',
        Dinero.deSoles(20.00), 0,
        personalizacion: _pers([
          _tamano('Tamaño', [_op('Personal'), _op('Familiar', 14)]),
          _notas('Preparación', ['Sin culantro', 'Para llevar']),
        ])),
    ProductoPlantilla('PLT-006', 'Menú del día', 'Platos de fondo',
        Dinero.deSoles(15.00), 0,
        personalizacion: _pers([
          _notas('Preparación', ['Sin ensalada', 'Para llevar']),
        ])),
    ProductoPlantilla(
        'PLT-007', 'Chicha morada', 'Bebidas', Dinero.deSoles(4.00), 0,
        personalizacion: _pers([
          _tamano('Presentación', [_op('Vaso'), _op('Jarra 1L', 8)]),
        ])),
    ProductoPlantilla('PLT-008', 'Inca Kola', 'Bebidas', Dinero.deSoles(4.00), 40,
        personalizacion: _pers([
          _tamano('Presentación',
              [_op('500ml'), _op('1L', 2.50), _op('1.5L', 4)]),
        ])),
    ProductoPlantilla(
        'PLT-009', 'Cerveza Pilsen', 'Bebidas', Dinero.deSoles(9.00), 24),
    ProductoPlantilla(
        'PLT-010', 'Mazamorra morada', 'Postres', Dinero.deSoles(6.00), 0),
    ProductoPlantilla(
        'PLT-011', 'Arroz con leche', 'Postres', Dinero.deSoles(6.00), 0),
  ];

  // -------------------------------------------------------------- Cafetería ---

  static final List<ProductoPlantilla> _cafeteria = <ProductoPlantilla>[
    ProductoPlantilla('CAF-001', 'Café pasado', 'Cafés', Dinero.deSoles(5.00), 0),
    ProductoPlantilla('CAF-002', 'Capuchino', 'Cafés', Dinero.deSoles(8.00), 0),
    ProductoPlantilla(
        'CAF-003', 'Café americano', 'Cafés', Dinero.deSoles(6.00), 0),
    ProductoPlantilla(
        'CAF-004', 'Jugo de naranja', 'Jugos', Dinero.deSoles(7.00), 0),
    ProductoPlantilla(
        'CAF-005', 'Jugo surtido', 'Jugos', Dinero.deSoles(8.00), 0),
    ProductoPlantilla(
        'CAF-006', 'Sándwich de pollo', 'Sándwiches', Dinero.deSoles(10.00), 0),
    ProductoPlantilla(
        'CAF-007', 'Sándwich mixto', 'Sándwiches', Dinero.deSoles(9.00), 0),
    ProductoPlantilla(
        'CAF-008', 'Torta de chocolate', 'Postres', Dinero.deSoles(9.00), 0),
    ProductoPlantilla('CAF-009', 'Empanada', 'Postres', Dinero.deSoles(4.50), 0),
    ProductoPlantilla('CAF-010', 'Agua San Luis 625ml', 'Bebidas',
        Dinero.deSoles(2.00), 30),
  ];

  // --------------------------------------------------------------- Pollería ---

  static final List<ProductoPlantilla> _polleria = <ProductoPlantilla>[
    ProductoPlantilla('POL-001', 'Pollo a la brasa entero', 'Pollos',
        Dinero.deSoles(55.00), 0),
    ProductoPlantilla(
        'POL-002', '1/2 Pollo a la brasa', 'Pollos', Dinero.deSoles(30.00), 0),
    ProductoPlantilla(
        'POL-003', '1/4 Pollo a la brasa', 'Pollos', Dinero.deSoles(18.00), 0),
    ProductoPlantilla(
        'POL-004', 'Parrilla personal', 'Parrillas', Dinero.deSoles(32.00), 0),
    ProductoPlantilla('POL-005', 'Anticuchos (2 palos)', 'Parrillas',
        Dinero.deSoles(15.00), 0),
    ProductoPlantilla('POL-006', 'Porción de papas fritas', 'Guarniciones',
        Dinero.deSoles(8.00), 0),
    ProductoPlantilla(
        'POL-007', 'Ensalada', 'Guarniciones', Dinero.deSoles(6.00), 0),
    ProductoPlantilla('POL-008', 'Chicha morada (jarra)', 'Bebidas',
        Dinero.deSoles(12.00), 0),
    ProductoPlantilla(
        'POL-009', 'Inca Kola 1.5L', 'Bebidas', Dinero.deSoles(8.00), 24),
    ProductoPlantilla(
        'POL-010', 'Cerveza Cusqueña', 'Bebidas', Dinero.deSoles(10.00), 24),
  ];

  // --------------------------------------------------------------- Farmacia ---
  //
  // Se siembran principio activo (DCI), registro sanitario DIGEMID, si requiere
  // receta, stock mínimo y meses al vencimiento (algunos "por vencer" para que
  // el módulo de Vencimientos se vea poblado desde el primer día).

  static final List<ProductoPlantilla> _farmacia = <ProductoPlantilla>[
    ProductoPlantilla('FAR-001', 'Paracetamol 500mg (blíster x10)',
        'Analgésicos', Dinero.deSoles(3.50), 60,
        principioActivo: 'Paracetamol',
        registroSanitario: 'EN-01234',
        stockMinimo: 20,
        mesesVence: 18),
    ProductoPlantilla('FAR-002', 'Ibuprofeno 400mg (blíster x10)', 'Analgésicos',
        Dinero.deSoles(5.00), 50,
        principioActivo: 'Ibuprofeno',
        registroSanitario: 'EN-02345',
        stockMinimo: 15,
        mesesVence: 12),
    ProductoPlantilla('FAR-003', 'Naproxeno 550mg (blíster x10)', 'Analgésicos',
        Dinero.deSoles(7.00), 30,
        principioActivo: 'Naproxeno sódico',
        registroSanitario: 'EN-03456',
        stockMinimo: 10,
        mesesVence: 2),
    ProductoPlantilla('FAR-004', 'Panadol Antigripal (caja x12)', 'Antigripales',
        Dinero.deSoles(8.00), 40,
        principioActivo: 'Paracetamol + Clorfenamina + Fenilefrina',
        registroSanitario: 'EE-04567',
        stockMinimo: 12,
        mesesVence: 10),
    ProductoPlantilla('FAR-005', 'Amoxicilina 500mg (caja x100)', 'Antibióticos',
        Dinero.deSoles(25.00), 20,
        principioActivo: 'Amoxicilina',
        registroSanitario: 'EG-05678',
        requiereReceta: true,
        stockMinimo: 8,
        mesesVence: 8),
    ProductoPlantilla('FAR-006', 'Azitromicina 500mg (blíster x3)',
        'Antibióticos', Dinero.deSoles(15.00), 15,
        principioActivo: 'Azitromicina',
        registroSanitario: 'EG-06789',
        requiereReceta: true,
        stockMinimo: 6,
        mesesVence: 1),
    ProductoPlantilla('FAR-007', 'Omeprazol 20mg (blíster x14)',
        'Gastrointestinal', Dinero.deSoles(6.00), 35,
        principioActivo: 'Omeprazol',
        registroSanitario: 'EN-07890',
        stockMinimo: 12,
        mesesVence: 14),
    ProductoPlantilla('FAR-008', 'Sales de rehidratación oral',
        'Gastrointestinal', Dinero.deSoles(2.50), 50,
        principioActivo: 'Electrolitos orales',
        registroSanitario: 'EN-08901',
        stockMinimo: 15,
        mesesVence: 20),
    ProductoPlantilla('FAR-009', 'Vitamina C 1g (tubo efervescente)',
        'Vitaminas', Dinero.deSoles(18.00), 25,
        principioActivo: 'Ácido ascórbico',
        registroSanitario: 'EE-09012',
        stockMinimo: 8,
        mesesVence: 9),
    ProductoPlantilla('FAR-010', 'Complejo B (blíster x10)', 'Vitaminas',
        Dinero.deSoles(9.00), 25,
        principioActivo: 'Vitaminas B1 B6 B12',
        registroSanitario: 'EE-09123',
        stockMinimo: 8,
        mesesVence: 15),
    ProductoPlantilla('FAR-011', 'Alcohol 96° 250ml', 'Primeros auxilios',
        Dinero.deSoles(6.00), 30,
        stockMinimo: 10, mesesVence: 24),
    ProductoPlantilla('FAR-012', 'Alcohol en gel 250ml', 'Primeros auxilios',
        Dinero.deSoles(9.00), 30,
        stockMinimo: 10, mesesVence: 24),
    ProductoPlantilla('FAR-013', 'Agua oxigenada 120ml', 'Primeros auxilios',
        Dinero.deSoles(4.00), 25,
        stockMinimo: 8, mesesVence: 16),
    ProductoPlantilla('FAR-014', 'Curitas (caja x100)', 'Primeros auxilios',
        Dinero.deSoles(5.00), 20,
        stockMinimo: 6),
    ProductoPlantilla('FAR-015', 'Mascarilla quirúrgica (unidad)', 'Higiene',
        Dinero.deSoles(0.50), 200,
        stockMinimo: 50),
    ProductoPlantilla(
        'FAR-016', 'Jabón antibacterial', 'Higiene', Dinero.deSoles(4.50), 40,
        stockMinimo: 12),
    ProductoPlantilla('FAR-017', 'Shampoo 400ml', 'Cuidado personal',
        Dinero.deSoles(15.00), 20,
        stockMinimo: 6),
    ProductoPlantilla(
        'FAR-018', 'Pañales talla M (paquete)', 'Bebé', Dinero.deSoles(35.00), 15,
        stockMinimo: 5),
    ProductoPlantilla('FAR-019', 'Termómetro digital', 'Primeros auxilios',
        Dinero.deSoles(22.00), 10,
        stockMinimo: 3),
    ProductoPlantilla('FAR-020', 'Preservativos (caja x3)', 'Cuidado personal',
        Dinero.deSoles(6.00), 30,
        stockMinimo: 10),
  ];

  // -------------------------------------------------------------- Ferretería ---

  static final List<ProductoPlantilla> _ferreteria = <ProductoPlantilla>[
    ProductoPlantilla('FER-001', 'Martillo carpintero 25oz',
        'Herramientas manuales', Dinero.deSoles(25.00), 15,
        stockMinimo: 3),
    ProductoPlantilla('FER-002', 'Desarmador estrella', 'Herramientas manuales',
        Dinero.deSoles(8.00), 30,
        stockMinimo: 6),
    ProductoPlantilla('FER-003', 'Alicate universal 8"', 'Herramientas manuales',
        Dinero.deSoles(18.00), 20,
        stockMinimo: 4),
    ProductoPlantilla('FER-004', 'Cinta métrica 5m', 'Herramientas manuales',
        Dinero.deSoles(12.00), 20,
        stockMinimo: 5),
    ProductoPlantilla('FER-005', 'Taladro percutor 650W',
        'Herramientas eléctricas', Dinero.deSoles(150.00), 8,
        stockMinimo: 2),
    ProductoPlantilla('FER-006', 'Disco de corte 4-1/2"', 'Abrasivos y discos',
        Dinero.deSoles(3.50), 60,
        stockMinimo: 15),
    ProductoPlantilla(
        'FER-007', 'Foco LED 9W', 'Iluminación', Dinero.deSoles(7.00), 50,
        stockMinimo: 12),
    ProductoPlantilla(
        'FER-008', 'Interruptor simple', 'Electricidad', Dinero.deSoles(5.00), 40,
        stockMinimo: 10),
    ProductoPlantilla('FER-009', 'Cable mellizo 14 AWG (metro)', 'Electricidad',
        Dinero.deSoles(2.50), 200,
        stockMinimo: 50),
    ProductoPlantilla('FER-010', 'Tomacorriente doble', 'Electricidad',
        Dinero.deSoles(6.50), 40,
        stockMinimo: 10),
    ProductoPlantilla('FER-011', 'Caño PVC 1/2" (3m)', 'Gasfitería / Plomería',
        Dinero.deSoles(6.00), 40,
        stockMinimo: 8),
    ProductoPlantilla('FER-012', 'Cinta teflón', 'Gasfitería / Plomería',
        Dinero.deSoles(1.50), 100,
        stockMinimo: 20),
    ProductoPlantilla('FER-013', 'Pintura látex blanco 1gal',
        'Pinturas y accesorios', Dinero.deSoles(45.00), 12,
        stockMinimo: 3),
    ProductoPlantilla(
        'FER-014', 'Brocha 3"', 'Pinturas y accesorios', Dinero.deSoles(6.00), 30,
        stockMinimo: 6),
    ProductoPlantilla('FER-015', 'Silicona transparente',
        'Adhesivos y pegamentos', Dinero.deSoles(10.00), 25,
        stockMinimo: 5),
    ProductoPlantilla('FER-016', 'Pegamento para PVC 1/4',
        'Adhesivos y pegamentos', Dinero.deSoles(12.00), 20,
        stockMinimo: 4),
    ProductoPlantilla('FER-017', 'Clavos 2" (kg)',
        'Fijación (clavos y tornillos)', Dinero.deSoles(8.00), 30,
        stockMinimo: 6),
    ProductoPlantilla('FER-018', 'Tornillo autorroscante (caja x100)',
        'Fijación (clavos y tornillos)', Dinero.deSoles(9.00), 25,
        stockMinimo: 5),
    ProductoPlantilla('FER-019', 'Candado 40mm', 'Cerrajería y candados',
        Dinero.deSoles(15.00), 20,
        stockMinimo: 4),
    ProductoPlantilla('FER-020', 'Guantes de seguridad',
        'Seguridad y protección', Dinero.deSoles(5.00), 40,
        stockMinimo: 10),
    ProductoPlantilla(
        'FER-021', 'Cemento Sol 42.5kg', 'Construcción', Dinero.deSoles(32.00), 30,
        stockMinimo: 8),
  ];

  // --------------------------------------------------------------- Licorería ---

  static final List<ProductoPlantilla> _licoreria = <ProductoPlantilla>[
    ProductoPlantilla(
        'LIC-001', 'Cerveza Pilsen 630ml', 'Cervezas', Dinero.deSoles(7.50), 48),
    ProductoPlantilla('LIC-002', 'Cerveza Cristal 630ml', 'Cervezas',
        Dinero.deSoles(7.50), 48),
    ProductoPlantilla('LIC-003', 'Cerveza Cusqueña 620ml', 'Cervezas',
        Dinero.deSoles(8.50), 36),
    ProductoPlantilla('LIC-004', 'Pisco Quebranta 750ml', 'Licores',
        Dinero.deSoles(45.00), 12),
    ProductoPlantilla(
        'LIC-005', 'Ron Cartavio 750ml', 'Licores', Dinero.deSoles(38.00), 12),
    ProductoPlantilla(
        'LIC-006', 'Vino Tacama tinto', 'Vinos', Dinero.deSoles(35.00), 15),
    ProductoPlantilla('LIC-007', 'Whisky Johnnie Walker', 'Licores',
        Dinero.deSoles(75.00), 8),
    ProductoPlantilla(
        'LIC-008', 'Inca Kola 1.5L', 'Gaseosas', Dinero.deSoles(8.00), 30),
    ProductoPlantilla(
        'LIC-009', 'Hielo (bolsa)', 'Otros', Dinero.deSoles(5.00), 40),
    ProductoPlantilla(
        'LIC-010', 'Piqueo surtido', 'Otros', Dinero.deSoles(6.00), 30),
  ];

  // ------------------------------------------------------------------- Hotel ---
  //
  // Las HABITACIONES NO son productos (se administran aparte y se alquilan
  // desde Cobrar). Aquí solo van los consumibles/servicios que se venden en el
  // POS o se cargan a la habitación.

  static final List<ProductoPlantilla> _hotel = <ProductoPlantilla>[
    ProductoPlantilla(
        'HAB-005', 'Desayuno buffet', 'Restaurante', Dinero.deSoles(25.00), 0),
    ProductoPlantilla(
        'HAB-006', 'Agua mineral', 'Minibar', Dinero.deSoles(4.00), 50),
    ProductoPlantilla(
        'HAB-007', 'Gaseosa lata', 'Minibar', Dinero.deSoles(5.00), 50),
    ProductoPlantilla('HAB-008', 'Cerveza', 'Minibar', Dinero.deSoles(10.00), 40),
    ProductoPlantilla(
        'HAB-009', 'Snack / piqueo', 'Minibar', Dinero.deSoles(6.00), 40),
    ProductoPlantilla('HAB-010', 'Lavandería (prenda)', 'Servicios',
        Dinero.deSoles(8.00), 0),
  ];

  // ------------------------------------------------------------------ Bodega ---

  static final List<ProductoPlantilla> _bodega = <ProductoPlantilla>[
    ProductoPlantilla(
        '7501055', 'Inca Kola 500ml', 'Bebidas', Dinero.deSoles(3.50), 48),
    ProductoPlantilla(
        '7501056', 'Coca Cola 500ml', 'Bebidas', Dinero.deSoles(3.50), 40),
    ProductoPlantilla(
        '7501099', 'Cerveza Pilsen 630ml', 'Bebidas', Dinero.deSoles(7.50), 24),
    ProductoPlantilla(
        '7502001', 'Arroz Costeño 1kg', 'Abarrotes', Dinero.deSoles(5.80), 30),
    ProductoPlantilla(
        '7502002', 'Aceite Primor 1L', 'Abarrotes', Dinero.deSoles(9.90), 18),
    ProductoPlantilla(
        '7502003', 'Leche Gloria tarro', 'Abarrotes', Dinero.deSoles(4.20), 36),
    ProductoPlantilla(
        '7503010', "Papas Lay's", 'Snacks', Dinero.deSoles(3.80), 22),
    ProductoPlantilla(
        '7503011', 'Galleta Soda Field', 'Snacks', Dinero.deSoles(1.50), 60),
    ProductoPlantilla(
        '7503012', 'Chocolate Sublime', 'Golosinas', Dinero.deSoles(2.00), 50),
    ProductoPlantilla('7504020', 'Detergente Bolívar 780g', 'Limpieza',
        Dinero.deSoles(8.50), 14),
    ProductoPlantilla(
        '7506001', 'Pan francés (und)', 'Panadería', Dinero.deSoles(0.30), 200),
  ];
}
