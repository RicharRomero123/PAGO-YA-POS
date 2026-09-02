// PagoYa Móvil — datos/sentencias.dart
//
// Constructores de SQL a partir de los mapas `aFila()` de las entidades.
//
// POR QUÉ: el escritorio escribe los INSERT/UPSERT a mano con parámetros
// nombrados de Dapper. Aquí los mapas nombrados se traducen a SQL con
// placeholders posicionales `?` en un solo lugar, para que ningún repositorio
// pueda desalinear la lista de columnas de la lista de valores — el bug clásico
// que mete el precio en la columna del stock y solo se nota semanas después.

library;

/// Una sentencia lista para ejecutar: SQL + argumentos posicionales.
typedef SentenciaSql = ({String sql, List<Object?> args});

/// Helpers para armar SQL a partir de mapas columna -> valor.
abstract final class Sql {
  /// `INSERT INTO tabla (cols) VALUES (?, ?, …)`.
  ///
  /// [conflicto] permite `'OR IGNORE'` o dejar el `ON CONFLICT` para
  /// [insertarSiFalta] / [upsert].
  static SentenciaSql insertar(String tabla, Map<String, Object?> fila) {
    final cols = fila.keys.toList(growable: false);
    final marcas = List.filled(cols.length, '?').join(', ');
    return (
      sql: 'INSERT INTO $tabla (${cols.join(', ')}) VALUES ($marcas)',
      args: cols.map((c) => fila[c]).toList(growable: false),
    );
  }

  /// `INSERT … ON CONFLICT(id) DO NOTHING`.
  ///
  /// Es la estrategia para las entidades INMUTABLES del kardex y del arqueo
  /// (`inventario`, `movimientos_caja`, `detalle_ventas`): su identidad UUID es
  /// global y estable, así que recibir dos veces el mismo evento no debe
  /// duplicar la fila ni pisarla.
  static SentenciaSql insertarSiFalta(
    String tabla,
    Map<String, Object?> fila, {
    String pk = 'id',
  }) {
    final base = insertar(tabla, fila);
    return (
      sql: '${base.sql}\nON CONFLICT($pk) DO NOTHING',
      args: base.args,
    );
  }

  /// `INSERT … ON CONFLICT(id) DO UPDATE SET … [WHERE guardaLww]`.
  ///
  /// [columnasActualizables] son las que se pisan en caso de conflicto: se pasa
  /// una lista explícita porque hay columnas que NO deben pisarse nunca
  /// (`stock_actual`, ver `outbox_store.dart`) y otras que son inmutables tras
  /// la creación (`created_utc`).
  ///
  /// Con [guardaLww] `true` se añade la cláusula
  /// `WHERE excluded.updated_utc > tabla.updated_utc`, que es exactamente el
  /// last-write-wins que usa `OutboxStore` en el escritorio: si el cambio que
  /// llega de la nube es más viejo que lo local, no se aplica.
  static SentenciaSql upsert(
    String tabla,
    Map<String, Object?> fila, {
    required List<String> columnasActualizables,
    String pk = 'id',
    bool guardaLww = false,
  }) {
    final base = insertar(tabla, fila);
    final sets =
        columnasActualizables.map((c) => '$c = excluded.$c').join(',\n    ');
    final guarda =
        guardaLww ? '\nWHERE excluded.updated_utc > $tabla.updated_utc' : '';
    return (
      sql: '${base.sql}\nON CONFLICT($pk) DO UPDATE SET\n    $sets$guarda',
      args: base.args,
    );
  }

  /// `UPDATE tabla SET c = ?, … WHERE <condicion>`.
  static SentenciaSql actualizar(
    String tabla,
    Map<String, Object?> cambios, {
    required String condicion,
    List<Object?> argsCondicion = const [],
  }) {
    final cols = cambios.keys.toList(growable: false);
    final sets = cols.map((c) => '$c = ?').join(', ');
    return (
      sql: 'UPDATE $tabla SET $sets WHERE $condicion',
      args: [...cols.map((c) => cambios[c]), ...argsCondicion],
    );
  }

  /// Lista de `?` separados por coma, para cláusulas `IN (…)`.
  static String marcas(int n) => List.filled(n, '?').join(', ');
}
