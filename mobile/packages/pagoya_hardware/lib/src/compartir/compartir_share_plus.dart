import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../impresion/configuracion_impresion.dart';
import '../impresion/renderizador_ticket.dart';
import '../modelo/resultados.dart';
import '../modelo/ticket.dart';
import 'contrato_compartir.dart';
import 'renderizador_imagen_ticket.dart';
import 'renderizador_pdf_ticket.dart';

/// Implementación real de [CompartirArchivo] con `share_plus` + `url_launcher`.
///
/// ## Notas de plataforma
///
/// - **Android 11+ (API 30)**: para que [whatsappDisponible] funcione hace
///   falta declarar `<queries>` con `com.whatsapp` y `com.whatsapp.w4b` en el
///   manifiesto. Sin eso, `canLaunchUrl` devuelve `false` aunque WhatsApp esté
///   instalado, y el botón principal diría "Compartir" en un teléfono que sí
///   tiene WhatsApp. Ya está declarado en el `AndroidManifest.xml` de la app.
/// - **iOS**: hay que declarar el esquema `whatsapp` en
///   `LSApplicationQueriesSchemes` de `Info.plist`. También está puesto.
/// - **iPad**: `share_plus` exige el origen del popover o lanza. Se pasa un
///   rectángulo por defecto para no romper en tablets.
///
/// API de `share_plus`: se usa `Share.shareXFiles(...)` / `Share.share(...)`,
/// que es la superficie de la **versión 10.x fijada en el pubspec**. Si algún
/// día se sube a `share_plus` 11+, el equivalente es
/// `SharePlus.instance.share(ShareParams(...))` y hay que cambiar los tres
/// puntos de llamada de este archivo (no hay más).
class CompartirArchivoSharePlus implements CompartirArchivo {
  CompartirArchivoSharePlus({
    RenderizadorImagenTicket? renderizadorImagen,
    RenderizadorPdfTicket? renderizadorPdf,
    RenderizadorTicket renderizadorTexto = const RenderizadorTicket(),
  })  : _imagen = renderizadorImagen ?? const RenderizadorImagenTicket(),
        _pdf = renderizadorPdf ?? const RenderizadorPdfTicket(),
        _texto = renderizadorTexto;

  final RenderizadorImagenTicket _imagen;
  final RenderizadorPdfTicket _pdf;
  final RenderizadorTicket _texto;

  /// Rectángulo de origen del popover. Obligatorio en iPad; en teléfono se
  /// ignora. Sin esto, `share_plus` lanza en tablets iOS.
  static const Rect _origenPopoverIpad = Rect.fromLTWH(0, 0, 1, 1);

  @override
  Future<ResultadoCompartir> compartirComprobante(
    TicketVenta ticket, {
    FormatoComprobante formato = FormatoComprobante.imagen,
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String? mensaje,
  }) async {
    final texto = mensaje ?? _mensajePorDefecto(ticket);
    try {
      switch (formato) {
        case FormatoComprobante.texto:
          return await compartirTexto(
            '$texto\n\n${_texto.comoTextoPlano(ticket, config: config)}',
          );

        case FormatoComprobante.imagen:
          final bytes = await _imagen.renderizarPng(ticket, config: config);
          return await compartirBytes(
            bytes,
            nombreArchivo: '${ticket.nombreArchivoSugerido}.png',
            mimeType: 'image/png',
            mensaje: texto,
          );

        case FormatoComprobante.pdf:
          final bytes = await _pdf.renderizarPdf(ticket, config: config);
          return await compartirBytes(
            bytes,
            nombreArchivo: '${ticket.nombreArchivoSugerido}.pdf',
            mimeType: 'application/pdf',
            mensaje: texto,
          );
      }
    } catch (_) {
      // Si el render falló (memoria, fuente rara), al menos va el texto: el
      // cliente igual recibe su comprobante.
      try {
        return await compartirTexto(
          '$texto\n\n${_texto.comoTextoPlano(ticket, config: config)}',
        );
      } catch (_) {
        return ResultadoCompartir.fallo(
          'No se pudo preparar el comprobante para enviar.',
        );
      }
    }
  }

  @override
  Future<ResultadoCompartir> compartirBytes(
    Uint8List bytes, {
    required String nombreArchivo,
    required String mimeType,
    String? mensaje,
  }) async {
    try {
      // `XFile.fromData` deja que `share_plus` materialice el archivo en SU
      // caché. Se evita así depender de `path_provider` sólo para pedir un
      // directorio temporal, y de paso el plugin se encarga de limpiar.
      final resultado = await Share.shareXFiles(
        <XFile>[
          XFile.fromData(bytes, mimeType: mimeType, name: nombreArchivo),
        ],
        // Android usa el nombre real del archivo para el adjunto de WhatsApp;
        // sin este override llega como "share.png" y el cliente recibe un
        // comprobante sin número.
        fileNameOverrides: <String>[nombreArchivo],
        text: mensaje,
        sharePositionOrigin: _origenPopoverIpad,
      );
      return _traducir(resultado, null);
    } catch (_) {
      return ResultadoCompartir.fallo(
        'No se pudo abrir la ventana para compartir.',
      );
    }
  }

  @override
  Future<ResultadoCompartir> compartirArchivoEnDisco(
    String ruta, {
    String? mensaje,
  }) async {
    try {
      if (!File(ruta).existsSync()) {
        return ResultadoCompartir.fallo('El archivo ya no existe.');
      }
      final resultado = await Share.shareXFiles(
        <XFile>[XFile(ruta)],
        text: mensaje,
        sharePositionOrigin: _origenPopoverIpad,
      );
      return _traducir(resultado, ruta);
    } catch (_) {
      return ResultadoCompartir.fallo('No se pudo compartir el archivo.');
    }
  }

  @override
  Future<ResultadoCompartir> compartirTexto(String texto) async {
    try {
      final resultado = await Share.share(
        texto,
        sharePositionOrigin: _origenPopoverIpad,
      );
      return _traducir(resultado, null);
    } catch (_) {
      return ResultadoCompartir.fallo('No se pudo compartir el texto.');
    }
  }

  @override
  Future<bool> get whatsappDisponible async {
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send?text=hola'));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ResultadoCompartir> abrirChatWhatsApp({
    required String telefono,
    required String mensaje,
  }) async {
    try {
      final numero = normalizarTelefonoPeru(telefono);
      if (numero == null) {
        return ResultadoCompartir.fallo(
          'El número de WhatsApp no parece válido.',
        );
      }
      // `wa.me` funciona con WhatsApp instalado y, si no, abre el navegador con
      // instrucciones. Es más robusto que el esquema `whatsapp://` a secas.
      final uri = Uri.parse(
        'https://wa.me/$numero?text=${Uri.encodeComponent(mensaje)}',
      );
      final abierto =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      return abierto
          ? ResultadoCompartir.ok()
          : ResultadoCompartir.fallo(
              'No se pudo abrir WhatsApp. Revisa que esté instalado.',
            );
    } catch (_) {
      return ResultadoCompartir.fallo('No se pudo abrir WhatsApp.');
    }
  }

  /// No-op deliberado.
  ///
  /// Al compartir con `XFile.fromData`, los archivos temporales los crea y los
  /// gestiona `share_plus` en su propia caché; Android e iOS la purgan solos.
  /// Se conserva el método porque forma parte del contrato y porque un
  /// transporte futuro (guardar el PDF en disco para el contador) sí tendrá que
  /// limpiar.
  @override
  Future<void> limpiarTemporales() async {}

  // ------------------------------------------------------------------

  static ResultadoCompartir _traducir(ShareResult r, String? ruta) {
    return switch (r.status) {
      ShareResultStatus.success => ResultadoCompartir.ok(rutaArchivo: ruta),
      ShareResultStatus.dismissed => ResultadoCompartir.cancelado(),
      // `unavailable`: la plataforma no informa el resultado (Android antiguo).
      // Se asume éxito: la hoja se abrió, que es lo que controlamos.
      ShareResultStatus.unavailable => ResultadoCompartir.ok(rutaArchivo: ruta),
    };
  }

  String _mensajePorDefecto(TicketVenta t) {
    final total = RenderizadorTicket.soles(t.total);
    return '${t.negocio.nombre}\n'
        'Comprobante ${t.numero}\n'
        'Total: $total\n'
        '${t.negocio.pieTicket}';
  }

  /// Normaliza un teléfono peruano a formato internacional sin `+`.
  ///
  /// - `987 654 321` → `51987654321` (celular peruano de 9 dígitos)
  /// - `+51 987654321` → `51987654321`
  /// - `51987654321` → tal cual
  ///
  /// Devuelve `null` si no parece un número usable.
  static String? normalizarTelefonoPeru(String entrada) {
    final soloDigitos = entrada.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return null;
    // Celular peruano: 9 dígitos empezando en 9.
    if (soloDigitos.length == 9 && soloDigitos.startsWith('9')) {
      return '51$soloDigitos';
    }
    if (soloDigitos.length >= 11 && soloDigitos.length <= 15) {
      return soloDigitos;
    }
    return null;
  }
}