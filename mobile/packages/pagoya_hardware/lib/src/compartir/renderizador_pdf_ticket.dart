import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../impresion/configuracion_impresion.dart';
import '../impresion/renderizador_ticket.dart';
import '../modelo/ticket.dart';

/// Genera el ticket como **PDF** con el ancho real del rollo (58 u 80 mm).
///
/// Se usa cuando el cliente pide "el archivo" o cuando el comprobante va al
/// contador. Para el uso normal (mandarlo por WhatsApp al cliente) es mejor el
/// PNG de `RenderizadorImagenTicket`: WhatsApp lo muestra en el chat sin que
/// haya que abrir nada.
///
/// Igual que la imagen, se apoya en las [LineaTicket] de [RenderizadorTicket]:
/// una sola definición del formato, tres salidas.
class RenderizadorPdfTicket {
  const RenderizadorPdfTicket({
    this.renderizador = const RenderizadorTicket(),
    this.tamanoFuente = 7.5,
  });

  final RenderizadorTicket renderizador;

  /// En puntos PDF (1/72"). 7.5 pt cabe holgado en 58 mm con 32 columnas.
  final double tamanoFuente;

  Future<Uint8List> renderizarPdf(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    final lineas = renderizador.renderizar(ticket, config: config);
    final anchoPagina = config.ancho.milimetros * PdfPageFormat.mm;
    const margen = 4.0 * PdfPageFormat.mm;
    final altoLinea = tamanoFuente * 1.35;

    var altoContenido = 0.0;
    for (final l in lineas) {
      altoContenido += l.doble ? altoLinea * 2 : altoLinea;
    }
    final altoPagina = altoContenido + margen * 2;

    // Courier es una de las fuentes base del estándar PDF: monoespaciada y sin
    // necesidad de incrustar un TTF (el archivo pesa unos pocos KB, que en una
    // conexión de bodega importa).
    final normal = pw.Font.courier();
    final negrita = pw.Font.courierBold();

    final doc = pw.Document(
      title: ticket.numero,
      author: ticket.negocio.nombre,
      creator: 'PagoYa',
    );

    pw.MemoryImage? logo;
    final bytesLogo = ticket.negocio.logoPng;
    if (bytesLogo != null && bytesLogo.isNotEmpty) {
      try {
        logo = pw.MemoryImage(bytesLogo);
      } catch (_) {
        logo = null;
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          anchoPagina,
          altoPagina + (logo != null ? 40 : 0),
          marginAll: margen,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logo != null)
              pw.Center(
                child: pw.Image(logo, height: 32, fit: pw.BoxFit.contain),
              ),
            ...lineas.map((l) {
              if (l.texto.isEmpty) {
                return pw.SizedBox(height: altoLinea);
              }
              return pw.SizedBox(
                height: l.doble ? altoLinea * 2 : altoLinea,
                child: pw.Align(
                  alignment: switch (l.alineacion) {
                    AlineacionTicket.izquierda => pw.Alignment.centerLeft,
                    AlineacionTicket.centro => pw.Alignment.center,
                    AlineacionTicket.derecha => pw.Alignment.centerRight,
                  },
                  child: pw.Text(
                    l.texto,
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: l.negrita ? negrita : normal,
                      fontSize: l.doble ? tamanoFuente * 1.7 : tamanoFuente,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    return doc.save();
  }
}