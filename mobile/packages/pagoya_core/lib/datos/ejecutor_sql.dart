// PagoYa Móvil — datos/ejecutor_sql.dart
//
// La superficie mínima de base de datos que usan los repositorios.
//
// POR QUÉ UNA ABSTRACCIÓN Y NO DRIFT DIRECTO
// ------------------------------------------
// 1. Aísla la API de drift en UN solo archivo (`base_datos_drift.dart`). Si la
//    versión de drift que fije `mobile-lead` en el pubspec cambia una firma,
//    se arregla ahí y no en diez repositorios.
// 2. Permite testear los repositorios contra cualquier motor SQLite (el
//    `NativeDatabase.memory()` de las pruebas, por ejemplo) sin arrastrar
//    Flutter a `pagoya_core`.
// 3. Deja explícito qué necesita el outbox: **transacciones anidables**. La
//    escritura de negocio y su fila de `outbox_sync` van juntas o no van.
//
// No se usa el generador de código de drift a propósito: el esquema se copia
// literal del escritorio con `customStatement`, así que no hay clases de tabla
// que generar y el proyecto no depende de `build_runner`.

library;

/// Ejecutor de SQL con placeholders posicionales (`?`).
///
/// Se usan posicionales y no nombrados porque es lo que soportan por igual
/// drift, `sqlite3` y `sqflite`; los mapas nombrados de las entidades se
/// convierten a listas en `sentencias.dart`.
abstract interface class EjecutorSql {
  /// Ejecuta una sentencia que no devuelve filas.
  Future<void> ejecutar(String sql, [List<Object?> args = const []]);

  /// Ejecuta una sentencia y devuelve cuántas filas afectó.
  ///
  /// Necesario para el last-write-wins: un `ON CONFLICT ... WHERE excluded.
  /// updated_utc > tabla.updated_utc` que devuelve 0 significa "el remoto era
  /// más viejo, no se aplicó", y así es como se cuentan los cambios aplicados.
  Future<int> ejecutarContando(String sql, [List<Object?> args = const []]);

  /// Consulta que devuelve filas como mapas columna -> valor.
  Future<List<Map<String, Object?>>> consultar(
    String sql, [
    List<Object?> args = const [],
  ]);

  /// Primer valor escalar de la consulta, o null si no hay filas.
  Future<Object?> escalar(String sql, [List<Object?> args = const []]);

  /// Ejecuta [accion] dentro de una transacción.
  ///
  /// Si [accion] lanza, se hace ROLLBACK y la excepción se propaga: es la
  /// garantía que sostiene el outbox. Si ya se está dentro de una transacción,
  /// la implementación debe reusarla (SQLite no anida transacciones reales).
  Future<T> transaccion<T>(Future<T> Function(EjecutorSql tx) accion);
}

/// Error de una operación de datos que la UI puede mostrar tal cual.
final class ErrorDatos implements Exception {
  final String mensaje;
  final Object? causa;

  const ErrorDatos(this.mensaje, [this.causa]);

  @override
  String toString() =>
      causa == null ? 'ErrorDatos: $mensaje' : 'ErrorDatos: $mensaje ($causa)';
}
