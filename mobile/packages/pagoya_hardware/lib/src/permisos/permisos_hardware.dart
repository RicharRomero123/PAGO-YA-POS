import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../modelo/resultados.dart';

/// Gestión de permisos de runtime del hardware.
///
/// **Aquí es donde se pierde el tiempo si no se cuida.** El motivo número uno
/// de "no encuentra mi impresora" no es el Bluetooth: es haber pedido mal los
/// permisos. Este archivo concentra esas reglas para que ninguna pantalla las
/// reimplemente a medias.
///
/// ## Bluetooth
///
/// - **Android 12 (API 31) o superior**: `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT`
///   son permisos de *runtime* y hay que pedirlos explícitamente. Los antiguos
///   `BLUETOOTH` / `BLUETOOTH_ADMIN` ya no sirven y en el manifiesto van con
///   `android:maxSdkVersion="30"`.
/// - **Android 11 (API 30) o inferior**: `BLUETOOTH` / `BLUETOOTH_ADMIN` son de
///   instalación (no se piden), pero **escanear BLE exige ubicación fina**.
///   Por eso en esas versiones se pide `ACCESS_FINE_LOCATION`: no usamos la
///   ubicación para nada, es un requisito histórico de Android.
/// - En Android 12+ declaramos `android:usesPermissionFlags="neverForLocation"`
///   en `BLUETOOTH_SCAN`, que es justamente la promesa de no derivar ubicación
///   del escaneo — y así **no** hay que pedir permiso de ubicación.
/// - **iOS**: no hay permiso de Bluetooth que pedir por API; el sistema muestra
///   el diálogo la primera vez que se usa CoreBluetooth, tomando el texto de
///   `NSBluetoothAlwaysUsageDescription` en `Info.plist`.
///
/// ## Cámara
///
/// Runtime en ambas plataformas. En iOS además hace falta
/// `NSCameraUsageDescription` **explicando el porqué**: Apple rechaza los
/// textos genéricos tipo "esta app usa la cámara".
///
/// ## Notificaciones
///
/// `POST_NOTIFICATIONS` es de runtime desde Android 13 (API 33). Solo se pide
/// si la app realmente va a notificar; pedirlo "por si acaso" al arrancar es
/// una forma barata de que el usuario diga que no a todo.
class PermisosHardware {
  const PermisosHardware();

  static AndroidDeviceInfo? _cacheAndroid;

  /// Nivel de API de Android, o `null` en iOS. Se cachea: la consulta cruza el
  /// canal de plataforma y no cambia durante la sesión.
  Future<int?> nivelApiAndroid() async {
    if (!Platform.isAndroid) return null;
    try {
      _cacheAndroid ??= await DeviceInfoPlugin().androidInfo;
      return _cacheAndroid!.version.sdkInt;
    } catch (_) {
      // Ante la duda, asumir Android 12+ es lo seguro: pedimos los permisos
      // nuevos, que es el caso que rompe si se omite.
      return 31;
    }
  }

  /// Pide lo necesario para descubrir y conectar impresoras Bluetooth,
  /// ramificando por versión de Android.
  Future<EstadoPermiso> asegurarBluetooth() async {
    if (Platform.isIOS) {
      // CoreBluetooth pide el permiso solo al primer uso, con el texto de
      // Info.plist. No hay nada que solicitar desde aquí.
      return EstadoPermiso.concedido;
    }
    if (!Platform.isAndroid) return EstadoPermiso.noDisponible;

    final api = await nivelApiAndroid() ?? 31;

    final requeridos = <Permission>[
      if (api >= 31) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ] else
        // Android <= 11: escanear BLE exige ubicación fina. BLUETOOTH y
        // BLUETOOTH_ADMIN son de instalación y no se piden.
        Permission.locationWhenInUse,
    ];

    return _solicitarTodos(requeridos);
  }

  /// Permiso de cámara para el escáner de códigos de barras.
  Future<EstadoPermiso> asegurarCamara() => _solicitar(Permission.camera);

  /// Estado del permiso de cámara **sin** mostrar el diálogo. Sirve para
  /// decidir si la pantalla debe explicar antes de pedir (mejor tasa de
  /// aceptación que disparar el diálogo a bocajarro).
  Future<EstadoPermiso> estadoCamara() async {
    try {
      return _traducir(await Permission.camera.status);
    } catch (_) {
      return EstadoPermiso.noDisponible;
    }
  }

  /// Notificaciones. Solo tiene efecto en Android 13+ e iOS; en Android 12 y
  /// anteriores devuelve concedido porque no existe el permiso.
  Future<EstadoPermiso> asegurarNotificaciones() async {
    if (Platform.isAndroid) {
      final api = await nivelApiAndroid() ?? 33;
      if (api < 33) return EstadoPermiso.concedido;
    }
    return _solicitar(Permission.notification);
  }

  /// Abre la pantalla de ajustes de la app. Único camino cuando el usuario
  /// marcó "no volver a preguntar".
  Future<bool> abrirAjustesDeLaApp() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<EstadoPermiso> _solicitar(Permission permiso) async {
    try {
      final actual = await permiso.status;
      if (actual.isGranted || actual.isLimited) return EstadoPermiso.concedido;
      if (actual.isPermanentlyDenied) {
        return EstadoPermiso.denegadoPermanentemente;
      }
      return _traducir(await permiso.request());
    } catch (_) {
      return EstadoPermiso.noDisponible;
    }
  }

  Future<EstadoPermiso> _solicitarTodos(List<Permission> permisos) async {
    if (permisos.isEmpty) return EstadoPermiso.concedido;
    try {
      final pendientes = <Permission>[];
      for (final p in permisos) {
        final s = await p.status;
        if (s.isPermanentlyDenied) return EstadoPermiso.denegadoPermanentemente;
        if (!s.isGranted && !s.isLimited) pendientes.add(p);
      }
      if (pendientes.isEmpty) return EstadoPermiso.concedido;

      final resultados = await pendientes.request();
      var peor = EstadoPermiso.concedido;
      for (final estado in resultados.values) {
        final traducido = _traducir(estado);
        if (traducido == EstadoPermiso.denegadoPermanentemente) {
          return EstadoPermiso.denegadoPermanentemente;
        }
        if (traducido != EstadoPermiso.concedido) peor = traducido;
      }
      return peor;
    } catch (_) {
      return EstadoPermiso.noDisponible;
    }
  }

  static EstadoPermiso _traducir(PermissionStatus estado) {
    if (estado.isGranted || estado.isLimited) return EstadoPermiso.concedido;
    if (estado.isPermanentlyDenied) {
      return EstadoPermiso.denegadoPermanentemente;
    }
    if (estado.isRestricted) return EstadoPermiso.noDisponible;
    return EstadoPermiso.denegado;
  }
}

/// Implementación falsa: concede todo sin tocar el canal de plataforma.
/// Necesaria en `flutter test`, donde `permission_handler` no tiene backend.
///
/// Extiende en vez de implementar para heredar los helpers privados; solo se
/// sobrescribe la superficie pública.
class PermisosHardwareFalsos extends PermisosHardware {
  const PermisosHardwareFalsos({this.conceder = true});

  final bool conceder;

  EstadoPermiso get _r =>
      conceder ? EstadoPermiso.concedido : EstadoPermiso.denegado;

  @override
  Future<int?> nivelApiAndroid() async => 34;

  @override
  Future<EstadoPermiso> asegurarBluetooth() async => _r;

  @override
  Future<EstadoPermiso> asegurarCamara() async => _r;

  @override
  Future<EstadoPermiso> estadoCamara() async => _r;

  @override
  Future<EstadoPermiso> asegurarNotificaciones() async => _r;

  @override
  Future<bool> abrirAjustesDeLaApp() async => true;
}