/// Espejo en Dart de `PagoYa.Core/Contratos/EstadoLicencia.cs`,
/// `CaracteristicaLicencia.cs` (clase `Flags`) y `PagoYa.Core/Enums/TierLicencia.cs`.
///
/// Los nombres de flag (`invoicing`, `cloud_sync`, `multi_site`) son el
/// contrato estable compartido con `licensing-backend` (docs/LICENSE-TOKEN.md
/// §5). **Prohibido renombrarlos**: el backend firma estos strings y un cambio
/// unilateral deja tokens válidos que no habilitan nada.
///
/// Punto de entrada estable: `licencia/contratos.dart` reexporta todo esto
/// (arbitraje de `mobile-lead`, MOBILE-ARQUITECTURA §4.2).
library;

import 'package:meta/meta.dart';

/// Niveles comerciales de licencia. El tier es **informativo**: el gating real
/// se hace por flag individual (un token podría habilitar `cloud_sync` sin
/// `invoicing`).
enum TierLicencia {
  /// PagoYa Base — offline de por vida, 1 caja, notas de venta.
  base('base'),

  /// PagoYa Cloud — respaldo en la nube, multi-caja / multisede.
  cloud('cloud'),

  /// PagoYa Facturador Pro — Boletas/Facturas SUNAT ilimitadas.
  facturadorPro('facturador');

  const TierLicencia(this.clave);

  /// Valor del claim `tier` del token (docs/LICENSE-TOKEN.md §4).
  final String clave;
}

/// Catálogo tipado de feature flags que la licencia puede habilitar.
enum CaracteristicaLicencia {
  /// Facturación electrónica SUNAT. Flag: `invoicing`.
  invoicing(Flags.invoicing),

  /// Respaldo y sincronización en la nube. Flag: `cloud_sync`.
  cloudSync(Flags.cloudSync),

  /// Operación multi-caja / multisede. Flag: `multi_site`.
  multiSite(Flags.multiSite);

  const CaracteristicaLicencia(this.flag);

  /// Nombre canónico del flag dentro del token firmado.
  final String flag;
}

/// Nombres canónicos (string) de los flags tal como viajan firmados dentro del
/// token. Espejo literal de `PagoYa.Core.Contratos.Flags`.
abstract final class Flags {
  /// Facturación electrónica SUNAT (Boletas/Facturas).
  static const String invoicing = 'invoicing';

  /// Respaldo y sincronización en la nube.
  static const String cloudSync = 'cloud_sync';

  /// Operación multi-caja / multisede.
  static const String multiSite = 'multi_site';

  /// Traduce el enum al nombre canónico del flag en el token.
  static String deCaracteristica(CaracteristicaLicencia caracteristica) =>
      caracteristica.flag;
}

/// Traduce el claim `tier` del token al enum. Desconocido → [TierLicencia.base]:
/// degradar es siempre la respuesta segura (espejo de `LicenseService.MapearTier`).
TierLicencia mapearTier(String? tier) => switch (tier?.toLowerCase().trim()) {
      'cloud' => TierLicencia.cloud,
      'facturador' || 'facturador_pro' => TierLicencia.facturadorPro,
      _ => TierLicencia.base,
    };

/// Motivo estructurado por el que la validación degradó a Base. Permite que la
/// UI decida qué mensaje y qué acción ofrecer sin parsear strings.
enum MotivoDegradacion {
  /// No hay token instalado todavía (primer arranque).
  sinToken,

  /// Firma RSA inválida, formato roto o payload no parseable.
  firmaInvalida,

  /// El token está vinculado a otro dispositivo (`hwid` != id local).
  otroDispositivo,

  /// `exp` pasado y también vencido el periodo de gracia de 7 días.
  expirada,
}

/// Snapshot **inmutable** del resultado de validar la licencia local. La UI y
/// los servicios lo consultan para hacer feature-gating.
///
/// Espejo de `PagoYa.Core.Contratos.EstadoLicencia`, más los campos que solo
/// tienen sentido en móvil: [relojSospechoso], [idDispositivoVinculado] y
/// [prefijoDispositivo].
@immutable
final class EstadoLicencia {
  /// `true` si el token es válido (firma OK, dispositivo OK, no expirado o en
  /// gracia). Ojo: también es `true` en el modo Base de respaldo **sin** token,
  /// igual que en C#. Para el gate de arranque se usa [estaActivada].
  final bool esValida;

  /// `true` **solo** si hay un token AUTÉNTICO instalado (firma válida +
  /// dispositivo vinculado + dentro de la ventana de expiración/gracia), del
  /// tier que sea, **incluido Base**.
  ///
  /// Es lo que consulta el gate de arranque (`gateArranqueProvider`): mientras
  /// sea `false` la app muestra la pantalla de activación y **no entra al POS**
  /// (CLAUDE.md, regla de negocio clave).
  final bool estaActivada;

  /// Tier comercial resuelto del token. Base si no hay licencia válida.
  final TierLicencia tier;

  /// Flags habilitados, normalizados a minúsculas (el contrato los define en
  /// minúsculas; C# compara con `OrdinalIgnoreCase`).
  final Set<String> featuresHabilitadas;

  /// Expiración del token (UTC). `null` para licencias perpetuas (`exp == 0`).
  final DateTime? expiraUtc;

  /// `true` si el token expiró pero aún opera dentro del grace period de 7 días.
  /// La UI debe avisar para renovar, nunca bloquear.
  final bool enPeriodoGracia;

  /// `true` si el reloj del dispositivo retrocedió más allá de la tolerancia
  /// respecto del último instante visto.
  ///
  /// **No degrada la licencia por sí solo** (un cambio de zona horaria no es un
  /// ataque): solo marca el estado para que la app fuerce una revalidación
  /// online y avise discretamente. Regla de MOBILE-ARQUITECTURA §5.5.
  final bool relojSospechoso;

  /// Motivo estructurado de la degradación, si la hubo.
  final MotivoDegradacion? motivoDegradacion;

  /// Mensaje legible del motivo, para la UI y el soporte.
  final String? motivo;

  /// Claim `license_id` (para soporte y para el tenant de la sync).
  final String? licenseId;

  /// Id del dispositivo al que está atado el token (claim `hwid`).
  ///
  /// En escritorio es el HWID (CPU + BaseBoard); en móvil es el id que devuelve
  /// `IdentidadDispositivo`, registrado como **asiento secundario** vía
  /// `POST /devices` — nunca vía `/activate`, que quemaría un traslado y
  /// desvincularía la PC.
  final String? idDispositivoVinculado;

  /// Prefijo de correlativos asignado por el server (claim `device_prefix`:
  /// `C01` en la PC, `M01` en el móvil). `null` en tokens sin asiento.
  final String? prefijoDispositivo;

  /// Id del **asiento** en el backend (claim `device_id`), el `{id}` de
  /// `DELETE /devices/{id}`. Se muestra en Ajustes para que el dueño pueda
  /// pedirle a soporte que libere el cupo. `null` en tokens sin asiento.
  final String? idAsiento;

  EstadoLicencia({
    required this.esValida,
    this.estaActivada = false,
    this.tier = TierLicencia.base,
    Iterable<String> featuresHabilitadas = const <String>[],
    this.expiraUtc,
    this.enPeriodoGracia = false,
    this.relojSospechoso = false,
    this.motivoDegradacion,
    this.motivo,
    this.licenseId,
    this.idDispositivoVinculado,
    this.prefijoDispositivo,
    this.idAsiento,
  }) : featuresHabilitadas = Set<String>.unmodifiable(
          featuresHabilitadas.map((String f) => f.trim().toLowerCase()),
        );

  /// Estado por defecto: tier Base, **sin** features premium y **sin** activar.
  /// Es el fallback seguro de cualquier fallo de validación.
  ///
  /// Se llama `baseSegura` y no `base` porque `base` es un modificador de clase
  /// reservado en Dart 3.
  factory EstadoLicencia.baseSegura({
    String? motivo,
    MotivoDegradacion? motivoDegradacion,
    bool relojSospechoso = false,
  }) =>
      EstadoLicencia(
        esValida: true,
        estaActivada: false,
        motivo: motivo,
        motivoDegradacion: motivoDegradacion,
        relojSospechoso: relojSospechoso,
      );

  /// Feature-gating por flag canónico (string).
  bool tieneFlag(String flag) =>
      featuresHabilitadas.contains(flag.trim().toLowerCase());

  /// Feature-gating tipado.
  bool tieneCaracteristica(CaracteristicaLicencia caracteristica) =>
      tieneFlag(caracteristica.flag);

  /// Días que faltan para `exp` (negativo si ya expiró). `null` si es perpetua.
  int? diasParaExpirar(DateTime ahoraUtc) =>
      expiraUtc?.difference(ahoraUtc).inDays;

  @override
  String toString() => 'EstadoLicencia(activada: $estaActivada, tier: $tier, '
      'features: $featuresHabilitadas, expira: $expiraUtc, '
      'gracia: $enPeriodoGracia, relojSospechoso: $relojSospechoso, '
      'motivo: $motivo)';
}
