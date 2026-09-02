import 'dart:typed_data';

import '../impresion/configuracion_impresion.dart';
import '../impresion/renderizador_ticket.dart';
import '../modelo/resultados.dart';
import '../modelo/ticket.dart';
import 'contrato_compartir.dart';

/// Un intento de compartir, registrado por [CompartirArchivoFalso].
class CompartidoSimulado {
  const CompartidoSimulado({
    required this.mensaje,
    this.nombreArchivo,
    this.mimeType,
    this.bytes,
    this.telefono,
  });

  final String mensaje;
  final String? nombreArchivo;
  final String? mimeType;
  final int? bytes;

  /// Solo para [CompartirArchivoFalso.abrirChatWhatsApp].
  final String? telefono;

  @override
  String toString() =>
      'CompartidoSimulado(${nombreArchivo ?? "texto"}, tel: $telefono)';
}

/// Implementación **falsa** de [CompartirArchivo].
///
/// No abre ninguna hoja del sistema: registra lo que se habría compartido en
/// [compartidos]. En `flutter test` es la única opción (`share_plus` necesita
/// canal de plataforma) y en el emulador evita el diálogo del sistema en cada
/// venta de prueba.
class CompartirArchivoFalso implements CompartirArchivo {
  CompartirArchivoFalso({
    this.hayWhatsapp = true,
    this.simularCancelacion = false,
    this.fallarSiempre = false,
    RenderizadorTicket renderizador = const RenderizadorTicket(),
  }) : _renderizador = renderizador;

  final RenderizadorTicket _renderizador;

  /// Qué devuelve [whatsappDisponible].
  bool hayWhatsapp;

  /// Simula que el usuario cierra la hoja sin elegir app.
  bool simularCancelacion;

  /// Simula un fallo del sistema al compartir.
  bool fallarSiempre;

  /// Todo lo que se intentó compartir, en orden.
  final List<CompartidoSimulado> compartidos = <CompartidoSimulado>[];

  /// Cuántas veces se llamó a [limpiarTemporales].
  int limpiezas = 0;

  ResultadoCompartir _resultado({String? ruta}) {
    if (fallarSiempre) {
      return ResultadoCompartir.fallo('Fallo simulado al compartir.');
    }
    if (simularCancelacion) return ResultadoCompartir.cancelado();
    return ResultadoCompartir.ok(rutaArchivo: ruta);
  }

  @override
  Future<ResultadoCompartir> compartirComprobante(
    TicketVenta ticket, {
    FormatoComprobante formato = FormatoComprobante.imagen,
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String? mensaje,
  }) async {
    final extension = switch (formato) {
      FormatoComprobante.imagen => 'png',
      FormatoComprobante.pdf => 'pdf',
      FormatoComprobante.texto => 'txt',
    };
    compartidos.add(CompartidoSimulado(
      mensaje: mensaje ?? _renderizador.comoTextoPlano(ticket, config: config),
      nombreArchivo: '${ticket.nombreArchivoSugerido}.$extension',
      mimeType: switch (formato) {
        FormatoComprobante.imagen => 'image/png',
        FormatoComprobante.pdf => 'application/pdf',
        FormatoComprobante.texto => 'text/plain',
      },
    ));
    return _resultado(ruta: '/tmp/${ticket.nombreArchivoSugerido}.$extension');
  }

  @override
  Future<ResultadoCompartir> compartirBytes(
    Uint8List bytes, {
    required String nombreArchivo,
    required String mimeType,
    String? mensaje,
  }) async {
    compartidos.add(CompartidoSimulado(
      mensaje: mensaje ?? '',
      nombreArchivo: nombreArchivo,
      mimeType: mimeType,
      bytes: bytes.length,
    ));
    return _resultado(ruta: '/tmp/$nombreArchivo');
  }

  @override
  Future<ResultadoCompartir> compartirArchivoEnDisco(
    String ruta, {
    String? mensaje,
  }) async {
    compartidos.add(CompartidoSimulado(
      mensaje: mensaje ?? '',
      nombreArchivo: ruta.split(RegExp(r'[/\\]')).last,
    ));
    return _resultado(ruta: ruta);
  }

  @override
  Future<ResultadoCompartir> compartirTexto(String texto) async {
    compartidos.add(CompartidoSimulado(mensaje: texto));
    return _resultado();
  }

  @override
  Future<bool> get whatsappDisponible async => hayWhatsapp;

  @override
  Future<ResultadoCompartir> abrirChatWhatsApp({
    required String telefono,
    required String mensaje,
  }) async {
    compartidos.add(CompartidoSimulado(mensaje: mensaje, telefono: telefono));
    return _resultado();
  }

  @override
  Future<void> limpiarTemporales() async => limpiezas++;
}