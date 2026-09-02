package pe.pagoya.movil

import io.flutter.embedding.android.FlutterActivity

/**
 * Actividad única de PagoYa Móvil.
 *
 * Toda la app es Flutter; no hay código nativo propio. Las capacidades de
 * plataforma (impresora Bluetooth ESC/POS, escáner de códigos, almacenamiento
 * seguro, compartir) se resuelven con plugins desde
 * `packages/pagoya_hardware`, no con canales de plataforma escritos a mano.
 *
 * Si algún día hace falta un MethodChannel propio, va aquí — pero antes hay que
 * preguntarse si no existe ya un plugin mantenido que lo haga: cada línea de
 * Kotlin es una línea que hay que reescribir en Swift.
 *
 * Nota: la ruta de este archivo tiene que coincidir con `namespace` de
 * `android/app/build.gradle.kts` (`pe.pagoya.movil`).
 */
class MainActivity : FlutterActivity()