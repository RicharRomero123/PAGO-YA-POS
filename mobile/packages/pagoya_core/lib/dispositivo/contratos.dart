/// **Puertos de plataforma canónicos del núcleo.**
///
/// Aquí viven **solo** los dos puertos que `pagoya_core` consume de verdad:
/// [IdentidadDispositivo] y [AlmacenSeguro]. Los implementa `flutter-hardware`
/// en `packages/pagoya_hardware/`.
///
/// Dueño de ESTE archivo: `mobile-lead`.
///
/// ## Por qué estos dos están en el núcleo y los demás no
///
/// La regla no es "todos los puertos de hardware juntos", es **quién los
/// consume**:
///
/// - El núcleo valida el claim `hwid` del token contra el id del dispositivo, y
///   guarda el token cifrado. Necesita estas dos interfaces, y `pagoya_core`
///   **no puede depender de `pagoya_hardware`** sin romper la invariante de que
///   es Dart puro. Por eso son canónicas aquí.
/// - `ImpresoraTickets`, `EscanerCodigos` y `CompartirArchivo` no los toca
///   ningún archivo del núcleo: son puertos que consume la UI. Se quedan en
///   `pagoya_hardware`, donde además están mejor modelados (estado de
///   impresora, tipo de conexión, causa de fallo).
///
/// Ver el arbitraje completo en `docs/MOBILE-ARQUITECTURA.md` §4.2.
///
/// `licencia/puertos_licencia.dart` reexporta ambos, así que quien trabaje en
/// licenciamiento los encuentra sin venir hasta aquí.
library;

// ---------------------------------------------------------------------------
// Identidad del dispositivo
// ---------------------------------------------------------------------------

/// Identificador estable de este dispositivo. Es el análogo móvil de
/// `IHardwareId` del escritorio, que hashea CPU ID + BaseBoard serial por WMI.
///
/// ## Cómo se genera (esto es especificación, no sugerencia)
///
/// **UUID v4 aleatorio, generado la primera vez y persistido en
/// [AlmacenSeguro]** (Keystore en Android, Keychain en iOS).
///
/// **NO se deriva de identificadores del sistema.** Es tentador usar el
/// `androidId` o el `identifierForVendor` de `device_info_plus` y hashearlos,
/// pero los dos cambian solos:
///
/// - `androidId` cambia al restaurar de fábrica y, desde Android 8, es distinto
///   por firma de app: cambiar la clave de firma del APK lo rota.
/// - `identifierForVendor` cambia cuando el usuario desinstala **todas** las
///   apps del mismo vendor.
///
/// Un id que rota solo significa que el `hwid` del token deja de coincidir y el
/// cliente **queda desactivado sin haber hecho nada**, en medio de su jornada de
/// ventas. Es el peor fallo posible del producto: peor que la piratería que
/// pretende evitar. El UUID persistido en el almacén seguro sobrevive a la
/// reinstalación (en iOS el Keychain sobrevive incluso al borrado de la app,
/// que es justo lo que queremos).
///
/// `device_info_plus` sí se usa, pero **solo para [obtenerNombreDispositivo]**,
/// que es informativo y aparece en el panel de dispositivos del admin.
///
/// ## Cómo se usa
///
/// Este id se registra como **seat secundario** con `POST /devices`. Jamás se
/// manda a `/activate`: eso desvincularía la PC del negocio y quemaría uno de
/// los dos traslados disponibles (MOBILE-ARQUITECTURA §6.1).
///
/// Implementa: `flutter-hardware` (`IdentidadDispositivoSegura`, y
/// `IdentidadDispositivoFalsa` para tests y emulador).
abstract interface class IdentidadDispositivo {
  /// Id estable de este dispositivo (UUID v4 persistido).
  ///
  /// Debe ser **determinístico entre arranques**: dos llamadas seguidas, y dos
  /// arranques distintos, devuelven lo mismo.
  ///
  /// Puede lanzar si el almacén seguro es ilegible (por ejemplo tras un cambio
  /// de firma del APK en Android). Quien llame debe tratar el fallo como "sin
  /// licencia" y mandar al usuario a la pantalla de activación — nunca
  /// inventar un id nuevo en silencio, porque eso quemaría un seat.
  Future<String> obtenerIdDispositivo();

  /// Nombre legible para el panel de dispositivos del admin, p. ej.
  /// `Samsung SM-A155M`. Solo informativo: sirve para que el dueño reconozca
  /// cuál de sus celulares revocar.
  Future<String> obtenerNombreDispositivo();

  /// Plataforma: `'android'` o `'ios'`.
  Future<String> obtenerPlataforma();
}

// ---------------------------------------------------------------------------
// Almacenamiento seguro
// ---------------------------------------------------------------------------

/// Almacén cifrado por el sistema: Keystore en Android, Keychain en iOS.
///
/// Es el equivalente móvil del cifrado DPAPI que usa `LicenseStoreArchivo` en
/// Windows. Guarda **solo secretos pequeños**: token de licencia, clave de
/// licencia, id de dispositivo. Los datos de negocio van a SQLite, no aquí.
///
/// Igual que en el escritorio, esto **no es la barrera criptográfica
/// principal**: la firma RSA lo es. Un atacante con el APK decompilado puede
/// leer lo que quiera de su propio teléfono; lo que no puede es fabricar un
/// token que valide.
///
/// Implementa: `flutter-hardware` sobre `flutter_secure_storage`.
abstract interface class AlmacenSeguro {
  /// Valor guardado bajo [clave], o `null` si no existe.
  ///
  /// Devolver `null` ante un valor ilegible (almacén corrupto, cifrado con otra
  /// cuenta) es aceptable y preferible a lanzar: degrada a "sin licencia", que
  /// es el fallo seguro.
  Future<String?> leer(String clave);

  /// Escribe (o sobrescribe) [valor] bajo [clave].
  Future<void> escribir(String clave, String valor);

  /// Borra [clave]. No falla si no existía.
  Future<void> borrar(String clave);
}
