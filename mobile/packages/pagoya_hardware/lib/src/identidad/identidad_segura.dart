import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pagoya_core/pagoya_core.dart' show IdentidadDispositivo;
import 'package:shared_preferences/shared_preferences.dart';

import '../almacen/opciones_almacen_seguro.dart';
import 'contrato_identidad.dart';

/// Implementación real de [IdentidadDispositivo] (el contrato canónico vive en
/// `pagoya_core`; ver `contrato_identidad.dart` para el arbitraje).
///
/// **UUID v4 generado con [Random.secure] en el primer arranque**, persistido
/// en `flutter_secure_storage`. Ver [IdentidadDispositivo] para el razonamiento
/// completo de por qué no se usan `ANDROID_ID`, `identifierForVendor` ni un
/// hash de hardware al estilo del escritorio.
///
/// ## Copia sombra (y por qué existe)
///
/// El id se escribe **también** en `SharedPreferences`. No es una segunda
/// fuente de verdad: es un seguro contra un fallo real y frecuente en Android
/// de gama baja: tras una actualización de sistema o un cambio de bloqueo de
/// pantalla, el Android Keystore puede quedar inutilizable y
/// `EncryptedSharedPreferences` lanza al leer. Sin sombra, el id se perdería y
/// el cliente quedaría desactivado — el escenario exacto que este archivo
/// existe para evitar.
///
/// Consideración de seguridad: el UUID **no es un secreto**. Es un
/// identificador opaco que además viaja al backend en cada `POST /devices`.
/// Guardarlo en claro como respaldo no debilita nada; el token de licencia
/// firmado, que sí es sensible, lo guarda `flutter-licencia` y **solo** en
/// almacenamiento seguro.
///
/// Ninguna de las dos copias sobrevive a un borrado de datos de la app en
/// Android (es el comportamiento esperado: equipo nuevo, seat nuevo). En iOS el
/// Keychain sí sobrevive a la reinstalación, que es justo lo que queremos.
///
/// ## "No hay id" NO es lo mismo que "no pude leer el id"
///
/// Es la distinción más importante de esta clase. Si una lectura **falla** y se
/// trata como "no había nada", se genera un UUID nuevo, se registra como un
/// segundo asiento y el cliente **queda desactivado sin haber hecho nada**. El
/// contrato de `pagoya_core` lo prohíbe expresamente.
///
/// Por eso los lectores internos devuelven `(valor, fallo)` en vez de un
/// `String?`, y solo se genera un id cuando **ambas** lecturas terminaron bien
/// y estaban vacías. Si alguna falló, se lanza [AlmacenSeguroIlegible] y el
/// núcleo reintenta más tarde sin degradar la licencia.
class IdentidadDispositivoSegura
    implements IdentidadDispositivo, IdentidadDispositivoExtendida {
  IdentidadDispositivoSegura({
    FlutterSecureStorage? almacenSeguro,
    DeviceInfoPlugin? infoPlugin,
  })  : _seguro = almacenSeguro ?? almacenCifradoPagoYa,
        _infoPlugin = infoPlugin ?? DeviceInfoPlugin();

  final FlutterSecureStorage _seguro;
  final DeviceInfoPlugin _infoPlugin;

  /// Clave del almacén seguro. **No cambiar nunca**: cambiarla equivale a
  /// desactivar a todos los clientes instalados.
  static const String claveId = 'pagoya.dispositivo.id';

  /// Clave de la copia sombra en SharedPreferences.
  static const String claveSombra = 'pagoya.dispositivo.id.respaldo';

  String? _cache;

  /// Nombre y plataforma se consultan en cada llamada del núcleo, pero
  /// `device_info_plus` cruza el canal de plataforma: se cachea.
  InfoDispositivo? _cacheInfo;

  /// Devuelve el UUID del dispositivo, creándolo **solo** si es el primer
  /// arranque de verdad.
  ///
  /// Lanza [AlmacenSeguroIlegible] si no se pudo determinar si existía un id
  /// previo. Ver la nota sobre "ausente" vs "ilegible" en la clase.
  @override
  Future<String> obtenerIdDispositivo() async {
    final enMemoria = _cache;
    if (enMemoria != null) return enMemoria;

    // 1. Almacén seguro (fuente de verdad).
    final delSeguro = await _leerSeguro();
    final idSeguro = delSeguro.valor;
    if (_esUuidValido(idSeguro)) {
      _cache = idSeguro;
      await _escribirSombra(idSeguro!);
      return idSeguro;
    }

    // 2. Copia sombra: el Keystore falló o se vació. Se restaura al almacén
    //    seguro y se sigue con el MISMO id (la licencia se conserva).
    final deSombra = await _leerSombra();
    final idSombra = deSombra.valor;
    if (_esUuidValido(idSombra)) {
      _cache = idSombra;
      await _escribirSeguro(idSombra!);
      return idSombra;
    }

    // 3. Ninguna de las dos copias dio un id. Antes de generar hay que estar
    //    SEGUROS de que no había ninguno: si alguna lectura falló, "no hay id"
    //    y "no pude leer el id" son indistinguibles, y generar uno nuevo
    //    quemaría un seat y desactivaría a un cliente que sí tenía licencia.
    //    El contrato de `pagoya_core` lo dice explícitamente: nunca inventar un
    //    id en silencio. `ServicioLicencia` traduce esta excepción a fallo
    //    transitorio y reintenta más tarde, sin degradar la licencia.
    if (delSeguro.fallo || deSombra.fallo) {
      throw const AlmacenSeguroIlegible(
        'No se pudo leer la identidad guardada de este dispositivo.',
      );
    }

    // 4. Primer arranque de verdad: ambas lecturas funcionaron y estaban
    //    vacías. Ahora sí se genera.
    final nuevo = generarUuidV4();
    _cache = nuevo;
    await _escribirSeguro(nuevo);
    await _escribirSombra(nuevo);
    return nuevo;
  }

  /// `true` si ya hay un id guardado. **Nunca lanza**: ante un almacén ilegible
  /// devuelve `false`, porque quien pregunta esto (el onboarding) solo quiere
  /// saber si enseñar la pantalla de activación.
  @override
  Future<bool> yaExiste() async {
    if (_cache != null) return true;
    if (_esUuidValido((await _leerSeguro()).valor)) return true;
    return _esUuidValido((await _leerSombra()).valor);
  }

  @override
  Future<String> regenerar() async {
    final nuevo = generarUuidV4();
    _cache = nuevo;
    await _escribirSeguro(nuevo);
    await _escribirSombra(nuevo);
    return nuevo;
  }

  /// Nombre legible del equipo, para el panel admin. Lo consume
  /// `VinculadorAsiento` al llamar a `POST /devices`.
  @override
  Future<String> obtenerNombreDispositivo() async =>
      (await obtenerInfo()).nombre;

  /// `'android'` | `'ios'` | `'desconocido'`.
  @override
  Future<String> obtenerPlataforma() async => (await obtenerInfo()).plataforma;

  @override
  Future<InfoDispositivo> obtenerInfo() async {
    final id = await obtenerIdDispositivo();
    final cacheada = _cacheInfo;
    if (cacheada != null && cacheada.id == id) return cacheada;

    final info = await _leerInfoDelSistema(id);
    _cacheInfo = info;
    return info;
  }

  Future<InfoDispositivo> _leerInfoDelSistema(String id) async {
    try {
      if (Platform.isAndroid) {
        final a = await _infoPlugin.androidInfo;
        final marca = _capitalizar(a.manufacturer);
        return InfoDispositivo(
          id: id,
          nombre: '$marca ${a.model}'.trim(),
          modelo: a.model,
          fabricante: marca,
          plataforma: 'android',
          versionSistema: a.version.release,
          esFisico: a.isPhysicalDevice,
        );
      }
      if (Platform.isIOS) {
        final i = await _infoPlugin.iosInfo;
        return InfoDispositivo(
          id: id,
          nombre: i.name.trim().isEmpty ? i.utsname.machine : i.name,
          modelo: i.utsname.machine,
          fabricante: 'Apple',
          plataforma: 'ios',
          versionSistema: i.systemVersion,
          esFisico: i.isPhysicalDevice,
        );
      }
    } catch (_) {
      // device_info_plus puede fallar en un OEM raro; la identidad NO depende
      // de esto (el id ya está resuelto), así que se devuelve lo genérico en
      // vez de propagar. Un nombre feo en el panel admin es mejor que una
      // activación que no se completa.
    }
    return InfoDispositivo(
      id: id,
      nombre: 'Dispositivo',
      modelo: 'desconocido',
      fabricante: 'desconocido',
      plataforma: Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : 'desconocido',
      versionSistema: '',
      esFisico: true,
    );
  }

  // ------------------------------------------------------------------

  /// Lee del almacén seguro distinguiendo **ausente** de **ilegible**.
  ///
  /// Esta distinción es la razón por la que la identidad NO se implementa
  /// encima de `AlmacenSeguroFlutter`: el contrato de `AlmacenSeguro.leer`
  /// obliga a devolver `null` ante un fallo, y aquí ese `null` sería
  /// catastrófico (generaríamos un id nuevo y quemaríamos un seat). El token de
  /// licencia sí puede permitirse ese `null` — se vuelve a pedir; una identidad
  /// perdida, no.
  Future<({String? valor, bool fallo})> _leerSeguro() async {
    try {
      return (valor: await _seguro.read(key: claveId), fallo: false);
    } catch (_) {
      // Keystore corrupto (pasa en gama baja tras actualizar el sistema).
      return (valor: null, fallo: true);
    }
  }

  Future<void> _escribirSeguro(String valor) async {
    try {
      await _seguro.write(key: claveId, value: valor);
    } catch (_) {
      // Si no se puede escribir, queda la sombra. No se pierde el id.
    }
  }

  Future<({String? valor, bool fallo})> _leerSombra() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (valor: prefs.getString(claveSombra), fallo: false);
    } catch (_) {
      return (valor: null, fallo: true);
    }
  }

  Future<void> _escribirSombra(String valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(claveSombra, valor);
    } catch (_) {}
  }

  static bool _esUuidValido(String? v) =>
      v != null && _patronUuid.hasMatch(v.trim());

  static final RegExp _patronUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String _capitalizar(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Genera un UUID v4 (RFC 4122) con [Random.secure].
  ///
  /// Se implementa a mano en lugar de añadir el paquete `uuid`: son 15 líneas,
  /// el formato está congelado desde 2005 y una dependencia menos es una
  /// dependencia menos que puede romper el build de una app que se vende por
  /// Facebook Ads.
  static String generarUuidV4() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
    String hex(int desde, int hasta) => b
        .sublist(desde, hasta)
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}