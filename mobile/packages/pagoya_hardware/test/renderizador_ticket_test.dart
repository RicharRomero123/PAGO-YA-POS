import 'package:flutter_test/flutter_test.dart';
import 'package:pagoya_hardware/pagoya_hardware.dart';

/// Tests del formato del ticket portado del escritorio
/// (`src/PagoYa.Desktop/Servicios/Impresion/TicketPrinterEscPos.cs`).
///
/// Son Dart puro: no tocan Bluetooth, cámara ni almacenamiento seguro, así que
/// corren en CI sin dispositivo.
///
/// Cuando `mobile-lead` publique los fixtures compartidos de
/// `tests/fixtures/paridad/` (ver `docs/MOBILE-ARQUITECTURA.md` §8), estos
/// tests deben pasar a leer de ahí en vez de tener los valores escritos a mano.
void main() {
  const renderizador = RenderizadorTicket();

  final negocio = const DatosNegocioTicket(
    nombre: 'Bodega Doña Rosa',
    ruc: '20512345678',
    direccion: 'Av. Los Álamos 145 - SJL',
    telefono: '987654321',
    pieTicket: '¡Gracias por su compra!',
  );

  TicketVenta ticketDemo({
    double total = 7.00,
    double? recibido,
    MetodoPagoTicket pago = MetodoPagoTicket.efectivo,
  }) {
    return TicketVenta(
      numero: 'M01-000123',
      fechaHora: DateTime(2026, 9, 2, 14, 33),
      metodoPago: pago,
      subTotal: 5.93,
      igv: 1.07,
      total: total,
      montoRecibido: recibido,
      negocio: negocio,
      lineas: const [
        LineaVentaTicket(
          descripcion: 'Inca Kola 500ml',
          cantidad: 2,
          precioUnitario: 3.50,
          importe: 7.00,
        ),
      ],
    );
  }

  group('formato de moneda (paridad con Fmt / N2 es-PE)', () {
    test('dos decimales y prefijo S/', () {
      expect(RenderizadorTicket.soles(7), 'S/ 7.00');
      expect(RenderizadorTicket.soles(3.5), 'S/ 3.50');
      expect(RenderizadorTicket.soles(0), 'S/ 0.00');
    });

    test('separador de miles con coma, como es-PE', () {
      expect(RenderizadorTicket.soles(1234.5), 'S/ 1,234.50');
      expect(RenderizadorTicket.soles(1234567.89), 'S/ 1,234,567.89');
      expect(RenderizadorTicket.soles(999.999), 'S/ 1,000.00');
    });

    test('negativos', () {
      expect(RenderizadorTicket.soles(-12.3), 'S/ -12.30');
    });
  });

  group('formato de cantidad (paridad con FmtCant)', () {
    test('entero sin decimales', () {
      expect(RenderizadorTicket.formatoCantidad(2), '2');
      expect(RenderizadorTicket.formatoCantidad(10), '10');
    });

    test('decimal hasta 3 dígitos sin ceros de relleno', () {
      expect(RenderizadorTicket.formatoCantidad(1.5), '1.5');
      expect(RenderizadorTicket.formatoCantidad(0.25), '0.25');
      expect(RenderizadorTicket.formatoCantidad(0.125), '0.125');
    });
  });

  group('dosColumnas (paridad con DosColumnas)', () {
    test('rellena con espacios hasta el ancho', () {
      final linea = RenderizadorTicket.dosColumnas('Subtotal:', 'S/ 5.93', 32);
      expect(linea.length, 32);
      expect(linea.startsWith('Subtotal:'), isTrue);
      expect(linea.endsWith('S/ 5.93'), isTrue);
    });

    test('si no entra, un solo espacio en medio', () {
      final linea = RenderizadorTicket.dosColumnas(
        'Una descripcion larguisima',
        'S/ 1,234,567.89',
        20,
      );
      expect(linea, 'Una descripcion larguisima S/ 1,234,567.89');
    });
  });

  group('formato de fecha (paridad con dd/MM/yyyy HH:mm)', () {
    test('rellena con ceros', () {
      expect(
        RenderizadorTicket.formatoFecha(DateTime(2026, 1, 5, 9, 7)),
        '05/01/2026 09:07',
      );
    });
  });

  group('estructura del ticket', () {
    test('respeta el orden del escritorio', () {
      // 80 mm = 42 columnas, el mismo ancho por defecto del escritorio, para
      // comparar el pie legal línea por línea.
      const config = ConfiguracionImpresion(ancho: AnchoPapel.mm80);
      final lineas = renderizador
          .renderizar(ticketDemo(), config: config)
          .map((l) => l.texto)
          .toList();

      expect(lineas.first, 'Bodega Doña Rosa');
      expect(lineas, contains('RUC: 20512345678'));
      expect(lineas, contains('Tel: 987654321'));
      expect(lineas, contains('NOTA DE VENTA'));
      expect(lineas, contains('M01-000123'));
      expect(lineas, contains('Fecha: 02/09/2026 14:33'));
      expect(lineas, contains('Pago : Efectivo'));
      expect(lineas, contains('Inca Kola 500ml'));
      expect(lineas, contains('Documento interno - no es comprobante'));
      expect(lineas, contains('de pago autorizado por SUNAT'));

      // El nombre del negocio va en negrita + doble.
      final encabezado = renderizador.renderizar(ticketDemo()).first;
      expect(encabezado.negrita, isTrue);
      expect(encabezado.doble, isTrue);
      expect(encabezado.alineacion, AlineacionTicket.centro);
    });

    test('en 58 mm el pie legal se parte en tres para no desbordar', () {
      const config = ConfiguracionImpresion(ancho: AnchoPapel.mm58);
      final textos = renderizador
          .renderizar(ticketDemo(), config: config)
          .map((l) => l.texto)
          .toList();
      expect(textos, contains('Documento interno - no es'));
      expect(textos, contains('comprobante de pago autorizado'));
      expect(textos, contains('por SUNAT'));
    });

    test('la línea del ítem lleva cantidad x precio e importe', () {
      final lineas = renderizador
          .renderizar(ticketDemo())
          .map((l) => l.texto)
          .toList();
      final linea = lineas.firstWhere((l) => l.contains(' x '));
      expect(linea.trimLeft(), startsWith('2 x S/ 3.50'));
      expect(linea.trimRight(), endsWith('S/ 7.00'));
    });

    test('el TOTAL usa la mitad de columnas por el doble ancho', () {
      const config = ConfiguracionImpresion(ancho: AnchoPapel.mm80); // 42
      final total = renderizador
          .renderizar(ticketDemo(), config: config)
          .firstWhere((l) => l.texto.startsWith('TOTAL:'));
      expect(total.doble, isTrue);
      expect(total.negrita, isTrue);
      expect(total.texto.length, 21); // 42 / 2
    });

    test('vuelto solo si el recibido supera el total', () {
      String textos(TicketVenta t) =>
          renderizador.renderizar(t).map((l) => l.texto).join('\n');

      expect(textos(ticketDemo(recibido: 10)), contains('Vuelto:'));
      expect(textos(ticketDemo(recibido: 10)), contains('S/ 3.00'));
      // Pago justo: hay "Recibido" pero no "Vuelto".
      expect(textos(ticketDemo(recibido: 7)), contains('Recibido:'));
      expect(textos(ticketDemo(recibido: 7)), isNot(contains('Vuelto:')));
      // Sin monto recibido no aparece ninguno de los dos.
      expect(textos(ticketDemo()), isNot(contains('Recibido:')));
    });

    test('el método de pago se imprime con la etiqueta del escritorio', () {
      final t = ticketDemo(pago: MetodoPagoTicket.billeteraDigital);
      final textos = renderizador.renderizar(t).map((l) => l.texto);
      expect(textos, contains('Pago : Yape / Plin'));
    });

    test('la reimpresión se marca en el ticket', () {
      final base = ticketDemo();
      final copia = TicketVenta(
        numero: base.numero,
        fechaHora: base.fechaHora,
        metodoPago: base.metodoPago,
        subTotal: base.subTotal,
        igv: base.igv,
        total: base.total,
        lineas: base.lineas,
        negocio: base.negocio,
        esReimpresion: true,
      );
      final textos = renderizador.renderizar(copia).map((l) => l.texto);
      expect(textos, contains('** REIMPRESION **'));
    });
  });

  group('ancho de papel configurable', () {
    test('58 mm usa 32 columnas y 80 mm usa 42', () {
      expect(AnchoPapel.mm58.columnasPorDefecto, 32);
      expect(AnchoPapel.mm80.columnasPorDefecto, 42);

      for (final ancho in AnchoPapel.values) {
        final config = ConfiguracionImpresion(ancho: ancho);
        final separadores = renderizador
            .renderizar(ticketDemo(), config: config)
            .where((l) => l.texto.startsWith('---'));
        expect(separadores, isNotEmpty);
        for (final s in separadores) {
          expect(s.texto.length, ancho.columnasPorDefecto);
        }
      }
    });

    test('el override manual de columnas gana', () {
      const config = ConfiguracionImpresion(
        ancho: AnchoPapel.mm58,
        columnas: 31, // clon chino que imprime 31
      );
      expect(config.columnasEfectivas, 31);
      final separador = renderizador
          .renderizar(ticketDemo(), config: config)
          .firstWhere((l) => l.texto.startsWith('---'));
      expect(separador.texto.length, 31);
    });
  });

  group('descripciones largas', () {
    test('se recortan al ancho del papel, no se desbordan', () {
      final t = TicketVenta(
        numero: 'M01-000124',
        fechaHora: DateTime(2026, 9, 2, 14, 33),
        metodoPago: MetodoPagoTicket.efectivo,
        subTotal: 10,
        igv: 1.8,
        total: 11.8,
        negocio: negocio,
        lineas: const [
          LineaVentaTicket(
            descripcion:
                'Detergente en polvo Bolívar Floral bolsa de 780 gramos '
                'presentación familiar',
            cantidad: 1,
            precioUnitario: 11.8,
            importe: 11.8,
          ),
        ],
      );
      const config = ConfiguracionImpresion(ancho: AnchoPapel.mm58);
      for (final l in renderizador.renderizar(t, config: config)) {
        if (l.doble) continue; // el doble ancho se mide distinto
        expect(l.texto.length, lessThanOrEqualTo(32),
            reason: 'la línea "${l.texto}" desborda el papel de 58 mm');
      }
    });
  });

  group('notas de comanda (rubros de comida)', () {
    test('se imprimen indentadas bajo el ítem', () {
      final t = TicketVenta(
        numero: 'M01-000125',
        fechaHora: DateTime(2026, 9, 2, 20, 5),
        metodoPago: MetodoPagoTicket.efectivo,
        subTotal: 23.73,
        igv: 4.27,
        total: 28,
        negocio: negocio,
        lineas: const [
          LineaVentaTicket(
            descripcion: 'Lomo saltado',
            cantidad: 1,
            precioUnitario: 28,
            importe: 28,
            notas: ['Sin cebolla', '+ Huevo frito'],
          ),
        ],
      );
      final textos = renderizador.renderizar(t).map((l) => l.texto).toList();
      expect(textos, contains('    - Sin cebolla'));
      expect(textos, contains('    - + Huevo frito'));
    });
  });
}