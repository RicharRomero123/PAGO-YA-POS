// PagoYa Móvil — datos/esquema.dart
//
// El esquema SQLite del POS de escritorio, embebido como constante Dart.
//
// POR QUÉ UNA CONSTANTE Y NO UN ASSET: `pagoya_core` es Dart puro y no puede
// usar `rootBundle` (eso obligaría a importar Flutter y rompería la regla de
// docs/MOBILE-ARQUITECTURA.md §2). El archivo `esquema.sql` de al lado es la
// copia legible para diffear contra `src/PagoYa.Data/Esquema/esquema.sql`;
// esta constante es la que se EJECUTA. Si tocas uno, toca el otro.

library;

import 'esquema_sql.dart';

/// Esquema y migraciones de la base local.
abstract final class Esquema {
  /// Versión del esquema, igual que la fila `meta('schema_version')` del
  /// escritorio.
  static const int version = 1;

  /// PRAGMAs que hay que aplicar **por conexión** (no son persistentes salvo
  /// `journal_mode`). Espeja `PagoYaDbContext.AplicarPragmas`.
  ///
  /// `foreign_keys` se activa por conexión en SQLite: si se olvida, las FK del
  /// esquema quedan decorativas y se pueden insertar detalles de venta
  /// huérfanos. `busy_timeout` evita que la escritura del outbox falle cuando
  /// el hilo de sincronización está leyendo.
  static const List<String> pragmas = <String>[
    'PRAGMA foreign_keys = ON',
    'PRAGMA journal_mode = WAL',
    'PRAGMA busy_timeout = 5000',
  ];

  /// Migraciones aditivas: columnas que el escritorio agrega con
  /// `AsegurarColumna` porque `CREATE TABLE IF NOT EXISTS` no altera tablas ya
  /// creadas. Se replican para que una BD móvil nueva quede **columna a
  /// columna idéntica** a una BD de escritorio actualizada.
  ///
  /// `(tabla, columna, definición)`.
  static const List<(String, String, String)> migracionesAditivas =
      <(String, String, String)>[
    ('productos', 'imagen_ruta', 'TEXT NULL'),
    ('productos', 'proveedor_id', 'TEXT NULL'),
    // Descuento por producto: tipo (0 ninguno / 1 % / 2 oferta) + valor.
    ('productos', 'tipo_descuento', 'INTEGER NOT NULL DEFAULT 0'),
    ('productos', 'descuento_valor', 'REAL NOT NULL DEFAULT 0'),
    // Umbral de reposición + campos farmacéuticos (rubro farmacia/botica).
    ('productos', 'stock_minimo', 'REAL NOT NULL DEFAULT 0'),
    ('productos', 'fecha_vencimiento', 'TEXT NULL'),
    ('productos', 'lote', 'TEXT NULL'),
    ('productos', 'registro_sanitario', 'TEXT NULL'),
    ('productos', 'principio_activo', 'TEXT NULL'),
    ('productos', 'requiere_receta', 'INTEGER NOT NULL DEFAULT 0'),
    ('productos', 'personalizacion_json', 'TEXT NULL'),
    ('habitaciones', 'imagen_ruta', 'TEXT NULL'),
    ('habitaciones', 'comodidades', 'TEXT NULL'),
  ];

  /// Sentencias DDL en orden de ejecución (sin los PRAGMA, que van aparte).
  static List<String> get sentencias => _sentencias ??= _partir(scriptEsquemaSql);
  static List<String>? _sentencias;

  /// Divide el script en sentencias: quita los comentarios de línea `--` y
  /// corta por `;`. El script embebido no contiene literales con `;` ni `--`
  /// dentro, así que un partido simple basta y evita traer un parser SQL.
  static List<String> _partir(String script) {
    final sinComentarios = script
        .split('\n')
        .map((l) {
          final i = l.indexOf('--');
          return i >= 0 ? l.substring(0, i) : l;
        })
        .join('\n');

    return sinComentarios
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        // Los PRAGMA se aplican por conexión, no como parte del DDL.
        .where((s) => !s.toUpperCase().startsWith('PRAGMA'))
        .toList(growable: false);
  }
}

/// Claves conocidas de la tabla `meta`.
///
/// `meta` es el pequeño almacén clave/valor de la BD local. El escritorio ya
/// usa `schema_version` y `sync_cursor`; el móvil agrega las suyas.
abstract final class ClavesMeta {
  static const String versionEsquema = 'schema_version';

  /// Cursor de bajada de la sincronización (lo lee/escribe `flutter-sync`).
  static const String cursorSync = 'sync_cursor';

  /// Prefijo de correlativo de este dispositivo (`M01`). Ver
  /// `datos/correlativos.dart`.
  static const String prefijoDispositivo = 'prefijo_dispositivo';

  /// Último correlativo de venta emitido por este dispositivo.
  static const String correlativoVenta = 'correlativo_venta';

  /// Último correlativo de pedido/comanda emitido por este dispositivo.
  static const String correlativoPedido = 'correlativo_pedido';

  /// `origen_caja_id` que este dispositivo estampa en cada fila.
  static const String origenCajaId = 'origen_caja_id';

  /// Rubro elegido en el onboarding (clave de `PlantillasRubro`).
  static const String rubro = 'rubro';

  /// Marca monotónica del reloj para detectar retrocesos de fecha
  /// (docs/MOBILE-ARQUITECTURA.md §5.5). La escribe `flutter-licencia`.
  static const String ultimoVistoUtc = 'ultimo_visto_utc';
}
