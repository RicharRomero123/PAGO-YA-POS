/// Persistencia del token de licencia sobre el almacén cifrado del sistema.
///
/// Es el equivalente móvil de `LicenseStoreArchivo` del escritorio (que cifra
/// con DPAPI en `%LocalAppData%\PagoYa\licencia.token`). Aquí el cifrado en
/// reposo lo da [AlmacenSeguro] → Keystore en Android, Keychain en iOS.
///
/// Igual que en escritorio, **la firma RSA sigue siendo la barrera
/// criptográfica principal**: esto solo protege el artefacto guardado. Un
/// atacante con el APK decompilado puede leer lo que quiera de su propio
/// teléfono; lo que no puede es fabricar un token que valide.
///
/// Nota iOS: el Keychain sobrevive a la desinstalación, y eso es **deseado**:
/// reinstalar la app no debe obligar al dueño de la bodega a reactivar.
library;

// `AlmacenSeguro` e `IdentidadDispositivo` llegan reexportados desde
// `puertos_licencia.dart` (son canónicos en `dispositivo/contratos.dart`).
import 'puertos_licencia.dart';

/// Claves usadas dentro de [AlmacenSeguro]. Prefijadas para no chocar con las
/// que guarde `flutter-hardware` (id de dispositivo) o `flutter-sync`.
abstract final class ClavesSeguras {
  /// Token de licencia firmado (`base64url(payload).base64url(firma)`).
  static const String tokenLicencia = 'pagoya.licencia.token';

  /// Clave de licencia (`PAGOYA-XXXX-…`) con la que se vinculó el dispositivo.
  ///
  /// Se guarda para poder **revalidar en silencio** sin volver a pedírsela al
  /// usuario. Es un secreto de menor valor que el token (sin ella el backend no
  /// emite nada igualmente), pero va al mismo almacén cifrado.
  static const String claveLicencia = 'pagoya.licencia.clave';
}

/// [AlmacenLicencia] respaldado por [AlmacenSeguro].
final class AlmacenLicenciaSegura implements AlmacenLicencia {
  final AlmacenSeguro _seguro;

  const AlmacenLicenciaSegura(this._seguro);

  @override
  Future<String?> leerToken() async {
    final String? valor = await _seguro.leer(ClavesSeguras.tokenLicencia);
    if (valor == null) return null;
    final String limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  @override
  Future<void> guardarToken(String tokenFirmado) =>
      _seguro.escribir(ClavesSeguras.tokenLicencia, tokenFirmado.trim());

  @override
  Future<void> borrarToken() async {
    await _seguro.borrar(ClavesSeguras.tokenLicencia);
    await _seguro.borrar(ClavesSeguras.claveLicencia);
  }

  /// Guarda la clave de licencia para la revalidación silenciosa.
  ///
  /// No está en el contrato [AlmacenLicencia] a propósito: solo la usa
  /// `RevalidadorLicencia`, dentro de este mismo módulo.
  Future<void> guardarClaveLicencia(String clave) =>
      _seguro.escribir(ClavesSeguras.claveLicencia, clave.trim());

  /// Clave de licencia guardada, o `null` si el dispositivo se activó pegando
  /// el token a mano (flujo sin internet).
  Future<String?> leerClaveLicencia() async {
    final String? valor = await _seguro.leer(ClavesSeguras.claveLicencia);
    if (valor == null) return null;
    final String limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }
}
