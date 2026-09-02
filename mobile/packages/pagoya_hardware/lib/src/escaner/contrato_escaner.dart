// `widgets.dart` re-exporta `foundation.dart`, de donde sale `ValueListenable`.
import 'package:flutter/widgets.dart';

import '../modelo/resultados.dart';

/// Cómo se comporta la sesión de escaneo.
enum ModoEscaneo {
  /// Lee **un** código y se detiene. Es el modo de la pantalla de cobro: se
  /// escanea, se agrega al carrito y la cámara se cierra.
  unico,

  /// Sigue leyendo. Es el modo de **carga de inventario en lote**: el dueño
  /// pasa 200 productos por la cámara sin tocar la pantalla entre uno y otro.
  /// Aquí es donde se gana la comparación contra el POS de PC.
  continuo,
}

/// Un código leído por la cámara.
class CodigoLeido {
  const CodigoLeido({
    required this.valor,
    required this.formato,
    required this.momento,
  });

  /// Contenido crudo (`rawValue`). Para EAN-13 es el código de barras del
  /// producto: se busca tal cual en `productos.codigo`.
  final String valor;

  /// Nombre del formato ('ean13', 'qrCode', 'code128'...). Informativo.
  final String formato;

  final DateTime momento;

  @override
  String toString() => '$valor ($formato)';
}

/// Sesión de cámara abierta. Vive mientras la pantalla del escáner está
/// montada; hay que llamar a [cerrar] al desmontarla o la cámara se queda
/// encendida gastando batería.
abstract interface class SesionEscaneo {
  /// Códigos leídos. En [ModoEscaneo.unico] emite uno y se pausa sola.
  Stream<CodigoLeido> get lecturas;

  /// `true` si el dispositivo tiene linterna. Muchas tablets baratas no.
  ValueListenable<bool> get linternaDisponible;

  /// Estado actual de la linterna.
  ValueListenable<bool> get linternaEncendida;

  /// Enciende/apaga la linterna. **Imprescindible**: media bodega en Perú está
  /// a media luz y sin linterna el lector no engancha el código.
  Future<void> alternarLinterna();

  /// Cambia entre cámara trasera y frontal.
  Future<void> alternarCamara();

  /// Pausa la detección sin apagar la cámara (p. ej. mientras se muestra un
  /// diálogo de "producto no encontrado").
  Future<void> pausar();

  /// Reanuda la detección tras [pausar].
  Future<void> reanudar();

  /// **Vista de la cámara.** La pantalla incrusta este widget en su layout; no
  /// conoce `mobile_scanner`. La implementación falsa devuelve un panel con
  /// botones para simular lecturas en el emulador.
  ///
  /// [superposicion] se dibuja encima (marco de puntería, contador de lote,
  /// botones); lo aporta `mobile-ux`, no este paquete.
  Widget construirVista({
    BoxFit ajuste = BoxFit.cover,
    Widget? superposicion,
  });

  /// Cierra la cámara y libera el stream. Idempotente.
  Future<void> cerrar();
}

/// **Interfaz del escáner de códigos de barras.**
///
/// Diferenciador competitivo frente al POS de PC: allá hace falta un lector
/// láser de S/ 80–150; aquí la cámara del teléfono ya lo hace. Por eso la
/// calidad del detalle importa (enfoque, linterna, feedback, modo lote) tanto
/// como que funcione.
abstract interface class EscanerCodigos {
  /// Estado del permiso de cámara sin mostrar diálogo.
  Future<EstadoPermiso> estadoPermiso();

  /// Pide el permiso de cámara. Conviene llamarlo **después** de explicar para
  /// qué sirve: el diálogo a bocajarro se deniega mucho más.
  Future<EstadoPermiso> solicitarPermiso();

  /// Abre la cámara.
  ///
  /// - [modo]: uno o continuo.
  /// - [ignorarRepetidoDurante]: en modo continuo, no vuelve a emitir el mismo
  ///   código antes de este lapso. Sin esto, un código quieto frente a la
  ///   cámara se lee 30 veces por segundo y se agregan 30 unidades.
  /// - [conSonido] / [conVibracion]: confirmación al leer. El cajero no mira la
  ///   pantalla mientras pasa productos; el "bip" es la única señal de que
  ///   enganchó.
  /// - [formatos]: limitar a los formatos esperados acelera el enganche. Por
  ///   defecto se leen los de retail peruano (EAN-13/8, UPC, Code 128/39) más
  ///   QR (Yape/Plin).
  Future<SesionEscaneo> abrirSesion({
    ModoEscaneo modo = ModoEscaneo.unico,
    Duration ignorarRepetidoDurante = const Duration(seconds: 2),
    bool conSonido = true,
    bool conVibracion = true,
    bool linternaAlIniciar = false,
    List<FormatoCodigo> formatos = FormatoCodigo.retailPeru,
  });
}

/// Formatos de código soportados, sin exponer el enum de `mobile_scanner`.
enum FormatoCodigo {
  /// El estándar del retail: casi todo producto envasado en Perú lo trae.
  ean13,
  ean8,
  upcA,
  upcE,

  /// Etiquetas impresas por el propio negocio (balanzas, farmacia).
  code128,
  code39,
  code93,
  itf,
  codabar,

  /// QR: pagos Yape/Plin y etiquetas internas.
  qr,
  dataMatrix,
  pdf417,
  aztec;

  /// Conjunto por defecto: lo que realmente circula en una bodega peruana.
  /// Limitar la lista hace que el detector enganche notablemente más rápido
  /// que dejándolo en "todos los formatos".
  static const List<FormatoCodigo> retailPeru = <FormatoCodigo>[
    FormatoCodigo.ean13,
    FormatoCodigo.ean8,
    FormatoCodigo.upcA,
    FormatoCodigo.upcE,
    FormatoCodigo.code128,
    FormatoCodigo.code39,
    FormatoCodigo.itf,
    FormatoCodigo.qr,
  ];
}