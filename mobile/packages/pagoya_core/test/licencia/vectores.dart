/// Vectores fijos y utilidades para los tests de licenciamiento.
///
/// ## Por qué el par de claves se genera aquí y no está hardcodeado
///
/// Para probar el camino feliz hace falta una firma **auténtica**, y la clave
/// privada de PagoYa vive solo en `server/PagoYa.Api`, fuera de git
/// (`docs/SEGURIDAD.md` §6). Así que los tests generan su propio par RSA-2048
/// con pointycastle **sembrado con una semilla fija** → el par es determinista
/// y reproducible, y los tokens que produce son vectores estables.
///
/// Los **payloads** sí son literales fijos byte a byte: son el vector real que
/// se firma, y coinciden en forma con lo que emite `EmisorTokens` del server.
///
/// ## Vector con un token real del servidor
///
/// [tokenRealDelServidor] está vacío a propósito. Para cerrar la paridad de
/// punta a punta (`docs/MOBILE-ARQUITECTURA.md` §8):
///
/// ```bash
/// curl -X POST http://localhost:5080/licenses -H "X-Admin-ApiKey: …" \
///   -H "Content-Type: application/json" \
///   -d '{"tier":"cloud"}'
/// curl -X POST http://localhost:5080/devices -H "Content-Type: application/json" \
///   -d '{"licenseKey":"PAGOYA-…","deviceId":"0b3f1e2a-7c4d-4f8b-9a10-5e6d7c8b9a01",
///        "plataforma":"android","nombre":"Celular de pruebas"}'
/// ```
///
/// y pegar el `token` de la respuesta en la constante. El test que lo consume se
/// salta solo mientras esté vacía.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pagoya_core/licencia/license_token_validator.dart';
import 'package:pointycastle/export.dart';

// ============================================================================
//  Instantes de referencia (todos UTC, epoch en segundos)
// ============================================================================

/// "Ahora" de referencia de los tests: 2026-03-01T12:00:00Z.
const int epochAhora = 1772366400;

/// Emisión: 30 días antes de [epochAhora].
const int epochEmision = 1769774400;

/// Expiración vigente: 30 días después de [epochAhora].
const int epochVigente = 1774958400;

/// Expiró hace 3 días → **dentro** del grace period de 7 días.
const int epochExpiradoEnGracia = 1772107200;

/// Expiró hace 10 días → **fuera** del grace period de 7 días.
const int epochExpiradoFueraGracia = 1771502400;

/// Reloj fijo de los tests.
DateTime get ahoraFija =>
    DateTime.fromMillisecondsSinceEpoch(epochAhora * 1000, isUtc: true);

/// UUID v4 de este dispositivo (el asiento). No es un fingerprint de hardware:
/// se genera en el primer arranque y vive en `flutter_secure_storage`.
const String idDispositivoPropio = '0b3f1e2a-7c4d-4f8b-9a10-5e6d7c8b9a01';

/// Id de **otro** dispositivo.
const String idDispositivoAjeno = '11112222-3333-4444-8555-666677778888';

/// Id del asiento (fila `Devices`) — el `{id}` de `DELETE /devices/{id}`.
const String idAsiento = '6f1c2f7a-9b21-4a0e-9d6e-9a2b7f0c1d33';

/// Prefijo que asigna el server a este móvil.
const String prefijoAsiento = 'M01';

// ============================================================================
//  Payloads fijos (JSON compacto, tal como lo serializa el emisor)
// ============================================================================

/// Facturador Pro vigente, token de **asiento**: trae `device_id` y
/// `device_prefix` (docs/LICENSE-TOKEN.md §4.1).
const String payloadFacturadorVigente =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000001",'
    '"tier":"facturador",'
    '"features":["invoicing","cloud_sync","multi_site"],'
    '"hwid":"$idDispositivoPropio",'
    '"iat":$epochEmision,'
    '"exp":$epochVigente,'
    '"sub":"20512345678",'
    '"device_id":"$idAsiento",'
    '"device_prefix":"$prefijoAsiento"}';

/// Base perpetua (`exp: 0`, sin features). **Sin** los claims de asiento: es un
/// token de los que ya están en campo y debe seguir siendo válido.
const String payloadBasePerpetua =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000002",'
    '"tier":"base",'
    '"features":[],'
    '"hwid":"$idDispositivoPropio",'
    '"iat":$epochEmision,'
    '"exp":0}';

/// Cloud expirada hace 3 días → debe seguir operando en gracia.
const String payloadCloudEnGracia =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000003",'
    '"tier":"cloud",'
    '"features":["cloud_sync","multi_site"],'
    '"hwid":"$idDispositivoPropio",'
    '"iat":$epochEmision,'
    '"exp":$epochExpiradoEnGracia,'
    '"device_id":"$idAsiento",'
    '"device_prefix":"$prefijoAsiento"}';

/// Cloud expirada hace 10 días → gracia vencida, degrada a Base.
const String payloadCloudFueraDeGracia =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000004",'
    '"tier":"cloud",'
    '"features":["cloud_sync","multi_site"],'
    '"hwid":"$idDispositivoPropio",'
    '"iat":$epochEmision,'
    '"exp":$epochExpiradoFueraGracia}';

/// Facturador vigente pero emitida para **otro** dispositivo.
const String payloadOtroDispositivo =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000005",'
    '"tier":"facturador",'
    '"features":["invoicing","cloud_sync","multi_site"],'
    '"hwid":"$idDispositivoAjeno",'
    '"iat":$epochEmision,'
    '"exp":$epochVigente,'
    '"device_id":"aaaabbbb-cccc-4ddd-8eee-ffff00001111",'
    '"device_prefix":"M02"}';

/// Licencia **no atada** a ningún equipo (`hwid` vacío): valida en cualquier
/// dispositivo, igual que en el escritorio.
const String payloadSinVinculo =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000006",'
    '"tier":"cloud",'
    '"features":["cloud_sync"],'
    '"hwid":"",'
    '"iat":$epochEmision,'
    '"exp":$epochVigente}';

/// Token con un claim **desconocido**: la ruta de compatibilidad hacia adelante
/// exige que se ignore sin romper (docs/LICENSE-TOKEN.md §4.1).
const String payloadConClaimFuturo =
    '{"license_id":"a1b2c3d4-0000-4000-8000-000000000007",'
    '"tier":"cloud",'
    '"features":["cloud_sync"],'
    '"hwid":"$idDispositivoPropio",'
    '"iat":$epochEmision,'
    '"exp":$epochVigente,'
    '"claim_del_futuro":{"algo":42}}';

/// Token emitido por `server/PagoYa.Api` con la clave privada de DEV. Vacío
/// mientras nadie lo pegue; el test que lo usa se salta solo.
const String tokenRealDelServidor = '';

// ============================================================================
//  Par de claves determinista + firma
// ============================================================================

/// Semilla fija de 32 bytes: hace [parDeClaves] reproducible entre corridas.
final Uint8List semillaFija =
    Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + 13) & 0xFF));

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _par;

/// Par RSA-2048 de pruebas. Se genera una sola vez por proceso (la generación
/// de claves RSA en Dart puro tarda varios segundos).
AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> get parDeClaves =>
    _par ??= _generarPar(semillaFija);

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _parAlterno;

/// Segundo par, para simular un token firmado con **otra** clave (un atacante,
/// o una clave rotada que ya no se acepta).
AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> get parAlterno =>
    _parAlterno ??= _generarPar(
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 11 + 3) & 0xFF)),
    );

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generarPar(Uint8List semilla) {
  final FortunaRandom aleatorio = FortunaRandom()..seed(KeyParameter(semilla));

  final RSAKeyGenerator generador = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        aleatorio,
      ),
    );

  final AsymmetricKeyPair<PublicKey, PrivateKey> par =
      generador.generateKeyPair();
  return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
    par.publicKey as RSAPublicKey,
    par.privateKey as RSAPrivateKey,
  );
}

/// Firma [payloadJson] (bytes UTF-8 crudos) y devuelve el token completo
/// `base64url(payload).base64url(firma)`.
String firmarToken(
  String payloadJson, {
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? con,
}) {
  final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> par = con ?? parDeClaves;
  final Uint8List payloadBytes = Uint8List.fromList(utf8.encode(payloadJson));

  final RSASigner firmante = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(par.privateKey));

  final RSASignature firma = firmante.generateSignature(payloadBytes);

  return '${codificarBase64Url(payloadBytes)}.${codificarBase64Url(firma.bytes)}';
}

/// Validador atado al par de pruebas.
LicenseTokenValidator validadorDePruebas() =>
    LicenseTokenValidator.conClaves(<RSAPublicKey>[parDeClaves.publicKey]);

/// Token con **un bit del payload alterado**, manteniendo la firma original.
/// Es el vector de manipulación: debe ser rechazado.
String manipularUnByteDelPayload(String token, {int indice = 12}) {
  final List<String> partes = token.split('.');
  final Uint8List payload = decodificarBase64Url(partes[0]);
  final Uint8List alterado = Uint8List.fromList(payload);
  alterado[indice % alterado.length] ^= 0x01;
  return '${codificarBase64Url(alterado)}.${partes[1]}';
}

/// Token con **un bit de la firma alterado**.
String manipularUnByteDeLaFirma(String token, {int indice = 5}) {
  final List<String> partes = token.split('.');
  final Uint8List firma = decodificarBase64Url(partes[1]);
  final Uint8List alterada = Uint8List.fromList(firma);
  alterada[indice % alterada.length] ^= 0x01;
  return '${partes[0]}.${codificarBase64Url(alterada)}';
}

// ============================================================================
//  Codificador DER mínimo: RSAPublicKey → PEM SubjectPublicKeyInfo
// ============================================================================

/// AlgorithmIdentifier completo de `rsaEncryption` con parámetros NULL.
const List<int> _algorithmIdentifierRsa = <int>[
  0x30, 0x0D, //
  0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, //
  0x05, 0x00,
];

/// Serializa una [RSAPublicKey] a PEM `SubjectPublicKeyInfo`. Sirve para probar
/// `parsearClavePublicaPem` contra una clave real generada al vuelo.
String clavePublicaAPem(RSAPublicKey clave) {
  final List<int> rsaPublicKey = _tlv(0x30, <int>[
    ..._tlv(0x02, _enteroDer(clave.modulus!)),
    ..._tlv(0x02, _enteroDer(clave.publicExponent!)),
  ]);

  final List<int> spki = _tlv(0x30, <int>[
    ..._algorithmIdentifierRsa,
    ..._tlv(0x03, <int>[0x00, ...rsaPublicKey]),
  ]);

  final String cuerpo = base64.encode(spki);
  final StringBuffer sb = StringBuffer('-----BEGIN PUBLIC KEY-----\n');
  for (int i = 0; i < cuerpo.length; i += 64) {
    final int fin = i + 64 > cuerpo.length ? cuerpo.length : i + 64;
    sb.writeln(cuerpo.substring(i, fin));
  }
  sb.writeln('-----END PUBLIC KEY-----');
  return sb.toString();
}

List<int> _tlv(int etiqueta, List<int> contenido) =>
    <int>[etiqueta, ..._longitudDer(contenido.length), ...contenido];

List<int> _longitudDer(int n) {
  if (n < 0x80) return <int>[n];
  final List<int> bytes = <int>[];
  int v = n;
  while (v > 0) {
    bytes.insert(0, v & 0xFF);
    v >>= 8;
  }
  return <int>[0x80 | bytes.length, ...bytes];
}

List<int> _enteroDer(BigInt valor) {
  String hex = valor.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final List<int> bytes = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  // DER INTEGER es con signo: si el bit alto está a 1, se antepone 0x00.
  if (bytes.isNotEmpty && (bytes.first & 0x80) != 0) bytes.insert(0, 0x00);
  return bytes;
}
