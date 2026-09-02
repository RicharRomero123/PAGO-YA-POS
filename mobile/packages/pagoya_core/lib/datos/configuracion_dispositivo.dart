// PagoYa Móvil — datos/configuracion_dispositivo.dart
//
// FUENTE ÚNICA de la identidad de sincronización de este dispositivo.
//
// POR QUÉ EXISTE
// --------------
// Dos valores tienen que ser exactamente el mismo en tres sitios distintos, y
// si se calculan por separado la sincronización falla en silencio:
//
//   * `origenCajaId` — se estampa en la columna `origen_caja_id` de CADA fila
//     de negocio y de CADA evento de `outbox_sync`, y `flutter-sync` lo manda
//     como `?origen=` en el `GET /sync/pull`. El backend usa ese parámetro para
//     el FILTRO DE ECO (no devolvernos nuestros propios eventos). Si el valor
//     que estampamos y el que enviamos difieren aunque sea en mayúsculas, el
//     filtro no filtra: la app se re-aplica sus propias ventas, con el riesgo
//     de sobrescritura que describe docs/MOBILE-ARQUITECTURA.md §6.2.
//     Por eso se lee de UN solo lugar: la tabla `meta`.
//
//   * `prefijoDispositivo` — el prefijo del correlativo legible (`M01`).
//     **NO lo genera el móvil.** Lo asigna el SERVIDOR al vincular el
//     dispositivo (`POST /devices`) y lo devuelve como `devicePrefix`:
//     `C01`..`C99` para escritorio, `M01`..`M99` para móvil, único por licencia
//     y no reutilizable tras revocar. El móvil solo lo guarda y lo compone con
//     el contador local. Derivarlo del id del dispositivo produciría choques
//     entre dos celulares de la misma bodega.
//
// Quien recibe la respuesta de `POST /devices` (dueño: `flutter-licencia`)
// llama a `guardarVinculacion` con lo que dijo el servidor. Todo lo demás lee
// de aquí.

library;

import 'ejecutor_sql.dart';
import 'esquema.dart';

/// Identidad de sincronización del dispositivo, cacheada en memoria.
final class ConfiguracionDispositivo {
  /// Prefijo de respaldo mientras la app **no está vinculada** al servidor.
  ///
  /// No es un prefijo válido para producción: es un marcador que permite
  /// operar offline antes de la activación sin dejar `ventas.numero` vacío.
  /// En cuanto llega el `devicePrefix` real, las ventas nuevas lo usan; las
  /// viejas conservan el suyo (los correlativos ya emitidos no se reescriben,
  /// un ticket entregado al cliente no se puede renumerar).
  static const String prefijoSinVincular = 'M00';

  final EjecutorSql _db;

  String? _origenCajaId;
  String? _prefijo;

  ConfiguracionDispositivo(this._db);

  /// `origen_caja_id` de este dispositivo. Cadena vacía si aún no se vinculó
  /// (el escritorio también usa '' por defecto, así que es compatible).
  Future<String> origenCajaId() async =>
      _origenCajaId ??= await _leer(ClavesMeta.origenCajaId) ?? '';

  /// Prefijo de correlativo asignado por el servidor. Ver [prefijoSinVincular].
  Future<String> prefijoDispositivo() async =>
      _prefijo ??= await _leer(ClavesMeta.prefijoDispositivo) ?? prefijoSinVincular;

  /// True si el servidor ya asignó un prefijo real.
  Future<bool> estaVinculado() async =>
      (await prefijoDispositivo()) != prefijoSinVincular;

  /// Guarda lo que devolvió `POST /devices`.
  ///
  /// [devicePrefix] es el `devicePrefix` de la respuesta, tal cual. [origen] es
  /// el identificador de caja/dispositivo que se usará en `origen_caja_id` y en
  /// `?origen=` del pull. Se normaliza aquí (trim + mayúsculas en el prefijo)
  /// para que no haya dos grafías del mismo valor dando vueltas.
  Future<void> guardarVinculacion({
    required String devicePrefix,
    required String origen,
  }) async {
    final p = devicePrefix.trim().toUpperCase();
    final o = origen.trim();
    if (p.isEmpty) {
      throw const ErrorDatos(
          'El servidor no devolvió devicePrefix: no se puede numerar sin él.');
    }
    await _escribir(ClavesMeta.prefijoDispositivo, p);
    await _escribir(ClavesMeta.origenCajaId, o);
    _prefijo = p;
    _origenCajaId = o;
  }

  /// Olvida la vinculación (revocación del seat desde el panel admin).
  ///
  /// NO borra las ventas ya numeradas: el servidor no reutiliza prefijos, así
  /// que los correlativos viejos siguen siendo únicos para siempre.
  Future<void> limpiarVinculacion() async {
    await _escribir(ClavesMeta.prefijoDispositivo, prefijoSinVincular);
    await _escribir(ClavesMeta.origenCajaId, '');
    _prefijo = prefijoSinVincular;
    _origenCajaId = '';
  }

  /// Invalida la caché en memoria (tras una restauración de respaldo, p.ej.).
  void invalidarCache() {
    _origenCajaId = null;
    _prefijo = null;
  }

  Future<String?> _leer(String clave) async {
    final v = await _db.escalar(
      'SELECT valor FROM meta WHERE clave = ?',
      [clave],
    );
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  Future<void> _escribir(String clave, String valor) => _db.ejecutar(
        'INSERT INTO meta (clave, valor) VALUES (?, ?) '
        'ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor',
        [clave, valor],
      );
}
