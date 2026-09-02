/// Puertos del licenciamiento. `pagoya_core` es **Dart puro**: aquí no entra
/// `package:flutter/…` ni ningún plugin. Las implementaciones se inyectan.
///
/// | Puerto | Implementación por defecto | Quién la escribe |
/// |---|---|---|
/// | [IdentidadDispositivo] | UUID v4 en `flutter_secure_storage` | `flutter-hardware` |
/// | [AlmacenLicencia] | `AlmacenLicenciaSegura` sobre `AlmacenSeguro` | este módulo |
/// | [RelojAuditado] | `RelojAuditadoMeta` sobre la tabla `meta` | este módulo |
/// | `MetaLicencia` | sobre `EjecutorSql` (`meta_licencia.dart`) | este módulo |
/// | `ServicioDispositivos` | cliente de `POST /devices` (`nube/contratos.dart`) | `flutter-sync` |
///
/// [IdentidadDispositivo] y `AlmacenSeguro` son **canónicos en `pagoya_core`**
/// (`dispositivo/contratos.dart`), no en `pagoya_hardware`: el núcleo valida el
/// `hwid` del token y no puede depender del paquete de hardware. Se reexportan
/// aquí para que quien importe el licenciamiento los encuentre sin ir a buscar.
library;

export '../dispositivo/contratos.dart' show AlmacenSeguro, IdentidadDispositivo;

/// Persistencia del token de licencia. Espejo de `ILicenseStore` del escritorio
/// (que en Windows cifra con DPAPI).
///
/// En móvil el respaldo es el Keystore / Keychain a través de `AlmacenSeguro`.
/// Nota iOS: el Keychain **sobrevive a la desinstalación**, y eso es deseado —
/// reinstalar la app no debe obligar al dueño de la bodega a reactivar.
abstract interface class AlmacenLicencia {
  /// Token firmado guardado, o `null` si no hay ninguno / no se pudo descifrar.
  Future<String?> leerToken();

  /// Persiste el token firmado (sobrescribe el anterior).
  Future<void> guardarToken(String tokenFirmado);

  /// Elimina el token guardado y la clave de licencia asociada.
  Future<void> borrarToken();
}

/// Reloj resistente a manipulación, para validar la expiración en un
/// dispositivo donde el usuario cambia la fecha con dos toques.
///
/// Estrategia (MOBILE-ARQUITECTURA §5.5): se guarda un `ultimo_visto_utc`
/// monotónico en la tabla `meta`; si el reloj del sistema retrocede más que
/// [toleranciaRetroceso] respecto de esa marca, se considera sospechoso y se
/// refleja en `EstadoLicencia.relojSospechoso`. **No se degrada de golpe**:
/// bloquear una bodega en plena venta por un reloj mal puesto es peor que el
/// fraude que evita.
abstract interface class RelojAuditado {
  /// Tolerancia antes de marcar un retroceso como sospechoso.
  ///
  /// 26 h cubre el peor caso legítimo real —cruzar de UTC+14 a UTC-12— más el
  /// horario de verano y un margen. Perú no tiene DST, pero el equipo puede
  /// viajar o tener el huso mal puesto y luego corregirlo, y eso no puede
  /// parecer un ataque.
  static const Duration toleranciaRetroceso = Duration(hours: 26);

  /// Días de gracia tras `exp` antes de degradar a Base
  /// (docs/LICENSE-TOKEN.md §6.3 — mismo valor que el escritorio).
  static const int diasGracia = 7;

  /// Hora actual en UTC, ya contrastada contra la marca monotónica.
  Future<DateTime> ahoraUtc();

  /// `true` si el reloj retrocedió más que [toleranciaRetroceso].
  Future<bool> detectoRetroceso();

  /// Actualiza `ultimo_visto_utc`. Se llama al arranque y en cada validación.
  Future<void> registrarVisto();
}
