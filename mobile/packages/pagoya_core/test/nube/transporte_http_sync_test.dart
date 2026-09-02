/// Tests del transporte HTTP contra un adaptador dio simulado.
///
/// Aquí se verifica lo único que el transporte decide por su cuenta y que el
/// resto de los tests no puede alcanzar (porque usan el transporte en memoria):
///   1. que el pull manda `cursor` y `origen`,
///   2. que los errores se ramifican por `ErrorResponse.codigo` y NO por texto,
///   3. que la ruta de compatibilidad (server sin `codigo`) sigue funcionando.
///
/// Si un renombrado del catálogo de §10 rompe el mapeo, salta aquí y no en la
/// bodega de un cliente.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pagoya_core/nube/nube.dart';
import 'package:test/test.dart';

/// Adaptador que responde lo que se le diga y guarda la petición recibida.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.estado, this.cuerpo);

  int estado;
  Map<String, dynamic> cuerpo;

  RequestOptions? ultimaPeticion;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ultimaPeticion = options;
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

({TransporteHttpSync transporte, _AdaptadorFalso adaptador}) _armar({
  int estado = 200,
  Map<String, dynamic> cuerpo = const {'aceptados': <String>[]},
  String origen = 'M01',
}) {
  final adaptador = _AdaptadorFalso(estado, Map<String, dynamic>.from(cuerpo));
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.pagoya.test/',
    validateStatus: (_) => true,
    responseType: ResponseType.json,
  ))
    ..httpClientAdapter = adaptador;

  final transporte = TransporteHttpSync(
    // Sin reintentos: los fallos reintentables no deben meter esperas reales.
    opciones: OpcionesSync(
      origenCajaId: origen,
      urlBase: 'https://api.pagoya.test',
      tokenLicencia: 'token-firmado',
      maxReintentosHttp: 0,
    ),
    dio: dio,
  );
  return (transporte: transporte, adaptador: adaptador);
}

EventoSyncLocal _evento() => EventoSyncLocal(
      id: 'evt-1',
      entidad: EntidadesSync.venta,
      entidadId: 'ent-1',
      operacion: 'INSERT',
      payloadJson: '{}',
      intentos: 0,
      origenCajaId: 'M01',
      creadoUtc: DateTime.utc(2026),
    );

void main() {
  group('Forma de la petición', () {
    test('el pull manda cursor y origen', () async {
      final a = _armar(cuerpo: {'cambios': <dynamic>[], 'cursor': '7'});

      await a.transporte.descargarCambios('7');

      final q = a.adaptador.ultimaPeticion!.queryParameters;
      expect(q['cursor'], '7');
      expect(q['origen'], 'M01',
          reason: 'sin `origen` el server no filtra el eco');
      expect(a.adaptador.ultimaPeticion!.path, 'sync/pull');
    });

    test('sin cursor previo se manda solo origen', () async {
      final a = _armar(cuerpo: {'cambios': <dynamic>[], 'cursor': '0'});

      await a.transporte.descargarCambios(null);

      final q = a.adaptador.ultimaPeticion!.queryParameters;
      expect(q.containsKey('cursor'), isFalse);
      expect(q['origen'], 'M01');
    });

    test('sin origen configurado no se manda el parámetro', () async {
      final a = _armar(
        cuerpo: {'cambios': <dynamic>[], 'cursor': '0'},
        origen: '   ',
      );

      await a.transporte.descargarCambios('3');

      expect(a.adaptador.ultimaPeticion!.queryParameters.containsKey('origen'),
          isFalse);
    });

    test('el Bearer va en la cabecera', () async {
      final a = _armar();

      await a.transporte.enviarLote([_evento()]);

      expect(a.adaptador.ultimaPeticion!.headers['Authorization'],
          'Bearer token-firmado');
    });
  });

  group('Ramificación por `codigo` (contrato §10)', () {
    Future<TipoFalloSync?> tipoDe(int estado, Map<String, dynamic> cuerpo) async {
      final a = _armar(estado: estado, cuerpo: cuerpo);
      final r = await a.transporte.enviarLote([_evento()]);
      return r.tipoFallo;
    }

    test('403 sin_flag_cloud_sync -> sinPermiso (upsell)', () async {
      expect(
        await tipoDe(403, {
          'error': 'La licencia no habilita la sincronización en la nube.',
          'codigo': CodigosErrorSync.sinFlagCloudSync,
        }),
        TipoFalloSync.sinPermiso,
      );
    });

    test('403 asiento_revocado -> asientoRevocado (re-vincular)', () async {
      expect(
        await tipoDe(403, {
          'error': 'El dispositivo fue revocado para esta licencia.',
          'codigo': CodigosErrorSync.asientoRevocado,
        }),
        TipoFalloSync.asientoRevocado,
      );
    });

    test('401 token_expirado -> tokenExpirado (revalidar, no re-vincular)',
        () async {
      expect(
        await tipoDe(401, {
          'error': 'El token venció.',
          'codigo': CodigosErrorSync.tokenExpirado,
        }),
        TipoFalloSync.tokenExpirado,
      );
    });

    test('401 token_invalido -> autenticacion (re-vincular)', () async {
      expect(
        await tipoDe(401, {
          'error': 'Firma inválida.',
          'codigo': CodigosErrorSync.tokenInvalido,
        }),
        TipoFalloSync.autenticacion,
      );
    });

    test('401 token_ausente y licencia_no_identificada caen en autenticacion',
        () async {
      expect(await tipoDe(401, {'error': 'x', 'codigo': CodigosErrorSync.tokenAusente}),
          TipoFalloSync.autenticacion);
      expect(
          await tipoDe(401,
              {'error': 'x', 'codigo': CodigosErrorSync.licenciaNoIdentificada}),
          TipoFalloSync.autenticacion);
    });

    test('el CÓDIGO manda sobre el texto, aunque el texto diga otra cosa',
        () async {
      // Este es el punto entero del cambio: el texto es para el usuario y puede
      // reescribirse; si alguien lo traduce, el cliente no puede cambiar de rama.
      expect(
        await tipoDe(403, {
          'error': 'El dispositivo fue revocado para esta licencia.',
          'codigo': CodigosErrorSync.sinFlagCloudSync,
        }),
        TipoFalloSync.sinPermiso,
        reason: 'el texto menciona "dispositivo" pero el código dice upsell',
      );
    });

    test('un código fuera del catálogo de sync cae al status HTTP', () async {
      expect(
        await tipoDe(409, {'error': 'x', 'codigo': 'cupo_dispositivos_lleno'}),
        TipoFalloSync.rechazoPermanente,
      );
    });
  });

  group('Compatibilidad con servers sin `codigo`', () {
    Future<TipoFalloSync?> tipoDe(int estado, String texto) async {
      final a = _armar(estado: estado, cuerpo: {'error': texto});
      final r = await a.transporte.enviarLote([_evento()]);
      return r.tipoFallo;
    }

    test('403 "dispositivo revocado" por texto', () async {
      expect(await tipoDe(403, 'El dispositivo fue revocado para esta licencia.'),
          TipoFalloSync.asientoRevocado);
    });

    test('403 ambiguo cae al caso del flag (upsell no rompe nada de más)',
        () async {
      expect(await tipoDe(403, 'La licencia no habilita la nube.'),
          TipoFalloSync.sinPermiso);
    });

    test('401 "expirado" por texto', () async {
      expect(await tipoDe(401, 'El token expiró.'), TipoFalloSync.tokenExpirado);
    });

    test('401 genérico -> autenticacion', () async {
      expect(await tipoDe(401, 'Token inválido.'), TipoFalloSync.autenticacion);
    });
  });

  group('Respuestas correctas', () {
    test('el push lee aceptados y entidadesDesconocidas', () async {
      final a = _armar(cuerpo: {
        'aceptados': ['EVT-1'],
        'entidadesDesconocidas': ['comanda_v2'],
      });

      final r = await a.transporte.enviarLote([_evento()]);

      expect(r.ok, isTrue);
      expect(r.aceptadosIds, ['evt-1'],
          reason: 'los ids se normalizan a minúsculas para casar con el outbox');
      expect(r.entidadesDesconocidas, ['comanda_v2']);
    });

    test('el push sin entidadesDesconocidas no revienta', () async {
      final a = _armar(cuerpo: {'aceptados': <String>[]});

      final r = await a.transporte.enviarLote([_evento()]);

      expect(r.ok, isTrue);
      expect(r.entidadesDesconocidas, isEmpty);
    });

    test('el pull lee cambios y cursor', () async {
      final a = _armar(cuerpo: {
        'cambios': [
          {
            'entidad': 'venta',
            'entidadId': 'e1',
            'operacion': 'INSERT',
            'payloadJson': '{}',
            'actualizadoUtc': '2026-03-15T10:30:00Z',
            'origenCajaId': 'C01',
          }
        ],
        'cursor': '42',
      });

      final p = await a.transporte.descargarCambios('41');

      expect(p.ok, isTrue);
      expect(p.cursor, '42');
      expect(p.cambios, hasLength(1));
      expect(p.cambios.first.origenCajaId, 'C01');
    });

    test('un 200 sin "aceptados" no marca nada como enviado', () async {
      // Preferimos reenviar (el backend deduplica) antes que dar por subido algo
      // que no sabemos si llegó.
      final a = _armar(cuerpo: {'algo': 'raro'});

      final r = await a.transporte.enviarLote([_evento()]);

      expect(r.ok, isFalse);
      expect(r.tipoFallo, TipoFalloSync.respuestaInvalida);
    });

    test('un lote vacío no llega a la red', () async {
      final a = _armar();

      final r = await a.transporte.enviarLote(const []);

      expect(r.ok, isTrue);
      expect(a.adaptador.ultimaPeticion, isNull);
    });
  });

  group('Sonda de internet real', () {
    test('un /health con JSON del backend cuenta como internet', () async {
      final a = _armar(cuerpo: {'servicio': 'PagoYa', 'estado': 'ok'});

      expect(await a.transporte.hayInternet(), isTrue);
    });

    test('un portal cautivo que devuelve 200 con otra cosa NO cuenta', () async {
      final a = _armar(cuerpo: {'login': 'wifi-del-mercado'});

      expect(await a.transporte.hayInternet(), isFalse);
    });

    test('un 401 del propio backend sí prueba que hay ruta', () async {
      final a = _armar(estado: 401, cuerpo: {'error': 'x'});

      expect(await a.transporte.hayInternet(), isTrue);
    });
  });
}
