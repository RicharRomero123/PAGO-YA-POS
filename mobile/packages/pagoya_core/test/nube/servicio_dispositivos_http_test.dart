/// Tests del cliente HTTP de seats (`POST /devices`, `DELETE /devices/{id}`).
///
/// Lo que se protege aquí, por orden de importancia:
///   1. **`codigo` llega intacto** a `ResultadoVinculacion.codigo`. Sin esto,
///      `codigoDeVinculacion()` devuelve null y TODO el flujo de asientos cae en
///      el parseo de subcadenas — que es justo lo que el campo vino a matar.
///   2. Un fallo de red **lanza** (los llamadores lo traducen a "reintenta"),
///      mientras que un 4xx **devuelve** un resultado. Confundirlos convierte un
///      sótano sin señal en "tu licencia tiene un problema".
///   3. La forma exacta del cuerpo que espera `VincularDispositivoRequest`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// `contratos.dart` reexporta `nube.dart`, así que de aquí salen tanto
// `ServicioDispositivos`/`ResultadoVinculacion` (mobile-lead) como
// `crearServicioDispositivos` y los lectores de error (flutter-sync).
import 'package:pagoya_core/nube/contratos.dart';
import 'package:test/test.dart';

/// Adaptador que responde lo que se le diga, o revienta como lo haría dio.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.estado, this.cuerpo);

  int estado;
  Map<String, dynamic> cuerpo;

  /// Si se pone, `fetch` lanza en vez de responder (simula caída de red).
  DioExceptionType? fallaDeRed;

  RequestOptions? ultimaPeticion;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ultimaPeticion = options;
    final falla = fallaDeRed;
    if (falla != null) {
      throw DioException(requestOptions: options, type: falla);
    }
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({ServicioDispositivos servicio, _AdaptadorFalso adaptador}) _armar({
  int estado = 201,
  Map<String, dynamic> cuerpo = const {'token': 'tok.firmado'},
}) {
  final adaptador = _AdaptadorFalso(estado, Map<String, dynamic>.from(cuerpo));
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.pagoya.test/',
    validateStatus: (_) => true,
    responseType: ResponseType.json,
  ))
    ..httpClientAdapter = adaptador;

  return (
    servicio: crearServicioDispositivos(
        urlBase: 'https://api.pagoya.test', dio: dio),
    adaptador: adaptador,
  );
}

Future<ResultadoVinculacion> _vincular(ServicioDispositivos s) => s.vincular(
      tokenLicencia: 'PAGOYA-S4WN-QGC5-TPYN-NY6S',
      idDispositivo: 'android-abc123',
      nombreDispositivo: 'Celular de Juan',
      plataforma: 'android',
    );

void main() {
  group('POST /devices — propagación de `codigo` (lo que desbloquea a licencia)',
      () {
    test('un error con codigo llega INTACTO en ResultadoVinculacion.codigo',
        () async {
      final a = _armar(estado: 409, cuerpo: {
        'error': 'Límite de dispositivos alcanzado (3/3).',
        'codigo': 'cupo_dispositivos_lleno',
      });

      final r = await _vincular(a.servicio);

      expect(r.exito, isFalse);
      expect(r.codigo, 'cupo_dispositivos_lleno');
      expect(r.mensaje, 'Límite de dispositivos alcanzado (3/3).');
    });

    test('cada código del catálogo de seats se propaga tal cual', () async {
      // No se traduce, no se normaliza, no se interpreta: se propaga. Quien
      // clasifica es `clasificarFalloVinculacion`.
      for (final codigo in const [
        'clave_no_encontrada',
        'licencia_suspendida',
        'licencia_revocada',
        'cupo_dispositivos_lleno',
        'dispositivo_ya_es_principal',
        'prefijos_agotados',
        'device_id_requerido',
        'token_expirado',
        'token_invalido',
        'asiento_revocado',
      ]) {
        final a = _armar(estado: 409, cuerpo: {'error': 'x', 'codigo': codigo});

        expect((await _vincular(a.servicio)).codigo, codigo,
            reason: 'el código $codigo se perdió por el camino');
      }
    });

    test('un código que este cliente aún no conoce también se propaga',
        () async {
      // La regla del catálogo es que se AGREGAN códigos. Un cliente viejo no
      // puede tragárselos: los pasa y deja que la clasificación diga
      // "desconocido" y muestre el texto del backend.
      final a = _armar(estado: 409, cuerpo: {
        'error': 'Algo nuevo pasó.',
        'codigo': 'condicion_inventada_en_el_futuro',
      });

      expect((await _vincular(a.servicio)).codigo,
          'condicion_inventada_en_el_futuro');
    });

    test('sin `codigo` queda null, que es la señal de "usa compatibilidad"',
        () async {
      final a = _armar(estado: 409, cuerpo: {'error': 'Server viejo.'});

      final r = await _vincular(a.servicio);

      expect(r.codigo, isNull);
      expect(r.mensaje, 'Server viejo.');
    });

    test('un `codigo` vacío o en blanco cuenta como ausente', () async {
      final a = _armar(estado: 409, cuerpo: {'error': 'x', 'codigo': '   '});

      expect((await _vincular(a.servicio)).codigo, isNull);
    });
  });

  group('POST /devices — camino de éxito', () {
    test('devuelve el token firmado', () async {
      final a = _armar(estado: 201, cuerpo: {
        'token': 'payload.firma',
        'tier': 'cloud',
        'features': ['cloud_sync'],
        'expUnix': 1790000000,
        'deviceId': '6f1c2f7a-9b21-4a0e-9d6e-9a2b7f0c1d33',
        'devicePrefix': 'M01',
      });

      final r = await _vincular(a.servicio);

      expect(r.exito, isTrue);
      expect(r.tokenFirmado, 'payload.firma');
      expect(r.codigo, isNull, reason: 'el camino feliz no trae código');
    });

    test('un 2xx sin token no es éxito, pero tampoco una excepción', () async {
      final a = _armar(estado: 200, cuerpo: {'tier': 'cloud'});

      final r = await _vincular(a.servicio);

      expect(r.exito, isFalse);
      expect(r.tokenFirmado, isNull);
      expect(r.mensaje, isNotNull);
    });

    test('manda el cuerpo con los nombres de VincularDispositivoRequest',
        () async {
      final a = _armar();

      await _vincular(a.servicio);

      final datos = a.adaptador.ultimaPeticion!.data as Map<String, dynamic>;
      expect(datos['licenseKey'], 'PAGOYA-S4WN-QGC5-TPYN-NY6S',
          reason: 'el parámetro se llama tokenLicencia pero ES la clave');
      expect(datos['deviceId'], 'android-abc123');
      expect(datos['nombre'], 'Celular de Juan');
      expect(datos['plataforma'], 'android');
      expect(a.adaptador.ultimaPeticion!.path, 'devices');
    });
  });

  group('Red vs respuesta de error', () {
    test('sin conexión LANZA (los llamadores lo leen como "reintenta")',
        () async {
      final a = _armar();
      a.adaptador.fallaDeRed = DioExceptionType.connectionError;

      expect(_vincular(a.servicio), throwsA(isA<ExcepcionRedDispositivos>()));
    });

    test('timeout LANZA', () async {
      final a = _armar();
      a.adaptador.fallaDeRed = DioExceptionType.connectionTimeout;

      expect(_vincular(a.servicio), throwsA(isA<ExcepcionRedDispositivos>()));
    });

    test('un 5xx LANZA: el servidor está caído, no la licencia', () async {
      final a = _armar(estado: 503, cuerpo: {'error': 'mantenimiento'});

      expect(_vincular(a.servicio), throwsA(isA<ExcepcionRedDispositivos>()));
    });

    test('un 4xx NO lanza: es información que el dueño tiene que ver',
        () async {
      final a = _armar(estado: 404, cuerpo: {
        'error': 'Clave de licencia no encontrada.',
        'codigo': 'clave_no_encontrada',
      });

      final r = await _vincular(a.servicio);

      expect(r.exito, isFalse);
      expect(r.codigo, 'clave_no_encontrada');
    });
  });

  group('DELETE /devices/{id}', () {
    test('manda la clave en la cabecera, nunca en la query', () async {
      // Las URLs acaban en logs de acceso y en proxies; una clave de licencia
      // en la query es una filtración con fecha.
      final a = _armar(estado: 200, cuerpo: {'revocado': true});

      await a.servicio
          .revocar(tokenLicencia: 'PAGOYA-CLAVE', idAsiento: 'seat-guid');

      final peticion = a.adaptador.ultimaPeticion!;
      expect(peticion.headers['X-License-Key'], 'PAGOYA-CLAVE');
      expect(peticion.path, 'devices/seat-guid');
      expect(peticion.uri.query, isNot(contains('PAGOYA-CLAVE')));
    });

    test('lee el campo `revocado` de la respuesta', () async {
      final a = _armar(estado: 200, cuerpo: {
        'deviceId': 'x',
        'revocado': true,
        'dispositivosActivos': 1,
        'maxDispositivos': 3,
      });

      expect(
        await a.servicio.revocar(tokenLicencia: 'k', idAsiento: 'seat-guid'),
        isTrue,
      );
    });

    test('un 403 devuelve false, no lanza', () async {
      final a = _armar(estado: 403, cuerpo: {
        'error': 'La clave es de otra licencia.',
        'codigo': 'clave_no_corresponde',
      });

      expect(
        await a.servicio.revocar(tokenLicencia: 'k', idAsiento: 'seat-guid'),
        isFalse,
      );
    });

    test('sin red LANZA', () async {
      final a = _armar(estado: 200, cuerpo: {'revocado': true});
      a.adaptador.fallaDeRed = DioExceptionType.connectionError;

      expect(
        a.servicio.revocar(tokenLicencia: 'k', idAsiento: 'seat-guid'),
        throwsA(isA<ExcepcionRedDispositivos>()),
      );
    });
  });

  group('Lectura compartida del cuerpo de error', () {
    test('es la misma que usa el transporte de sync', () {
      // Los dos clientes leen `codigo`/`error` con las MISMAS funciones, para
      // que no diverjan en cuanto uno añada un trim() y el otro no.
      expect(leerCodigoErrorRemoto({'codigo': ' asiento_revocado '}),
          'asiento_revocado');
      expect(leerCodigoErrorRemoto({'codigo': ''}), isNull);
      expect(leerCodigoErrorRemoto({'error': 'x'}), isNull);
      expect(leerCodigoErrorRemoto('no soy un mapa'), isNull);
      expect(leerCodigoErrorRemoto(null), isNull);

      expect(leerMensajeErrorRemoto({'error': 'texto'}), 'texto');
      expect(leerMensajeErrorRemoto({'codigo': 'x'}), '');
    });
  });
}
