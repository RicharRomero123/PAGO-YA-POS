/// Acceso clave/valor a la tabla `meta` de SQLite para el licenciamiento.
///
/// `meta(clave TEXT PRIMARY KEY, valor TEXT NOT NULL)` es idéntica a la del
/// escritorio (`src/PagoYa.Data/Esquema/esquema.sql`). Se usa `meta` y no el
/// almacén seguro a propósito: esto no son secretos, son marcas
/// anti-manipulación y metadatos del asiento que otros módulos también leen.
///
/// **Todas las operaciones son best-effort.** Si la base no está disponible se
/// devuelve `null` y se sigue: perder una marca degrada una defensa, pero
/// bloquear la caja por no poder escribir una fila sería peor.
library;

import '../datos/ejecutor_sql.dart';

/// Claves de `meta` que escribe el licenciamiento. Prefijadas para no chocar
/// con `flutter-datos` (configuración) ni con `flutter-sync` (cursores).
abstract final class ClavesMetaLicencia {
  /// Instante UTC máximo visto por la app (ISO-8601). Monotónico.
  static const String ultimoVistoUtc = 'licencia.ultimo_visto_utc';

  /// Último intento de revalidación online (ISO-8601), para el throttling.
  static const String ultimaRevalidacionUtc = 'licencia.ultima_revalidacion_utc';

  /// Último instante en que se detectó un retroceso sospechoso (ISO-8601).
  static const String ultimoRetrocesoUtc = 'licencia.ultimo_retroceso_utc';

  /// Prefijo de dispositivo asignado por el server (`M01`..`M99`), leído del
  /// claim `device_prefix` del token firmado.
  ///
  /// **Lo consumen otros agentes**: `flutter-datos` para los correlativos
  /// `M01-000123` (`ventas.numero`) y `flutter-sync` como `origen_caja_id` del
  /// outbox / filtro de eco. Se escribe aquí porque el valor viene firmado
  /// dentro del token y esta es la única capa que lo verifica.
  static const String prefijoDispositivo = 'licencia.device_prefix';

  /// Id del **asiento** (fila `Devices` del backend), del claim `device_id`.
  /// Es el `{id}` de `DELETE /devices/{id}`; se muestra en Ajustes para que el
  /// dueño pueda pedir la revocación a soporte.
  static const String idAsiento = 'licencia.device_id';
}

/// Lector/escritor de `meta` tolerante a fallos.
final class MetaLicencia {
  final EjecutorSql _sql;

  const MetaLicencia(this._sql);

  /// Valor de [clave], o `null` si no existe o la base no está disponible.
  Future<String?> leer(String clave) async {
    try {
      final Object? valor = await _sql.escalar(
        'SELECT valor FROM meta WHERE clave = ?',
        <Object?>[clave],
      );
      final String? texto = valor?.toString().trim();
      return (texto == null || texto.isEmpty) ? null : texto;
    } catch (_) {
      return null;
    }
  }

  /// Escribe (upsert) [valor] bajo [clave]. Nunca lanza.
  Future<void> escribir(String clave, String valor) async {
    try {
      await _sql.ejecutar(
        'INSERT INTO meta(clave, valor) VALUES (?, ?) '
        'ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor',
        <Object?>[clave, valor],
      );
    } catch (_) {
      // El próximo arranque lo reintenta.
    }
  }

  /// Borra [clave]. Nunca lanza.
  Future<void> borrar(String clave) async {
    try {
      await _sql.ejecutar(
        'DELETE FROM meta WHERE clave = ?',
        <Object?>[clave],
      );
    } catch (_) {
      // idem.
    }
  }

  /// Lee una marca temporal ISO-8601 en UTC, o `null` si no es parseable.
  Future<DateTime?> leerFecha(String clave) async {
    final String? valor = await leer(clave);
    if (valor == null) return null;
    return DateTime.tryParse(valor)?.toUtc();
  }

  /// Escribe una marca temporal en ISO-8601 UTC.
  Future<void> escribirFecha(String clave, DateTime valor) =>
      escribir(clave, valor.toUtc().toIso8601String());
}

/// [MetaLicencia] en memoria, para tests y para el arranque de emergencia.
final class MetaLicenciaEnMemoria implements MetaLicencia {
  /// Contenido visible para los tests.
  final Map<String, String> datos;

  MetaLicenciaEnMemoria([Map<String, String>? inicial])
      : datos = <String, String>{...?inicial};

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> escribir(String clave, String valor) async {
    datos[clave] = valor;
  }

  @override
  Future<void> borrar(String clave) async {
    datos.remove(clave);
  }

  @override
  Future<DateTime?> leerFecha(String clave) async {
    final String? valor = datos[clave];
    if (valor == null) return null;
    return DateTime.tryParse(valor)?.toUtc();
  }

  @override
  Future<void> escribirFecha(String clave, DateTime valor) async {
    datos[clave] = valor.toUtc().toIso8601String();
  }
}
