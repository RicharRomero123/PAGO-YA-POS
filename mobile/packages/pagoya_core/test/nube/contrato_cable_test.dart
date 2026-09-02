/// Tests del **contrato del cable** contra el backend existente.
///
/// El backend serializa con `JsonSerializerDefaults.Web`, es decir camelCase.
/// Si alguien renombra un campo aquí, el push deja de guardar y nadie se entera
/// hasta que un dueño llame preguntando por sus ventas. Estos tests son la
/// alarma: fijan la forma exacta de `EventoSyncDto` y `CambioRemotoDto` de
/// `server/PagoYa.Api/Contratos/Dtos.cs`, y los dos 403 que devuelve el backend.
library;

import 'dart:convert';

import 'package:pagoya_core/nube/nube.dart';
import 'package:test/test.dart';

void main() {
  group('EventoSyncLocal -> POST /sync/push', () {
    test('serializa con los nombres exactos de EventoSyncDto', () {
      final e = EventoSyncLocal(
        id: 'a1b2c3d4-0000-4000-8000-000000000001',
        entidad: 'venta',
        entidadId: 'b1b2c3d4-0000-4000-8000-000000000002',
        operacion: 'INSERT',
        payloadJson: '{"Total":25.4}',
        intentos: 2,
        origenCajaId: 'M01',
        creadoUtc: DateTime.utc(2026, 3, 15, 10, 30),
      );

      final json = e.aJson();

      expect(json.keys.toSet(), {
        'id',
        'entidad',
        'entidadId',
        'operacion',
        'payloadJson',
        'intentos',
        'origenCajaId',
        'creadoUtc',
      });
      expect(json['entidadId'], e.entidadId);
      expect(json['origenCajaId'], 'M01');
      expect(json['payloadJson'], isA<String>(),
          reason: 'el snapshot viaja como STRING, no como objeto anidado');
      expect(json['creadoUtc'], '2026-03-15T10:30:00.000Z');
    });

    test('el cuerpo del push es {"eventos": [...]}', () {
      final cuerpo = {
        'eventos': [
          EventoSyncLocal(
            id: 'x',
            entidad: 'caja',
            entidadId: 'y',
            operacion: 'UPDATE',
            payloadJson: '{}',
            intentos: 0,
            origenCajaId: 'M01',
            creadoUtc: DateTime.utc(2026),
          ).aJson()
        ]
      };

      final texto = jsonEncode(cuerpo);

      expect(texto, contains('"eventos"'));
      expect(jsonDecode(texto), isA<Map<String, dynamic>>());
    });
  });

  group('GET /sync/pull -> CambioRemoto', () {
    test('lee la forma camelCase de CambioRemotoDto', () {
      final json = {
        'entidad': 'producto',
        'entidadId': 'c1b2c3d4-0000-4000-8000-000000000003',
        'operacion': 'UPDATE',
        'payloadJson': '{"Nombre":"Arroz","ActualizadoUtc":"2026-03-15T10:30:00Z"}',
        'actualizadoUtc': '2026-03-15T10:30:00Z',
        'origenCajaId': 'C01',
      };

      final c = CambioRemoto.desdeJson(json);

      expect(c.entidad, 'producto');
      expect(c.entidadId, 'c1b2c3d4-0000-4000-8000-000000000003');
      expect(c.origenCajaId, 'C01');
      expect(c.actualizadoUtc, DateTime.utc(2026, 3, 15, 10, 30));
      expect(c.actualizadoUtc.isUtc, isTrue,
          reason: 'el LWW compara en UTC o compara mal');
    });

    test('sin marca de actualización cae a epoch: pierde el LWW, no lo gana', () {
      // Un cambio sin `actualizadoUtc` legible NO puede pisar un dato local
      // bueno. El sesgo seguro es que pierda siempre.
      final c = CambioRemoto.desdeJson({
        'entidad': 'venta',
        'entidadId': 'z',
        'operacion': 'DELETE',
        'payloadJson': '{}',
        'actualizadoUtc': 'basura',
        'origenCajaId': 'C01',
      });

      expect(c.actualizadoUtc.millisecondsSinceEpoch, 0);
    });

    test('tolera campos ausentes sin reventar', () {
      final c = CambioRemoto.desdeJson(const {'entidad': 'mesa'});

      expect(c.entidad, 'mesa');
      expect(c.entidadId, '');
      expect(c.payloadJson, '{}');
      expect(c.origenCajaId, '');
    });

    test('acepta payloadJson ya deserializado y lo vuelve a serializar', () {
      final c = CambioRemoto.desdeJson({
        'entidad': 'venta',
        'entidadId': 'z',
        'operacion': 'INSERT',
        'payloadJson': {'Total': 10},
        'actualizadoUtc': '2026-01-01T00:00:00Z',
        'origenCajaId': 'C01',
      });

      expect(jsonDecode(c.payloadJson), {'Total': 10});
    });
  });

  group('Flag de licencia', () {
    test('el nombre canónico es el mismo string que en C# y en el token', () {
      // `Flags.CloudSync` de PagoYa.Core y `docs/LICENSE-TOKEN.md` §5.
      expect(flagCloudSync, 'cloud_sync');
    });
  });

  group('Códigos de error (server/README.md §10)', () {
    test('los strings son exactamente los publicados', () {
      // Espejo de `PagoYa.Api.Contratos.CodigosError`. Un código publicado no
      // cambia de significado ni se recicla: si esto falla, alguien rompió el
      // contrato en un lado y el otro está ramificando mal.
      expect(CodigosErrorSync.tokenAusente, 'token_ausente');
      expect(CodigosErrorSync.tokenInvalido, 'token_invalido');
      expect(CodigosErrorSync.tokenExpirado, 'token_expirado');
      expect(CodigosErrorSync.licenciaNoIdentificada, 'licencia_no_identificada');
      expect(CodigosErrorSync.sinFlagCloudSync, 'sin_flag_cloud_sync');
      expect(CodigosErrorSync.asientoRevocado, 'asiento_revocado');
    });

    test('los dos 403 son motivos distintos y ambos paran los reintentos', () {
      expect(MotivoFalloSync.sinPermisoCloud,
          isNot(MotivoFalloSync.dispositivoRevocado));
      expect(esMotivoBloqueante(MotivoFalloSync.sinPermisoCloud), isTrue);
      expect(esMotivoBloqueante(MotivoFalloSync.dispositivoRevocado), isTrue);
      expect(esMotivoBloqueante(MotivoFalloSync.tokenInvalido), isTrue);
    });

    test('expirado ≠ inválido: uno se renueva, el otro se re-vincula', () {
      expect(MotivoFalloSync.tokenExpirado, isNot(MotivoFalloSync.tokenInvalido));
      // Vencer se arregla solo (RevalidadorLicencia): no bloquea el ciclo.
      expect(esMotivoBloqueante(MotivoFalloSync.tokenExpirado), isFalse);
      // Sin red y server caído tampoco: es lo normal en una bodega.
      expect(esMotivoBloqueante(MotivoFalloSync.sinRed), isFalse);
      expect(esMotivoBloqueante(MotivoFalloSync.servidor), isFalse);
    });

    test('ningún 4xx de licencia es reintentable a nivel transporte', () {
      expect(esReintentable(TipoFalloSync.sinPermiso), isFalse);
      expect(esReintentable(TipoFalloSync.asientoRevocado), isFalse);
      expect(esReintentable(TipoFalloSync.autenticacion), isFalse);
      expect(esReintentable(TipoFalloSync.tokenExpirado), isFalse,
          reason: 'reintentar YA no sirve; el reintento lo agenda el planificador');
      expect(esReintentable(TipoFalloSync.red), isTrue);
      expect(esReintentable(TipoFalloSync.servidor), isTrue);
      expect(esReintentable(TipoFalloSync.limite), isTrue);
    });
  });
}
