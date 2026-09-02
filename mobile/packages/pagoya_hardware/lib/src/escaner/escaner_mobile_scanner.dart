import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modelo/resultados.dart';
import '../permisos/permisos_hardware.dart';
import 'contrato_escaner.dart';

/// Implementación real de [EscanerCodigos] con `mobile_scanner` (ML Kit en
/// Android, Vision en iOS).
///
/// ## Decisiones que se notan en la caja
///
/// - **`DetectionSpeed.noDuplicates` + antirrebote propio.** ML Kit reporta el
///   mismo código en cada frame; sin filtrar, escanear una Inca Kola agrega 25
///   unidades. El filtro por valor+tiempo vive aquí, no en la pantalla.
/// - **Formatos limitados** a los de retail peruano. El detector prueba menos
///   decodificadores por frame y engancha visiblemente más rápido en gama baja.
/// - **Feedback sonoro y háptico** al leer. El cajero mira el producto, no la
///   pantalla: el bip es la confirmación.
/// - **Linterna** expuesta como estado observable, porque las bodegas están
///   a media luz y es lo primero que se toca.
/// - **Autoenfoque**: se deja el modo continuo del sistema; forzar
///   `cameraResolution` alta empeora el enfoque en gama baja, así que no se
///   toca.
class EscanerMobileScanner implements EscanerCodigos {
  EscanerMobileScanner({PermisosHardware? permisos})
      : _permisos = permisos ?? const PermisosHardware();

  final PermisosHardware _permisos;

  @override
  Future<EstadoPermiso> estadoPermiso() => _permisos.estadoCamara();

  @override
  Future<EstadoPermiso> solicitarPermiso() => _permisos.asegurarCamara();

  @override
  Future<SesionEscaneo> abrirSesion({
    ModoEscaneo modo = ModoEscaneo.unico,
    Duration ignorarRepetidoDurante = const Duration(seconds: 2),
    bool conSonido = true,
    bool conVibracion = true,
    bool linternaAlIniciar = false,
    List<FormatoCodigo> formatos = FormatoCodigo.retailPeru,
  }) async {
    final controlador = MobileScannerController(
      // El widget dibuja pero no detecta duplicados consecutivos; el
      // antirrebote fino lo hace la sesión.
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: 250,
      facing: CameraFacing.back,
      torchEnabled: linternaAlIniciar,
      formats: formatos.map(_aFormatoNativo).toList(growable: false),
      autoStart: false,
    );

    final sesion = _SesionMobileScanner(
      controlador: controlador,
      modo: modo,
      ignorarRepetidoDurante: ignorarRepetidoDurante,
      conSonido: conSonido,
      conVibracion: conVibracion,
    );
    await sesion._iniciar();
    return sesion;
  }

  static BarcodeFormat _aFormatoNativo(FormatoCodigo f) => switch (f) {
        FormatoCodigo.ean13 => BarcodeFormat.ean13,
        FormatoCodigo.ean8 => BarcodeFormat.ean8,
        FormatoCodigo.upcA => BarcodeFormat.upcA,
        FormatoCodigo.upcE => BarcodeFormat.upcE,
        FormatoCodigo.code128 => BarcodeFormat.code128,
        FormatoCodigo.code39 => BarcodeFormat.code39,
        FormatoCodigo.code93 => BarcodeFormat.code93,
        FormatoCodigo.itf => BarcodeFormat.itf,
        FormatoCodigo.codabar => BarcodeFormat.codabar,
        FormatoCodigo.qr => BarcodeFormat.qrCode,
        FormatoCodigo.dataMatrix => BarcodeFormat.dataMatrix,
        FormatoCodigo.pdf417 => BarcodeFormat.pdf417,
        FormatoCodigo.aztec => BarcodeFormat.aztec,
      };
}

class _SesionMobileScanner implements SesionEscaneo {
  _SesionMobileScanner({
    required MobileScannerController controlador,
    required this.modo,
    required this.ignorarRepetidoDurante,
    required this.conSonido,
    required this.conVibracion,
  }) : _controlador = controlador;

  final MobileScannerController _controlador;
  final ModoEscaneo modo;
  final Duration ignorarRepetidoDurante;
  final bool conSonido;
  final bool conVibracion;

  final StreamController<CodigoLeido> _lecturas =
      StreamController<CodigoLeido>.broadcast();
  final ValueNotifier<bool> _linternaDisponible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _linternaEncendida = ValueNotifier<bool>(false);

  /// Último instante en que se aceptó cada código, para el antirrebote.
  final Map<String, DateTime> _ultimaLectura = <String, DateTime>{};

  StreamSubscription<BarcodeCapture>? _sub;
  bool _cerrada = false;
  bool _pausada = false;

  Future<void> _iniciar() async {
    _controlador.addListener(_sincronizarEstado);
    _sub = _controlador.barcodes.listen(_alDetectar, onError: (Object _) {
      // Un error del detector no debe tumbar la pantalla; la cámara sigue.
    });
    try {
      await _controlador.start();
    } catch (_) {
      // Permiso denegado o cámara ocupada: la UI lo verá porque no llegan
      // lecturas y `MobileScanner` pinta su propio estado de error.
    }
    _sincronizarEstado();
  }

  void _sincronizarEstado() {
    final estado = _controlador.value;
    _linternaDisponible.value = estado.torchState != TorchState.unavailable;
    _linternaEncendida.value = estado.torchState == TorchState.on;
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_cerrada || _pausada) return;
    for (final barcode in captura.barcodes) {
      final valor = barcode.rawValue?.trim();
      if (valor == null || valor.isEmpty) continue;

      // Antirrebote: el mismo código no se acepta dos veces seguidas dentro
      // de la ventana. Sin esto, el modo continuo es inutilizable.
      final ahora = DateTime.now();
      final previa = _ultimaLectura[valor];
      if (previa != null && ahora.difference(previa) < ignorarRepetidoDurante) {
        continue;
      }
      _ultimaLectura[valor] = ahora;

      _confirmar();
      _lecturas.add(CodigoLeido(
        valor: valor,
        formato: barcode.format.name,
        momento: ahora,
      ));

      if (modo == ModoEscaneo.unico) {
        // Se pausa (no se cierra): la pantalla decide si cerrar o reanudar
        // tras procesar el producto.
        unawaited(pausar());
        return;
      }
    }
  }

  /// Confirmación al leer: háptica + clic del sistema. No se usa un plugin de
  /// audio para no arrastrar una dependencia por un bip.
  void _confirmar() {
    if (conVibracion) {
      HapticFeedback.mediumImpact().ignore();
    }
    if (conSonido) {
      SystemSound.play(SystemSoundType.click).ignore();
    }
  }

  @override
  Stream<CodigoLeido> get lecturas => _lecturas.stream;

  @override
  ValueListenable<bool> get linternaDisponible => _linternaDisponible;

  @override
  ValueListenable<bool> get linternaEncendida => _linternaEncendida;

  @override
  Future<void> alternarLinterna() async {
    try {
      await _controlador.toggleTorch();
    } catch (_) {
      // Teléfono sin linterna: se ignora, el botón queda deshabilitado por
      // `linternaDisponible`.
    }
    _sincronizarEstado();
  }

  @override
  Future<void> alternarCamara() async {
    try {
      await _controlador.switchCamera();
    } catch (_) {}
    _sincronizarEstado();
  }

  @override
  Future<void> pausar() async {
    if (_cerrada || _pausada) return;
    _pausada = true;
    try {
      await _controlador.stop();
    } catch (_) {}
  }

  @override
  Future<void> reanudar() async {
    if (_cerrada || !_pausada) return;
    _pausada = false;
    try {
      await _controlador.start();
    } catch (_) {}
  }

  @override
  Widget construirVista({
    BoxFit ajuste = BoxFit.cover,
    Widget? superposicion,
  }) {
    final camara = MobileScanner(
      controller: _controlador,
      fit: ajuste,
      // Un fallo de cámara no puede mostrar un stack trace al bodeguero.
      // Firma de 3 parámetros: es la de `mobile_scanner` 5.x, que es la
      // versión fijada en el pubspec. En 6.x el `child` desaparece.
      errorBuilder: (context, error, child) => const _CamaraNoDisponible(),
    );
    if (superposicion == null) return camara;
    return Stack(fit: StackFit.expand, children: [camara, superposicion]);
  }

  @override
  Future<void> cerrar() async {
    if (_cerrada) return;
    _cerrada = true;
    _controlador.removeListener(_sincronizarEstado);
    await _sub?.cancel();
    try {
      await _controlador.dispose();
    } catch (_) {}
    _linternaDisponible.dispose();
    _linternaEncendida.dispose();
    await _lecturas.close();
  }
}

/// Mensaje cuando la cámara no arranca. En castellano llano, sin códigos de
/// error: el usuario es el dueño de una bodega, no un desarrollador.
class _CamaraNoDisponible extends StatelessWidget {
  const _CamaraNoDisponible();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1B1B1B),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se pudo abrir la cámara.\n\n'
            'Revisa que le hayas dado permiso a PagoYa y que ninguna otra app '
            'la esté usando. Igual puedes escribir el código a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFEFEFEF), fontSize: 15),
          ),
        ),
      ),
    );
  }
}