import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../impresion/configuracion_impresion.dart';
import '../impresion/renderizador_ticket.dart';
import '../modelo/ticket.dart';

/// Dibuja el ticket como **PNG**, para mandarlo por WhatsApp.
///
/// Se apoya en las mismas [LineaTicket] que produce [RenderizadorTicket], así
/// que la imagen que recibe el cliente y el papel que sale de la térmica dicen
/// exactamente lo mismo, con el mismo formato y el mismo ancho de columnas.
///
/// Se usa `dart:ui` directamente (PictureRecorder + Canvas + TextPainter) en
/// vez de rasterizar un widget: no necesita un árbol montado ni
/// `RepaintBoundary`, así que funciona igual desde un servicio, desde un test
/// o desde una pantalla, y no arrastra ninguna dependencia extra.
///
/// La tipografía es **monoespaciada**: es lo que hace que las columnas
/// (`Subtotal: ......... S/ 5.93`) queden alineadas igual que en el papel.
class RenderizadorImagenTicket {
  const RenderizadorImagenTicket({
    this.renderizador = const RenderizadorTicket(),
    this.tamanoFuente = 22.0,
    this.margen = 28.0,
    this.escalaDispositivo = 1.0,
  });

  final RenderizadorTicket renderizador;

  /// Alto de fuente base. 22 px da un PNG legible en un WhatsApp comprimido
  /// sin que pese de más.
  final double tamanoFuente;

  final double margen;

  /// Multiplicador global (2.0 = imagen al doble de resolución).
  final double escalaDispositivo;

  static const List<String> _familiaMono = <String>[
    'monospace', // Android
    'Courier', // iOS
    'Menlo',
    'Roboto Mono',
  ];

  /// Genera el PNG del ticket.
  Future<Uint8List> renderizarPng(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    final lineas = renderizador.renderizar(ticket, config: config);
    final columnas = config.columnasEfectivas;
    final escala = escalaDispositivo;
    final fuente = tamanoFuente * escala;
    final margenPx = margen * escala;

    // Ancho de un carácter en la fuente mono: se mide una vez y define el
    // ancho del lienzo (columnas * anchoChar), igual que el papel.
    final anchoChar = _anchoDeUnCaracter(fuente);
    final altoLinea = fuente * 1.32;

    final anchoLienzo = anchoChar * columnas + margenPx * 2;

    // Alto: las líneas "doble" ocupan el doble de alto.
    var altoContenido = 0.0;
    for (final l in lineas) {
      altoContenido += l.doble ? altoLinea * 2 : altoLinea;
    }

    // Logo opcional, escalado al ancho útil.
    ui.Image? logo;
    var altoLogo = 0.0;
    final logoBytes = ticket.negocio.logoPng;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      logo = await _decodificar(logoBytes);
      if (logo != null) {
        final anchoUtil = anchoLienzo - margenPx * 2;
        final anchoLogo =
            logo.width > anchoUtil ? anchoUtil : logo.width.toDouble();
        altoLogo = logo.height * (anchoLogo / logo.width) + altoLinea * 0.5;
      }
    }

    final altoLienzo = altoContenido + altoLogo + margenPx * 2;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, anchoLienzo, altoLienzo),
    );

    // Fondo blanco: sin él el PNG sale transparente y WhatsApp lo muestra
    // sobre negro en modo oscuro, ilegible.
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, anchoLienzo, altoLienzo),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var y = margenPx;

    if (logo != null) {
      final anchoUtil = anchoLienzo - margenPx * 2;
      final anchoLogo =
          logo.width > anchoUtil ? anchoUtil : logo.width.toDouble();
      final altoDibujo = logo.height * (anchoLogo / logo.width);
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        ui.Rect.fromLTWH(
          (anchoLienzo - anchoLogo) / 2,
          y,
          anchoLogo,
          altoDibujo,
        ),
        ui.Paint(),
      );
      y += altoDibujo + altoLinea * 0.5;
    }

    for (final linea in lineas) {
      final alto = linea.doble ? altoLinea * 2 : altoLinea;
      if (linea.texto.isNotEmpty) {
        final painter = _pintor(
          linea.texto,
          linea.doble ? fuente * 2 : fuente,
          negrita: linea.negrita,
        );
        painter.layout();
        final x = switch (linea.alineacion) {
          AlineacionTicket.izquierda => margenPx,
          AlineacionTicket.centro => (anchoLienzo - painter.width) / 2,
          AlineacionTicket.derecha => anchoLienzo - margenPx - painter.width,
        };
        painter.paint(canvas, ui.Offset(x < margenPx ? margenPx : x, y));
      }
      y += alto;
    }

    final picture = recorder.endRecording();
    final imagen = await picture.toImage(
      anchoLienzo.ceil(),
      altoLienzo.ceil(),
    );
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    imagen.dispose();
    logo?.dispose();

    return datos!.buffer.asUint8List();
  }

  static Future<ui.Image?> _decodificar(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      // Logo corrupto: se imprime el ticket sin logo, no se rompe nada.
      return null;
    }
  }

  static TextPainter _pintor(
    String texto,
    double tamano, {
    required bool negrita,
  }) {
    return TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: tamano,
          height: 1.0,
          fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
          fontFamily: _familiaMono.first,
          fontFamilyFallback: _familiaMono.sublist(1),
          // Sin ligaduras ni ajustes: cada carácter debe ocupar lo mismo.
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
  }

  /// Ancho de un carácter en la fuente monoespaciada. Define el ancho del
  /// lienzo: `columnas * anchoChar`, igual que el rollo de papel.
  static double _anchoDeUnCaracter(double tamano) {
    final p = _pintor('0', tamano, negrita: false)..layout();
    return p.width;
  }
}