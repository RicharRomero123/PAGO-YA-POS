@Timeout(Duration(minutes: 5))

/// Tests del validador criptográfico puro (firma + parseo del payload).
///
/// ⚠ NO EJECUTADOS: el entorno donde se escribieron no tiene shell disponible
/// (`docs/MOBILE-ARQUITECTURA.md` §9). Correr con `dart test test/licencia`
/// desde `mobile/packages/pagoya_core`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pagoya_core/licencia/clave_publica_embebida.dart';
import 'package:pagoya_core/licencia/license_token.dart';
import 'package:pagoya_core/licencia/license_token_validator.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

import 'vectores.dart';

void main() {
  group('LicenseTokenValidator', () {
    test('acepta un token válido y expone los claims del contrato', () {
      final String token = firmarToken(payloadFacturadorVigente);
      final ResultadoValidacionToken r = validadorDePruebas().validar(token);

      expect(r.esValido, isTrue, reason: r.error);
      final LicenseToken t = r.token!;
      expect(t.licenseId, 'a1b2c3d4-0000-4000-8000-000000000001');
      expect(t.tier, 'facturador');
      expect(
        t.features,
        containsAll(<String>['invoicing', 'cloud_sync', 'multi_site']),
      );
      expect(t.hwid, idDispositivoPropio);
      expect(t.iat, epochEmision);
      expect(t.exp, epochVigente);
      expect(t.sub, '20512345678');
      expect(t.esPerpetua, isFalse);
      expect(t.expiraUtc, DateTime.utc(2026, 3, 31, 12));
    });

    test('exp = 0 se lee como licencia perpetua', () {
      final ResultadoValidacionToken r =
          validadorDePruebas().validar(firmarToken(payloadBasePerpetua));

      expect(r.esValido, isTrue, reason: r.error);
      expect(r.token!.esPerpetua, isTrue);
      expect(r.token!.expiraUtc, isNull);
      expect(r.token!.features, isEmpty);
    });

    test('RECHAZA un token con un byte del payload manipulado', () {
      final String bueno = firmarToken(payloadFacturadorVigente);
      final String malo = manipularUnByteDelPayload(bueno);

      expect(malo, isNot(bueno),
          reason: 'el vector debe estar realmente alterado');

      final ResultadoValidacionToken r = validadorDePruebas().validar(malo);
      expect(r.esValido, isFalse);
      expect(r.token, isNull);
      expect(r.error, contains('Firma'));
    });

    test('RECHAZA un token con un byte de la firma manipulado', () {
      final String malo =
          manipularUnByteDeLaFirma(firmarToken(payloadFacturadorVigente));

      expect(validadorDePruebas().validar(malo).esValido, isFalse);
    });

    test('RECHAZA un token firmado con otra clave privada', () {
      final String ajeno =
          firmarToken(payloadFacturadorVigente, con: parAlterno);

      expect(validadorDePruebas().validar(ajeno).esValido, isFalse);
    });

    test('acepta si alguna de las claves aceptadas verifica (rotación de '
        'llaves)', () {
      final LicenseTokenValidator conAmbas = LicenseTokenValidator.conClaves(
        <RSAPublicKey>[parAlterno.publicKey, parDeClaves.publicKey],
      );

      expect(
        conAmbas.validar(firmarToken(payloadFacturadorVigente)).esValido,
        isTrue,
      );
    });

    test('RECHAZA formatos inválidos sin lanzar', () {
      final LicenseTokenValidator v = validadorDePruebas();

      expect(v.validar(null).esValido, isFalse);
      expect(v.validar('').esValido, isFalse);
      expect(v.validar('   ').esValido, isFalse);
      expect(v.validar('sinpunto').esValido, isFalse);
      expect(v.validar('a.b.c').esValido, isFalse);
      expect(v.validar('!!!.???').esValido, isFalse);
      expect(v.validar('.').esValido, isFalse);
    });

    test('RECHAZA un payload firmado que no es un objeto JSON', () {
      // Firma auténtica, pero el contenido es un array: no cumple el contrato.
      final ResultadoValidacionToken r =
          validadorDePruebas().validar(firmarToken('["no","es","un","objeto"]'));

      expect(r.esValido, isFalse);
      expect(r.error, contains('objeto JSON'));
    });

    test('la firma se calcula sobre los BYTES UTF-8 del payload, no sobre el '
        'string base64url', () {
      // Se firma a mano el string base64url —el error clásico al portar— y se
      // comprueba que el validador lo rechaza.
      final Uint8List payloadBytes =
          Uint8List.fromList(utf8.encode(payloadBasePerpetua));
      final String payloadB64 = codificarBase64Url(payloadBytes);

      final RSASigner firmante =
          RSASigner(SHA256Digest(), '0609608648016503040201')
            ..init(
              true,
              PrivateKeyParameter<RSAPrivateKey>(parDeClaves.privateKey),
            );
      final RSASignature firmaMala = firmante.generateSignature(
        Uint8List.fromList(utf8.encode(payloadB64)),
      );

      final String tokenMal =
          '$payloadB64.${codificarBase64Url(firmaMala.bytes)}';

      expect(validadorDePruebas().validar(tokenMal).esValido, isFalse);
      expect(
        validadorDePruebas().validar(firmarToken(payloadBasePerpetua)).esValido,
        isTrue,
      );
    });
  });

  group('Claims aditivos de asiento (docs/LICENSE-TOKEN.md §4.1)', () {
    test('device_id y device_prefix se parsean cuando vienen', () {
      final LicenseToken t = validadorDePruebas()
          .validar(firmarToken(payloadFacturadorVigente))
          .token!;

      expect(t.deviceId, idAsiento);
      expect(t.devicePrefix, prefijoAsiento);
      expect(t.esTokenDeAsiento, isTrue);
    });

    test('REGLA DURA: un token sin esos claims es válido igualmente', () {
      final ResultadoValidacionToken r =
          validadorDePruebas().validar(firmarToken(payloadBasePerpetua));

      expect(r.esValido, isTrue, reason: r.error);
      expect(r.token!.deviceId, isNull);
      expect(r.token!.devicePrefix, isNull);
      expect(r.token!.esTokenDeAsiento, isFalse);
    });

    test('un claim desconocido se preserva y no rompe el parseo', () {
      final LicenseToken t = validadorDePruebas()
          .validar(firmarToken(payloadConClaimFuturo))
          .token!;

      expect(t.licenseId, 'a1b2c3d4-0000-4000-8000-000000000007');
      expect(t.claimsExtra.containsKey('claim_del_futuro'), isTrue);
    });

    test('el token real emitido por server/PagoYa.Api valida contra la clave '
        'pública embebida', () {
      // Vector de paridad de punta a punta. Ver el doc de vectores.dart para
      // saber cómo rellenarlo.
      final ResultadoValidacionToken r =
          LicenseTokenValidator().validar(tokenRealDelServidor);
      expect(r.esValido, isTrue, reason: r.error);
    },
        skip: tokenRealDelServidor.isEmpty
            ? 'Pega en vectores.dart un token emitido por POST /devices.'
            : null);
  });

  group('base64url', () {
    test('ida y vuelta sin padding, con - y _', () {
      // 0xFB 0xFF 0xFE fuerza los caracteres que difieren del base64 estándar.
      const List<int> bytes = <int>[0xFB, 0xFF, 0xFE, 0x00, 0x10];
      final String codificado = codificarBase64Url(bytes);

      expect(codificado, isNot(contains('=')));
      expect(codificado, isNot(contains('+')));
      expect(codificado, isNot(contains('/')));
      expect(decodificarBase64Url(codificado), bytes);
    });

    test('rechaza una longitud imposible', () {
      expect(() => decodificarBase64Url('A'), throwsFormatException);
    });
  });

  group('parsearClavePublicaPem', () {
    test('parsea la clave pública EMBEBIDA de producción', () {
      final RSAPublicKey clave = parsearClavePublicaPem(pemClavePublicaPagoYa);

      expect(clave.modulus!.bitLength, 2048,
          reason: 'el contrato exige RSA-2048');
      expect(clave.publicExponent, BigInt.from(65537));
    });

    test('parsea una clave generada al vuelo (ida y vuelta DER)', () {
      final RSAPublicKey original = parDeClaves.publicKey;
      final RSAPublicKey parseada =
          parsearClavePublicaPem(clavePublicaAPem(original));

      expect(parseada.modulus, original.modulus);
      expect(parseada.publicExponent, original.publicExponent);
    });

    test('rechaza un PEM que no es SubjectPublicKeyInfo', () {
      expect(
        () => parsearClavePublicaPem(
          '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----',
        ),
        throwsFormatException,
      );
      expect(() => parsearClavePublicaPem(''), throwsFormatException);
    });

    test('el validador por defecto usa la clave embebida sin explotar', () {
      // Construirlo parsea el PEM: si la constante se corrompiera, esto falla.
      expect(LicenseTokenValidator().validar('a.b').esValido, isFalse);
    });
  });
}
