import 'package:pagoya_core/pagoya_core.dart'
    show AlmacenSeguro, IdentidadDispositivo;

import 'almacen/almacen_seguro_falso.dart';
import 'almacen/almacen_seguro_flutter.dart';
import 'compartir/compartir_falso.dart';
import 'compartir/compartir_share_plus.dart';
import 'compartir/contrato_compartir.dart';
import 'escaner/contrato_escaner.dart';
import 'escaner/escaner_falso.dart';
import 'escaner/escaner_mobile_scanner.dart';
import 'identidad/identidad_falsa.dart';
import 'identidad/identidad_segura.dart';
import 'impresion/contrato_impresora.dart';
import 'impresion/impresora_bluetooth.dart';
import 'impresion/impresora_falsa.dart';

/// **Fachada de la capa de plataforma.** Las cinco capacidades, juntas.
///
/// `pagoya_movil` crea **una** de estas en el composition root y la publica con
/// Riverpod; ninguna pantalla construye implementaciones a mano. Cambiar de
/// real a falsa es una línea, que es justo lo que permite correr todo en el
/// emulador.
///
/// Tres de los cinco puertos son canónicos de este paquete
/// ([ImpresoraTickets], [EscanerCodigos], [CompartirArchivo]); los otros dos
/// ([IdentidadDispositivo] y [AlmacenSeguro]) son de `pagoya_core`, porque el
/// núcleo los consume para validar y guardar la licencia y no puede depender de
/// un paquete con plugins. Aquí solo se implementan y se ensamblan.
///
/// ```dart
/// // main.dart (dueño: mobile-lead)
/// final hardware = const bool.fromEnvironment('SIN_HARDWARE')
///     ? HardwarePagoYa.falso()
///     : HardwarePagoYa.real();
///
/// // El módulo de licencia se monta sobre dos de estos puertos:
/// final licencia = construirServicioLicencia(
///   identidad: hardware.identidad,
///   almacen: AlmacenLicenciaSegura(hardware.almacenSeguro),
/// );
///
/// await hardware.impresora.restaurarImpresoraGuardada();
/// ```
///
/// ```powershell
/// # correr en el emulador sin impresora, sin cámara y sin Keystore
/// flutter run --dart-define=SIN_HARDWARE=true
/// ```
class HardwarePagoYa {
  const HardwarePagoYa({
    required this.impresora,
    required this.escaner,
    required this.identidad,
    required this.almacenSeguro,
    required this.compartir,
  });

  /// Implementaciones reales (teléfono físico).
  factory HardwarePagoYa.real() => HardwarePagoYa(
        impresora: ImpresoraTicketsBluetooth(),
        escaner: EscanerMobileScanner(),
        identidad: IdentidadDispositivoSegura(),
        almacenSeguro: AlmacenSeguroFlutter(),
        compartir: CompartirArchivoSharePlus(),
      );

  /// Implementaciones falsas (emulador, tests, demos).
  ///
  /// Con [todoFalla] en `true` la impresora y el compartir devuelven error
  /// siempre: es el modo para verificar que **la venta se completa igual**, que
  /// es una regla de negocio, no un detalle de UI. El almacén seguro **no** se
  /// rompe con ese interruptor: sin licencia la app ni siquiera entra al POS,
  /// así que no habría nada que probar. Para ensayar un Keystore caído se usa
  /// `AlmacenSeguroFalso.fallarLectura` directamente.
  factory HardwarePagoYa.falso({bool todoFalla = false}) => HardwarePagoYa(
        impresora: ImpresoraTicketsFalsa(fallarSiempre: todoFalla),
        escaner: EscanerFalso(),
        identidad: IdentidadDispositivoFalsa(),
        almacenSeguro: AlmacenSeguroFalso(),
        compartir: CompartirArchivoFalso(fallarSiempre: todoFalla),
      );

  /// Ticket térmico ESC/POS por Bluetooth.
  final ImpresoraTickets impresora;

  /// Cámara como lector de códigos de barras.
  final EscanerCodigos escaner;

  /// Id estable de este dispositivo (UUID v4 persistido). Lo consume el
  /// licenciamiento para registrar el asiento con `POST /devices`.
  final IdentidadDispositivo identidad;

  /// Keystore/Keychain para secretos pequeños. Lo envuelve
  /// `AlmacenLicenciaSegura` para guardar el token y la clave de licencia.
  final AlmacenSeguro almacenSeguro;

  /// Comprobante por WhatsApp (imagen o PDF).
  final CompartirArchivo compartir;

  /// Libera lo que haya que liberar al cerrar la app.
  ///
  /// Solo la impresora tiene recursos vivos (socket Bluetooth y un
  /// `StreamController` de estado). El escáner se libera por sesión, y la
  /// identidad y el almacén seguro no abren nada.
  Future<void> liberar() => impresora.liberar();
}