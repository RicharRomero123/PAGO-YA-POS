/// Identidad del dispositivo — **la interfaz NO se declara aquí**.
///
/// ## Arbitraje de `mobile-lead` (MOBILE-ARQUITECTURA §4.2), aplicado
///
/// `IdentidadDispositivo` es **canónico en `pagoya_core`**. El núcleo valida el
/// claim `hwid` del token de licencia contra el id del dispositivo, y
/// `pagoya_core` no puede depender de `pagoya_hardware` (rompería la invariante
/// de Dart puro, y además sería una dependencia circular: este paquete ya
/// depende del core).
///
/// Este paquete **implementa** esa interfaz:
/// - `IdentidadDispositivoSegura` — UUID v4 en `flutter_secure_storage`.
/// - `IdentidadDispositivoFalsa` — en memoria, para tests y emulador.
///
/// Se re-exporta el símbolo para que quien importe `package:pagoya_hardware`
/// siga encontrando el tipo sin tener que importar los dos paquetes.
///
/// ---
///
/// ## Cómo se construye la identidad, y por qué así
///
/// **UUID v4 aleatorio generado en el primer arranque**, guardado en
/// `flutter_secure_storage` (Keychain en iOS, EncryptedSharedPreferences sobre
/// Android Keystore en Android).
///
/// ### Qué NO se usa, y por qué
///
/// - **`ANDROID_ID` (`Settings.Secure.ANDROID_ID`)**: desde Android 8 es
///   distinto por app *y por clave de firma*, y se **regenera en cada factory
///   reset y en cada reinstalación en varios OEM**. Además cambiaría si algún
///   día se rota la clave de firma del APK. Una identidad que cambia sola es
///   una licencia perdida y un ticket de soporte por WhatsApp.
/// - **`identifierForVendor` (iOS)**: se **borra cuando el usuario desinstala
///   todas las apps del mismo vendor**. Reinstalar PagoYa daría un id nuevo.
/// - **IMEI / número de serie**: inaccesibles sin permisos privilegiados desde
///   Android 10. Ni se intenta.
/// - **Un hash de hardware al estilo `HardwareIdWindows`** (CPU ID +
///   BaseBoard serial por WMI, ver
///   `src/PagoYa.Desktop/Servicios/HardwareIdWindows.cs`): **no se replica en
///   móvil**. En Android/iOS no existe API pública equivalente, y las señales
///   que sí hay (modelo, fabricante, build) son idénticas en miles de teléfonos
///   del mismo lote: dos Redmi 9A darían el mismo "HWID" y compartirían
///   licencia. En escritorio el hash de hardware es estable y único; en móvil
///   no es ni lo uno ni lo otro.
///
/// ### Consecuencia deseada en iOS
///
/// El Keychain **sobrevive a la desinstalación** de la app. Es exactamente lo
/// que queremos: el cliente reinstala PagoYa y su licencia sigue activa sin
/// escribirle a nadie. La implementación usa `first_unlock_this_device` para
/// que el id **no** viaje a otro iPhone por backup de iCloud, lo que duplicaría
/// el seat. El equivalente en Android es `android:allowBackup="false"` en el
/// manifiesto.
library;

export 'package:pagoya_core/pagoya_core.dart' show IdentidadDispositivo;

/// El almacén seguro no se pudo leer, así que **no se sabe** si este
/// dispositivo ya tenía un id.
///
/// Se lanza en vez de generar un id nuevo, porque un id nuevo se registraría
/// como un segundo asiento y dejaría al cliente sin licencia en mitad de su
/// jornada. `pagoya_core` lo trata como fallo transitorio: reintenta más tarde
/// y **no degrada** la licencia.
///
/// Causa típica: el Android Keystore queda inutilizable tras una actualización
/// del sistema o un cambio del bloqueo de pantalla en gama baja.
class AlmacenSeguroIlegible implements Exception {
  const AlmacenSeguroIlegible(this.mensaje);

  /// Texto apto para mostrar al usuario final.
  final String mensaje;

  @override
  String toString() => 'AlmacenSeguroIlegible: $mensaje';
}

/// Datos descriptivos del equipo, para el panel de administración.
///
/// **No forma parte de la identidad** (esa es el UUID a secas, y es lo único
/// que consume `pagoya_core`). Sirve para que, cuando el cliente escriba
/// "cambié de celular", el vendedor vea en el panel "Xiaomi Redmi 9A ·
/// Android 11" y revoque el dispositivo correcto.
///
/// Vive en `pagoya_hardware` y no en el core justo porque el core no lo
/// necesita: es una comodidad de soporte, no una regla de licenciamiento.
class InfoDispositivo {
  const InfoDispositivo({
    required this.id,
    required this.nombre,
    required this.modelo,
    required this.fabricante,
    required this.plataforma,
    required this.versionSistema,
    required this.esFisico,
  });

  /// El UUID v4. Lo mismo que devuelve `obtenerIdDispositivo()`.
  final String id;

  /// Nombre para mostrar ("Xiaomi Redmi 9A").
  final String nombre;

  final String modelo;
  final String fabricante;

  /// `'android'` | `'ios'` | `'desconocido'`. Mismo valor que
  /// `obtenerPlataforma()`.
  final String plataforma;

  /// "13" / "17.4".
  final String versionSistema;

  /// `false` en emulador/simulador. Útil para no quemar seats en pruebas.
  final bool esFisico;

  Map<String, Object?> aJson() => <String, Object?>{
        'id': id,
        'nombre': nombre,
        'modelo': modelo,
        'fabricante': fabricante,
        'plataforma': plataforma,
        'versionSistema': versionSistema,
        'esFisico': esFisico,
      };
}

/// Capacidades de identidad que **añade** este paquete por encima del contrato
/// del core.
///
/// El core solo necesita tres strings (id, nombre, plataforma). La UI de
/// soporte y el onboarding necesitan un poco más, y eso vive aquí para no
/// engordar la interfaz que el núcleo tiene que respetar.
abstract interface class IdentidadDispositivoExtendida {
  /// Datos descriptivos para el panel admin.
  Future<InfoDispositivo> obtenerInfo();

  /// `true` si el id ya existía (no es el primer arranque). `flutter-licencia`
  /// lo usa para decidir si mostrar el onboarding de activación.
  Future<bool> yaExiste();

  /// **Genera un id nuevo, descartando el anterior.**
  ///
  /// Solo para soporte: "el mismo teléfono aparece dos veces en el panel" o
  /// una migración manual. Ejecutarlo **desvincula la licencia**: el id viejo
  /// queda huérfano en el backend y hay que revocarlo desde el panel admin.
  /// Nunca llamarlo de forma automática ante un error de lectura — para eso
  /// está la copia sombra de `IdentidadDispositivoSegura`.
  Future<String> regenerar();
}