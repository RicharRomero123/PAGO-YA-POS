import '../modelo/ticket.dart';
import 'configuracion_impresion.dart';

/// Alineación de una línea del ticket.
enum AlineacionTicket { izquierda, centro, derecha }

/// Una línea ya compuesta del ticket: texto plano + estilo.
///
/// Es la **representación intermedia** que consumen los tres destinos:
/// ESC/POS (impresora térmica), PNG y PDF (WhatsApp). Componer una sola vez
/// garantiza que el ticket impreso y el que llega por WhatsApp sean idénticos.
class LineaTicket {
  const LineaTicket(
    this.texto, {
    this.alineacion = AlineacionTicket.izquierda,
    this.negrita = false,
    this.doble = false,
  });

  /// Línea en blanco.
  const LineaTicket.vacia()
      : texto = '',
        alineacion = AlineacionTicket.izquierda,
        negrita = false,
        doble = false;

  final String texto;
  final AlineacionTicket alineacion;
  final bool negrita;

  /// Doble ancho + doble alto (GS ! 0x11 en ESC/POS). Ocupa la mitad de
  /// columnas, por eso el renderizador ya lo tiene en cuenta al padear.
  final bool doble;

  @override
  String toString() => texto;
}

/// Compone el ticket de una venta como lista de [LineaTicket].
///
/// **Port directo de `TicketPrinterEscPos.ConstruirTicket`**
/// (`src/PagoYa.Desktop/Servicios/Impresion/TicketPrinterEscPos.cs`). El orden,
/// los textos, los separadores y el redondeo son literalmente los mismos:
///
/// ```
///           NOMBRE DEL NEGOCIO           (centrado, negrita, doble)
///                RUC: 20xxxxxxxxx
///                 Av. Siempreviva 742
///                   Tel: 999888777
///
///                 NOTA DE VENTA          (centrado, negrita)
///                    M01-000123
/// ------------------------------------------
/// Fecha: 02/09/2026 14:33
/// Pago : Efectivo
/// ------------------------------------------
/// Inca Kola 500ml
///   2 x S/ 3.50                     S/ 7.00
/// ------------------------------------------
/// Subtotal:                         S/ 5.93
/// IGV (18%):                        S/ 1.07
/// TOTAL:                  S/ 7.00            (doble)
/// Recibido:                        S/ 10.00
/// Vuelto:                           S/ 3.00
///
///            ¡Gracias por su compra!
///        Documento interno - no es comprobante
///           de pago autorizado por SUNAT
/// ```
///
/// La única adición sobre el escritorio son las [LineaVentaTicket.notas]
/// (modificadores de comanda) y la marca de reimpresión, ambas opcionales.
class RenderizadorTicket {
  const RenderizadorTicket();

  /// Compone el ticket completo.
  List<LineaTicket> renderizar(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) {
    final ancho = config.columnasEfectivas;
    final n = ticket.negocio;
    final lineas = <LineaTicket>[];

    void centrada(String s, {bool negrita = false, bool doble = false}) =>
        lineas.add(LineaTicket(s,
            alineacion: AlineacionTicket.centro,
            negrita: negrita,
            doble: doble));
    void izq(String s, {bool negrita = false, bool doble = false}) =>
        lineas.add(LineaTicket(s, negrita: negrita, doble: doble));
    void vacia() => lineas.add(const LineaTicket.vacia());

    // --- Encabezado del negocio ---
    centrada(n.nombre, negrita: true, doble: true);
    if (n.ruc.trim().isNotEmpty) centrada('RUC: ${n.ruc}');
    if (n.direccion.trim().isNotEmpty) centrada(n.direccion);
    if (n.telefono.trim().isNotEmpty) centrada('Tel: ${n.telefono}');
    vacia();
    centrada(ticket.titulo, negrita: true);
    centrada(ticket.numero);
    if (ticket.esReimpresion) centrada('** REIMPRESION **', negrita: true);

    // --- Datos de la venta ---
    izq(separador(ancho));
    izq('Fecha: ${formatoFecha(ticket.fechaHora)}');
    izq('Pago : ${ticket.metodoPago.etiqueta}');
    izq(separador(ancho));

    // --- Ítems ---
    for (final d in ticket.lineas) {
      // Línea 1: descripción recortada al ancho del papel.
      izq(recortar(d.descripcion, ancho));
      // Línea 2: "  cant x precio" a la izquierda, importe a la derecha.
      final izquierda = '  ${formatoCantidad(d.cantidad)} x ${soles(d.precioUnitario)}';
      izq(dosColumnas(izquierda, soles(d.importe), ancho));
      // Modificadores / notas de comanda (no existen en el escritorio todavía).
      for (final nota in d.notas) {
        izq(recortar('    - $nota', ancho));
      }
    }

    izq(separador(ancho));

    // --- Totales ---
    izq(dosColumnas('Subtotal:', soles(ticket.subTotal), ancho));
    izq(dosColumnas('IGV (18%):', soles(ticket.igv), ancho));
    // En doble ancho la cuenta de columnas se reduce a la mitad (igual que el
    // escritorio: `DosColumnas("TOTAL:", ..., ancho / 2)`).
    izq(dosColumnas('TOTAL:', soles(ticket.total), ancho ~/ 2),
        negrita: true, doble: true);

    final recibido = ticket.montoRecibido;
    if (recibido != null) {
      izq(dosColumnas('Recibido:', soles(recibido), ancho));
      final v = ticket.vuelto;
      if (v != null) izq(dosColumnas('Vuelto:', soles(v), ancho));
    }

    // --- Pie ---
    vacia();
    centrada(recortar(n.pieTicket, ancho));
    if (config.imprimirPieSunat) {
      for (final l in pieSunat(ancho)) {
        centrada(l);
      }
    }

    return lineas;
  }

  /// Pie legal, partido según el ancho del papel.
  ///
  /// El escritorio lo imprime en dos líneas porque su ancho por defecto es 42
  /// columnas (80 mm). En móvil el ancho por defecto es 58 mm (32 columnas) y
  /// "Documento interno - no es comprobante" tiene 36 caracteres: la impresora
  /// lo partiría por donde le diera la gana, dejando una línea suelta fea. Con
  /// 36 columnas o más se usan **exactamente** las dos líneas del escritorio;
  /// por debajo se reparte en tres.
  static List<String> pieSunat(int ancho) {
    if (ancho >= 36) {
      return const [
        'Documento interno - no es comprobante',
        'de pago autorizado por SUNAT',
      ];
    }
    return const [
      'Documento interno - no es',
      'comprobante de pago autorizado',
      'por SUNAT',
    ];
  }

  /// Versión en texto plano del ticket, con las líneas ya centradas por
  /// espacios. Sirve para el mensaje de WhatsApp de respaldo cuando no se pudo
  /// generar la imagen, y para los tests de paridad con el escritorio.
  String comoTextoPlano(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) {
    final ancho = config.columnasEfectivas;
    final buffer = StringBuffer();
    for (final l in renderizar(ticket, config: config)) {
      // El texto en "doble" ocupa el doble de ancho al imprimirse; para el
      // volcado plano lo centramos con el ancho normal.
      buffer.writeln(_alinear(l.texto, l.alineacion, ancho));
    }
    return buffer.toString();
  }

  static String _alinear(String s, AlineacionTicket a, int ancho) {
    if (s.length >= ancho) return s;
    switch (a) {
      case AlineacionTicket.izquierda:
        return s;
      case AlineacionTicket.centro:
        final pad = (ancho - s.length) ~/ 2;
        return ' ' * pad + s;
      case AlineacionTicket.derecha:
        return ' ' * (ancho - s.length) + s;
    }
  }

  // ------------------------------------------------------------------
  // Helpers de formato. Portados uno a uno del escritorio; los tests de
  // paridad (`tests/fixtures/paridad/`) comparan contra la salida de C#.
  // ------------------------------------------------------------------

  /// Línea de guiones del ancho del papel (`new string('-', ancho)`).
  static String separador(int ancho) => '-' * ancho;

  /// `TicketPrinterEscPos.Recortar`.
  static String recortar(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// `TicketPrinterEscPos.DosColumnas`: texto a la izquierda, importe pegado a
  /// la derecha, relleno de espacios en medio. Si no entran, se separan por un
  /// solo espacio (la impresora hará el salto de línea).
  static String dosColumnas(String izquierda, String derecha, int ancho) {
    if (izquierda.length + derecha.length >= ancho) {
      return '$izquierda $derecha';
    }
    return izquierda + ' ' * (ancho - izquierda.length - derecha.length) + derecha;
  }

  /// `TicketPrinterEscPos.Fmt`: `"S/ " + monto.ToString("N2", es-PE)`.
  /// Formato es-PE: coma como separador de miles, punto decimal → `S/ 1,234.50`.
  /// Se implementa a mano para no depender de `intl` ni de que el locale del
  /// teléfono esté en español (un teléfono en inglés imprimiría distinto).
  static String soles(double monto) => 'S/ ${miles(monto)}';

  /// Número con 2 decimales y separador de miles es-PE.
  static String miles(double monto) {
    final negativo = monto < 0;
    final fijo = monto.abs().toStringAsFixed(2);
    final partes = fijo.split('.');
    final entera = partes[0];
    final decimales = partes[1];

    final buffer = StringBuffer();
    for (var i = 0; i < entera.length; i++) {
      if (i > 0 && (entera.length - i) % 3 == 0) buffer.write(',');
      buffer.write(entera[i]);
    }
    return '${negativo ? '-' : ''}$buffer.$decimales';
  }

  /// `TicketPrinterEscPos.FmtCant`: entero si es entero, si no hasta 3
  /// decimales sin ceros de relleno (venta por kilo: `1.5`, `0.25`).
  static String formatoCantidad(double cantidad) {
    if (cantidad == cantidad.truncateToDouble()) {
      return cantidad.toInt().toString();
    }
    var s = cantidad.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// `venta.FechaHora.ToString("dd/MM/yyyy HH:mm", es-PE)`.
  static String formatoFecha(DateTime f) {
    String dd(int v) => v.toString().padLeft(2, '0');
    return '${dd(f.day)}/${dd(f.month)}/${f.year} ${dd(f.hour)}:${dd(f.minute)}';
  }
}