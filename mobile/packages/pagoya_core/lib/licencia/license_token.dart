/// Espejo en Dart de `PagoYa.Licensing.LicenseToken`: el **payload** del token
/// de licencia. Es el CONTRATO compartido con `licensing-backend`
/// (docs/LICENSE-TOKEN.md §4). Los nombres JSON en snake_case son parte del
/// contrato: NO renombrar.
library;

/// Payload de claims del token de licencia PagoYa.
final class LicenseToken {
  /// Identificador único de la licencia emitida (revocación/soporte).
  final String licenseId;

  /// Tier comercial: `base` | `cloud` | `facturador`.
  final String tier;

  /// Feature flags habilitados. Valores canónicos: `invoicing`, `cloud_sync`,
  /// `multi_site`. Puede venir vacío.
  final List<String> features;

  /// Huella del equipo al que está atado el token. En escritorio es el HWID
  /// (CPU + BaseBoard); en un **token de asiento** (`POST /devices`) es el id
  /// estable del dispositivo secundario — en móvil, el UUID guardado en
  /// `flutter_secure_storage`. Vacío = licencia no atada a un equipo.
  ///
  /// Cada equipo valida contra su propia huella: el móvil compara esto contra
  /// `IdentidadDispositivo.obtenerIdDispositivo()`.
  final String hwid;

  /// Issued-at: Unix epoch en segundos (UTC).
  final int iat;

  /// Expiration: Unix epoch en segundos (UTC). `0` = perpetua (típico de Base).
  final int exp;

  /// RUC/identificador del negocio (informativo).
  final String? sub;

  /// Id del **asiento** (fila `Devices` del backend) al que se emitió el token.
  /// Claim `device_id`, **opcional** (docs/LICENSE-TOKEN.md §4.1).
  ///
  /// Es el `{id}` de `DELETE /devices/{id}` y lo que el backend usa para hacer
  /// efectiva la revocación en `/sync/*`. `null` en tokens emitidos antes del
  /// modelo de asientos — y eso **no** invalida nada: es enriquecimiento, no
  /// requisito.
  final String? deviceId;

  /// Prefijo de dispositivo asignado por el server (`C01` en la PC, `M01` en el
  /// móvil). Claim `device_prefix`, **opcional**.
  ///
  /// Lo asigna el backend, nunca el cliente. Se usa para los correlativos
  /// (`M01-000123`) y como `origen_caja_id` del outbox.
  final String? devicePrefix;

  /// Claims no reconocidos, preservados tal cual. Es la ruta de compatibilidad
  /// hacia adelante: si el contrato crece, un cliente viejo no rompe.
  final Map<String, Object?> claimsExtra;

  const LicenseToken({
    required this.licenseId,
    required this.tier,
    required this.features,
    required this.hwid,
    required this.iat,
    required this.exp,
    this.sub,
    this.deviceId,
    this.devicePrefix,
    this.claimsExtra = const <String, Object?>{},
  });

  /// True si el token trae los claims aditivos del modelo de asientos.
  bool get esTokenDeAsiento => deviceId != null;

  /// True si la licencia es perpetua (sin expiración).
  bool get esPerpetua => exp == 0;

  /// Fecha de emisión como DateTime UTC.
  DateTime get emitidoUtc =>
      DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true);

  /// Fecha de expiración como DateTime UTC, o null si es perpetua.
  DateTime? get expiraUtc => exp == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);

  /// Claims conocidos del contrato; el resto va a [claimsExtra].
  static const Set<String> _clavesConocidas = <String>{
    'license_id',
    'tier',
    'features',
    'hwid',
    'iat',
    'exp',
    'sub',
    'device_id',
    'device_prefix',
  };

  /// Deserializa el payload. Tolerante en los tipos numéricos (algunos
  /// serializadores emiten `exp` como string) pero estricto en la forma: si el
  /// JSON no es un objeto, lanza [FormatException] y el validador degrada a
  /// Base.
  factory LicenseToken.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> extra = <String, Object?>{};
    for (final MapEntry<String, Object?> e in json.entries) {
      if (!_clavesConocidas.contains(e.key)) extra[e.key] = e.value;
    }

    return LicenseToken(
      licenseId: _comoTexto(json['license_id']) ?? '',
      tier: _comoTexto(json['tier']) ?? 'base',
      features: _comoListaTexto(json['features']),
      hwid: _comoTexto(json['hwid']) ?? '',
      iat: _comoEntero(json['iat']) ?? 0,
      exp: _comoEntero(json['exp']) ?? 0,
      sub: _comoTexto(json['sub']),
      // Claims aditivos del modelo de asientos: OPCIONALES. Su ausencia es
      // normal y nunca invalida el token (docs/LICENSE-TOKEN.md §4.1).
      deviceId: _comoTexto(json['device_id']),
      devicePrefix: _comoTexto(json['device_prefix']),
      claimsExtra: Map<String, Object?>.unmodifiable(extra),
    );
  }

  /// Reserializa el payload. El emisor omite los claims nulos
  /// (`JsonIgnoreCondition.WhenWritingNull`) y aquí se hace lo mismo, para que
  /// un round-trip no altere los bytes que se firmaron.
  Map<String, Object?> toJson() => <String, Object?>{
        'license_id': licenseId,
        'tier': tier,
        'features': features,
        'hwid': hwid,
        'iat': iat,
        'exp': exp,
        if (sub != null) 'sub': sub,
        if (deviceId != null) 'device_id': deviceId,
        if (devicePrefix != null) 'device_prefix': devicePrefix,
        ...claimsExtra,
      };

  static String? _comoTexto(Object? v) => v is String ? v : v?.toString();

  static int? _comoEntero(Object? v) => switch (v) {
        final int i => i,
        final double d => d.toInt(),
        final String s => int.tryParse(s.trim()),
        _ => null,
      };

  static List<String> _comoListaTexto(Object? v) {
    if (v is! List) return const <String>[];
    return List<String>.unmodifiable(
      v.whereType<Object>().map((Object e) => e.toString()),
    );
  }

  @override
  String toString() => 'LicenseToken(licenseId: $licenseId, tier: $tier, '
      'features: $features, hwid: $hwid, iat: $iat, exp: $exp, '
      'deviceId: $deviceId, devicePrefix: $devicePrefix)';
}
