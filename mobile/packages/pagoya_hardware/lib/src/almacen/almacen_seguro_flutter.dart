import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pagoya_core/pagoya_core.dart' show AlmacenSeguro;

import 'opciones_almacen_seguro.dart';

/// Se re-exporta el contrato del núcleo, igual que con `IdentidadDispositivo`,
/// para que quien importe `package:pagoya_hardware` no tenga que importar los
/// dos paquetes solo para nombrar el tipo.
export 'package:pagoya_core/pagoya_core.dart' show AlmacenSeguro;

/// Implementación real de [AlmacenSeguro] sobre `flutter_secure_storage`:
/// **Keystore en Android, Keychain en iOS**.
///
/// El contrato es de `pagoya_core` (`dispositivo/contratos.dart`); aquí solo
/// vive la implementación, porque el núcleo es Dart puro y no puede depender de
/// un plugin. Lo consume `AlmacenLicenciaSegura` de `flutter-licencia` para
/// guardar el token y la clave de licencia.
///
/// Es el equivalente móvil del cifrado DPAPI de `LicenseStoreArchivo` en
/// Windows. Y, como allá, **no es la barrera criptográfica principal**: la firma
/// RSA-2048 del token lo es. Alguien con su propio teléfono rooteado puede leer
/// esto; lo que no puede es fabricar un token que valide.
///
/// ## Política de errores (leer antes de "mejorarla")
///
/// - [leer] **devuelve `null` si falla**, como manda el contrato. Un almacén
///   ilegible degrada a "sin licencia", que es el fallo seguro: la app manda al
///   usuario a la pantalla de activación en vez de reventar.
/// - [escribir] **deja propagar el error a propósito**. Tragarse un fallo de
///   escritura del token sería el peor bug posible del producto: el cliente
///   activa, ve "listo", cierra la app y al abrirla vuelve a estar bloqueado sin
///   entender por qué. Quien llame debe avisarle de que no se pudo guardar.
/// - [borrar] no falla nunca: borrar algo que ya no está es éxito.
///
/// Compatibilidad: Android 6.0+ (API 23, lo exige `EncryptedSharedPreferences`),
/// iOS 13+. Ver [opcionesAndroidPagoYa] y [opcionesIosPagoYa] para el porqué de
/// cada opción de plataforma.
class AlmacenSeguroFlutter implements AlmacenSeguro {
  /// [almacen] se inyecta solo en tests; en producción se usa la instancia
  /// compartida con las opciones de plataforma de PagoYa.
  AlmacenSeguroFlutter({FlutterSecureStorage? almacen})
      : _almacen = almacen ?? almacenCifradoPagoYa;

  final FlutterSecureStorage _almacen;

  @override
  Future<String?> leer(String clave) async {
    try {
      return await _almacen.read(key: clave);
    } catch (_) {
      // Keystore corrupto tras actualizar el sistema, o valor cifrado con otra
      // cuenta. Se degrada a "no hay nada": el gate de licencia mandará a
      // activar, que es recuperable. Lanzar aquí solo daría un stack trace.
      return null;
    }
  }

  @override
  Future<void> escribir(String clave, String valor) {
    // Sin try/catch: ver la política de errores en la doc de la clase.
    return _almacen.write(key: clave, value: valor);
  }

  @override
  Future<void> borrar(String clave) async {
    try {
      await _almacen.delete(key: clave);
    } catch (_) {
      // Ya no está, o el almacén no responde. En ambos casos el resultado
      // deseado (que la clave no exista) se cumple o se cumplirá al reinstalar.
    }
  }
}