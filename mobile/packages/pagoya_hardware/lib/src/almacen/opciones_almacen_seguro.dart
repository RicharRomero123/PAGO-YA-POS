import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Opciones de plataforma **compartidas por todo lo que PagoYa guarda
/// cifrado**: el id de dispositivo y el token de licencia.
///
/// Viven en un solo sitio a propósito. Si el id de dispositivo y el token se
/// guardaran con opciones distintas de accesibilidad del Keychain, podrían
/// sobrevivir a eventos distintos (una reinstalación, una restauración de
/// backup) y quedar **desparejados**: token válido con id nuevo, o al revés.
/// Cualquiera de los dos casos es una activación rota y un WhatsApp de soporte.
library;

/// Android: `EncryptedSharedPreferences` sobre el Android Keystore (exige
/// API 23, de ahí el `minSdk 23` del Gradle).
///
/// **`resetOnError: false` es deliberado.** Con `true`, `flutter_secure_storage`
/// borra todo el almacén ante un fallo de descifrado — y los fallos de Keystore
/// tras una actualización de sistema son frecuentes en gama baja. Eso
/// convertiría un error transitorio en la pérdida definitiva de la licencia del
/// cliente. Preferimos que la lectura falle y que quien llame decida: la
/// identidad tiene copia sombra, y el token se puede re-pedir.
const AndroidOptions opcionesAndroidPagoYa = AndroidOptions(
  encryptedSharedPreferences: true,
  resetOnError: false,
);

/// iOS: `first_unlock_this_device`.
///
/// - **Sobrevive a desinstalar y reinstalar la app.** Es justo lo que queremos:
///   el cliente reinstala PagoYa y su licencia sigue activa sin escribirle a
///   nadie (regla de negocio: "activa una sola vez, luego offline de por vida").
/// - **NO se restaura en otro iPhone** por backup de iCloud. Sin el sufijo
///   `_this_device`, restaurar un backup en un teléfono nuevo clonaría el id de
///   dispositivo y el token: dos equipos con el mismo seat, que es exactamente
///   lo que el licenciamiento existe para impedir.
/// - `first_unlock` (y no `unlocked`) permite leer con el teléfono bloqueado
///   tras el primer desbloqueo del arranque, para que la app no falle si el
///   sistema la reanuda con la pantalla apagada.
const IOSOptions opcionesIosPagoYa = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

/// Instancia compartida de `flutter_secure_storage` con las opciones de arriba.
///
/// Es `const` y sin estado: compartirla no acopla nada, y garantiza que nadie
/// abra el almacén con otras opciones por descuido.
const FlutterSecureStorage almacenCifradoPagoYa = FlutterSecureStorage(
  aOptions: opcionesAndroidPagoYa,
  iOptions: opcionesIosPagoYa,
);