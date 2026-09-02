/// Puerto en Dart de `src/PagoYa.Licensing/LicenseTokenValidator.cs`.
///
/// Verifica criptográficamente un token de licencia PagoYa:
/// `base64url(payload_json) "." base64url(firma_rsa)`, con la firma
/// **RSA-2048 RSASSA-PKCS1-v1_5 sobre SHA-256** calculada sobre los **bytes
/// crudos UTF-8 del payload** (no sobre el string base64url).
/// Ver docs/LICENSE-TOKEN.md §2 y §3 — ese documento es el contrato y no se toca.
///
/// Este validador es **puro**: no conoce el dispositivo ni el reloj. Esas
/// reglas las aplica `ServicioLicencia` (espejo de `LicenseService.cs`). Aquí
/// solo se responde: ¿la firma es auténtica y el payload es parseable?
///
/// ## Nota sobre el parseo del PEM (desviación documentada)
///
/// `docs/MOBILE-ARQUITECTURA.md` §4 fija **pointycastle + asn1lib**. La
/// verificación RSA usa pointycastle tal cual. Para el `SubjectPublicKeyInfo`
/// se usa un lector DER interno ([_LectorDer], ~60 líneas) en vez de asn1lib:
/// los getters de asn1lib para enteros y BIT STRING (`integer` /
/// `valueAsBigInteger`, `stringValues` / `contentBytes`) cambiaron entre las
/// versiones 1.0→1.5 y este código se escribió sin poder compilar. El lector
/// propio es determinista, cubierto por tests y elimina esa dependencia de
/// versión. Si se prefiere asn1lib, basta sustituir `parsearClavePublicaPem` —
/// el resto del archivo no cambia.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'clave_publica_embebida.dart';
import 'license_token.dart';

/// Resultado de la verificación criptográfica de un token.
final class ResultadoValidacionToken {
  /// Payload deserializado. No nulo solo si [esValido].
  final LicenseToken? token;

  /// Motivo legible del fallo. Null si [esValido].
  final String? error;

  const ResultadoValidacionToken._(this.token, this.error);

  const ResultadoValidacionToken.ok(LicenseToken token)
      : this._(token, null);

  const ResultadoValidacionToken.fallo(String error) : this._(null, error);

  /// True si la firma es auténtica y el payload es un objeto JSON válido.
  bool get esValido => token != null;
}

/// Verificador de la firma RSA del token contra la(s) clave(s) pública(s)
/// embebida(s).
final class LicenseTokenValidator {
  /// Claves públicas aceptadas, ya parseadas. Se admiten varias para soportar
  /// rotación de llaves (token viejo + token nuevo válidos a la vez).
  final List<RSAPublicKey> _clavesPublicas;

  /// Usa las claves públicas embebidas por defecto.
  LicenseTokenValidator()
      : _clavesPublicas = pemClavesPublicasAceptadas
            .map(parsearClavePublicaPem)
            .toList(growable: false);

  /// Inyecta una clave pública en PEM (útil para tests y para rotación).
  LicenseTokenValidator.conPem(String pem)
      : _clavesPublicas = <RSAPublicKey>[parsearClavePublicaPem(pem)];

  /// Inyecta claves ya parseadas (útil para tests que generan un par al vuelo).
  LicenseTokenValidator.conClaves(List<RSAPublicKey> claves)
      : _clavesPublicas = List<RSAPublicKey>.unmodifiable(claves);

  /// Verifica la firma y parsea el payload.
  ///
  /// Nunca lanza: cualquier fallo (formato, base64, firma, JSON) vuelve como
  /// [ResultadoValidacionToken.fallo] para que el llamador degrade a Base.
  ResultadoValidacionToken validar(String? tokenFirmado) {
    if (tokenFirmado == null || tokenFirmado.trim().isEmpty) {
      return const ResultadoValidacionToken.fallo('Token vacío.');
    }

    final List<String> partes = tokenFirmado.trim().split('.');
    if (partes.length != 2) {
      return const ResultadoValidacionToken.fallo(
        'Formato de token inválido (se esperaba payload.firma).',
      );
    }

    final Uint8List payloadBytes;
    final Uint8List firmaBytes;
    try {
      payloadBytes = decodificarBase64Url(partes[0]);
      firmaBytes = decodificarBase64Url(partes[1]);
    } on FormatException {
      return const ResultadoValidacionToken.fallo(
        'Codificación base64url inválida.',
      );
    }

    if (payloadBytes.isEmpty || firmaBytes.isEmpty) {
      return const ResultadoValidacionToken.fallo(
        'Token incompleto (payload o firma vacíos).',
      );
    }

    // --- Firma RSA-2048 sobre los BYTES del payload, no sobre el base64url ---
    if (!_firmaEsAutentica(payloadBytes, firmaBytes)) {
      return const ResultadoValidacionToken.fallo(
        'Firma del token no válida (posible manipulación o clave incorrecta).',
      );
    }

    // --- Deserialización del payload ya autenticado ---
    final Object? decodificado;
    try {
      decodificado = jsonDecode(utf8.decode(payloadBytes));
    } on FormatException {
      return const ResultadoValidacionToken.fallo(
        'El payload del token no es JSON válido.',
      );
    }

    if (decodificado is! Map<String, Object?>) {
      return const ResultadoValidacionToken.fallo(
        'El payload del token no es un objeto JSON.',
      );
    }

    try {
      return ResultadoValidacionToken.ok(LicenseToken.fromJson(decodificado));
    } on FormatException catch (e) {
      return ResultadoValidacionToken.fallo(
        'El payload del token no cumple el contrato: ${e.message}',
      );
    }
  }

  /// True si alguna de las claves aceptadas verifica la firma.
  bool _firmaEsAutentica(Uint8List payloadBytes, Uint8List firmaBytes) {
    for (final RSAPublicKey clave in _clavesPublicas) {
      try {
        // RSASSA-PKCS1-v1_5 con DigestInfo de SHA-256.
        // El identificador hex es el DER del OID 2.16.840.1.101.3.4.2.1.
        final RSASigner verificador =
            RSASigner(SHA256Digest(), '0609608648016503040201')
              ..init(false, PublicKeyParameter<RSAPublicKey>(clave));

        if (verificador.verifySignature(
          payloadBytes,
          RSASignature(firmaBytes),
        )) {
          return true;
        }
      } catch (_) {
        // pointycastle lanza si la firma no mide lo mismo que el módulo, o si
        // el bloque PKCS#1 está corrupto. Es un rechazo, no un crash: se
        // prueba la siguiente clave y, si no hay más, degrada a Base.
        continue;
      }
    }
    return false;
  }
}

/// Decodifica base64url (RFC 4648, **sin padding**) a bytes.
/// Espejo exacto de `LicenseTokenValidator.DecodeBase64Url` en C#:
/// `-`→`+`, `_`→`/` y se repone el padding `=`.
Uint8List decodificarBase64Url(String entrada) {
  String s = entrada.replaceAll('-', '+').replaceAll('_', '/');
  final int resto = s.length % 4;
  if (resto == 2) {
    s += '==';
  } else if (resto == 3) {
    s += '=';
  } else if (resto == 1) {
    // Longitud imposible en base64: sobra un carácter.
    throw const FormatException('Longitud base64url inválida.');
  }
  return base64.decode(s);
}

/// Codifica bytes a base64url sin padding (lo usan los tests al construir
/// tokens y el cliente al reenviar el token al backend).
String codificarBase64Url(List<int> bytes) =>
    base64.encode(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

// ============================================================================
//  Parseo del PEM SubjectPublicKeyInfo
// ============================================================================

/// DER del OID `rsaEncryption` (1.2.840.113549.1.1.1), tal como aparece dentro
/// del `AlgorithmIdentifier` de un SPKI de RSA.
const List<int> _oidRsaEncryption = <int>[
  0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
];

/// Parsea una clave pública RSA en PEM (`-----BEGIN PUBLIC KEY-----`, formato
/// `SubjectPublicKeyInfo`) a la [RSAPublicKey] de pointycastle.
///
/// Lanza [FormatException] si el PEM no es un SPKI de RSA. Se llama una sola
/// vez al construir el validador, con una constante del binario: si falla, es
/// un bug de compilación del cliente, no una entrada del usuario.
RSAPublicKey parsearClavePublicaPem(String pem) {
  final Uint8List der = _derDesdePem(pem);

  // SubjectPublicKeyInfo ::= SEQUENCE { AlgorithmIdentifier, BIT STRING }
  final Uint8List spki = _LectorDer(der).leerContenido(_etiquetaSequence);
  final _LectorDer interno = _LectorDer(spki);

  final Uint8List algoritmo = interno.leerContenido(_etiquetaSequence);
  if (!_empiezaCon(algoritmo, _oidRsaEncryption)) {
    throw const FormatException(
      'La clave pública embebida no es RSA (OID rsaEncryption ausente).',
    );
  }

  final Uint8List bitString = interno.leerContenido(_etiquetaBitString);
  if (bitString.isEmpty || bitString[0] != 0x00) {
    throw const FormatException(
      'BIT STRING con bits sobrantes: no es una clave pública DER válida.',
    );
  }

  // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
  final Uint8List clave =
      _LectorDer(Uint8List.sublistView(bitString, 1)).leerContenido(_etiquetaSequence);
  final _LectorDer lectorClave = _LectorDer(clave);
  final BigInt modulo = lectorClave.leerEnteroPositivo();
  final BigInt exponente = lectorClave.leerEnteroPositivo();

  if (modulo.bitLength < 2048) {
    throw FormatException(
      'Clave RSA demasiado corta (${modulo.bitLength} bits, se exigen 2048).',
    );
  }

  return RSAPublicKey(modulo, exponente);
}

const int _etiquetaSequence = 0x30;
const int _etiquetaBitString = 0x03;
const int _etiquetaInteger = 0x02;

Uint8List _derDesdePem(String pem) {
  final List<String> lineas = const LineSplitter()
      .convert(pem)
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty && !l.startsWith('-----'))
      .toList(growable: false);

  if (lineas.isEmpty) {
    throw const FormatException('PEM vacío o sin cuerpo base64.');
  }
  return base64.decode(lineas.join());
}

bool _empiezaCon(Uint8List datos, List<int> prefijo) {
  if (datos.length < prefijo.length) return false;
  for (int i = 0; i < prefijo.length; i++) {
    if (datos[i] != prefijo[i]) return false;
  }
  return true;
}

/// Lector DER mínimo (solo lo que exige un SPKI de RSA): etiqueta, longitud
/// definida corta/larga y contenido. No soporta longitud indefinida — DER no la
/// permite, así que rechazarla es correcto.
final class _LectorDer {
  final Uint8List _bytes;
  int _pos = 0;

  _LectorDer(this._bytes);

  int _siguienteByte() {
    if (_pos >= _bytes.length) {
      throw const FormatException('DER truncado.');
    }
    return _bytes[_pos++];
  }

  /// Lee un TLV con la etiqueta esperada y devuelve **solo el contenido**.
  Uint8List leerContenido(int etiquetaEsperada) {
    final int etiqueta = _siguienteByte();
    if (etiqueta != etiquetaEsperada) {
      throw FormatException(
        'DER inesperado: se esperaba 0x${etiquetaEsperada.toRadixString(16)} '
        'y llegó 0x${etiqueta.toRadixString(16)}.',
      );
    }
    final int longitud = _leerLongitud();
    if (_pos + longitud > _bytes.length) {
      throw const FormatException('DER truncado: longitud fuera de rango.');
    }
    final Uint8List contenido =
        Uint8List.sublistView(_bytes, _pos, _pos + longitud);
    _pos += longitud;
    return contenido;
  }

  /// Lee un INTEGER DER y lo interpreta como entero **sin signo** (los enteros
  /// de RSA son positivos; DER les antepone 0x00 cuando el bit alto está a 1).
  BigInt leerEnteroPositivo() {
    final Uint8List contenido = leerContenido(_etiquetaInteger);
    if (contenido.isEmpty) {
      throw const FormatException('INTEGER DER vacío.');
    }
    if (contenido[0] & 0x80 != 0) {
      throw const FormatException('INTEGER DER negativo en una clave RSA.');
    }
    BigInt valor = BigInt.zero;
    for (final int b in contenido) {
      valor = (valor << 8) | BigInt.from(b);
    }
    return valor;
  }

  int _leerLongitud() {
    final int primero = _siguienteByte();
    if (primero < 0x80) return primero;
    final int octetos = primero & 0x7F;
    if (octetos == 0 || octetos > 4) {
      throw const FormatException('Longitud DER no soportada.');
    }
    int longitud = 0;
    for (int i = 0; i < octetos; i++) {
      longitud = (longitud << 8) | _siguienteByte();
    }
    return longitud;
  }
}
