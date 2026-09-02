/// **PagoYa Móvil — capa de plataforma (hardware).**
///
/// Este paquete es la ÚNICA puerta de la app hacia el hardware y los plugins
/// nativos. Ninguna pantalla debe importar `mobile_scanner`,
/// `print_bluetooth_thermal`, `flutter_blue_plus`, `share_plus` ni
/// `flutter_secure_storage` directamente: todo pasa por las cuatro interfaces
/// que se exportan aquí.
///
/// ## Interfaces públicas
///
/// | Interfaz | Qué resuelve | Implementación real | Implementación falsa |
/// |---|---|---|---|
/// | `ImpresoraTickets` | Ticket térmico ESC/POS por Bluetooth | `ImpresoraTicketsBluetooth` | `ImpresoraTicketsFalsa` |
/// | `EscanerCodigos` | Cámara como lector de códigos de barras | `EscanerMobileScanner` | `EscanerFalso` |
/// | `IdentidadDispositivo` | UUID v4 estable en almacenamiento seguro | `IdentidadDispositivoSegura` | `IdentidadDispositivoFalsa` |
/// | `AlmacenSeguro` | Keystore/Keychain para el token de licencia | `AlmacenSeguroFlutter` | `AlmacenSeguroFalso` |
/// | `CompartirArchivo` | Comprobante por WhatsApp (imagen / PDF) | `CompartirArchivoSharePlus` | `CompartirArchivoFalso` |
///
/// `ImpresoraTickets`, `EscanerCodigos` y `CompartirArchivo` son **canónicos en
/// este paquete**. `IdentidadDispositivo` y `AlmacenSeguro` **no**: sus
/// contratos viven en `pagoya_core` (`dispositivo/contratos.dart`) porque el
/// núcleo los consume para validar el claim `hwid` del token y para guardarlo
/// cifrado, y no puede depender del paquete de hardware sin romper su
/// invariante de Dart puro (MOBILE-ARQUITECTURA §4.2). Aquí solo se
/// implementan, y se re-exportan por comodidad.
///
/// Las implementaciones **falsas**, agrupadas en `HardwarePagoYa.falso()`,
/// permiten correr toda la app en el emulador y en `flutter test` sin
/// impresora, sin cámara y sin Keychain.
///
/// ## Compatibilidad (leer antes de prometerle algo a un cliente)
///
/// **Android**
/// - `minSdkVersion 23` (Android 6.0). Requerido por `EncryptedSharedPreferences`
///   de `flutter_secure_storage` y por `flutter_blue_plus`.
/// - `targetSdkVersion 36` (Android 16), exigido por Play Store desde 2026-08.
/// - Impresoras: **Bluetooth SPP clásico** (el 90 % de las térmicas baratas que
///   se venden en Perú: clones Xprinter XP-58, Goojprt PT-210/MTP-2,
///   Bixolon SPP-R200, Epson TM-P20, "POS-58" genéricas) vía
///   `print_bluetooth_thermal`. La impresora debe estar **emparejada desde los
///   ajustes de Android**: SPP no descubre dispositivos nuevos desde la app.
/// - Respaldo BLE (`flutter_blue_plus`) para las térmicas modernas que solo
///   exponen GATT (Munbyn, algunas Xprinter 2023+).
///
/// **iOS**
/// - Mínimo **iOS 13.0**.
/// - ⚠️ **El SPP clásico NO está disponible para apps de terceros en iOS** sin
///   certificación MFi de Apple. En iOS la impresión funciona **solo con
///   impresoras BLE**. Es una limitación de la plataforma, no del código:
///   `ImpresoraTicketsBluetooth` lo detecta y devuelve
///   `CausaFalloImpresion.noSoportado` con un mensaje claro.
///
/// **Fabricantes agresivos (Xiaomi/MIUI-HyperOS, Huawei/EMUI, Oppo/ColorOS,
/// Vivo, realme)** matan procesos en segundo plano de forma agresiva. Por eso
/// este paquete **no monta ningún worker de fondo**: la conexión Bluetooth se
/// abre bajo demanda al imprimir y se reintenta si murió. Nada crítico depende
/// de un proceso que asumamos vivo. Ver `ImpresoraTicketsBluetooth` para el
/// detalle de la política de reconexión.
library;

export 'src/almacen/almacen_seguro_falso.dart';
export 'src/almacen/almacen_seguro_flutter.dart';
export 'src/almacen/opciones_almacen_seguro.dart';
export 'src/compartir/compartir_falso.dart';
export 'src/compartir/compartir_share_plus.dart';
export 'src/compartir/contrato_compartir.dart';
export 'src/compartir/renderizador_imagen_ticket.dart';
export 'src/compartir/renderizador_pdf_ticket.dart';
export 'src/escaner/contrato_escaner.dart';
export 'src/escaner/escaner_falso.dart';
export 'src/escaner/escaner_mobile_scanner.dart';
export 'src/hardware_falso.dart';
export 'src/identidad/contrato_identidad.dart';
export 'src/identidad/identidad_falsa.dart';
export 'src/identidad/identidad_segura.dart';
export 'src/impresion/codificador_cp850.dart';
export 'src/impresion/configuracion_impresion.dart';
export 'src/impresion/contrato_impresora.dart';
export 'src/impresion/generador_escpos.dart';
export 'src/impresion/impresora_bluetooth.dart';
export 'src/impresion/impresora_falsa.dart';
export 'src/impresion/renderizador_ticket.dart';
export 'src/impresion/transporte.dart';
export 'src/modelo/resultados.dart';
export 'src/modelo/ticket.dart';
export 'src/permisos/permisos_hardware.dart';