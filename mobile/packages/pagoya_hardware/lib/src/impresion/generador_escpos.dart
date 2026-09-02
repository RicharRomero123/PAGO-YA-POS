import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../modelo/ticket.dart';
import 'codificador_cp850.dart';
import 'configuracion_impresion.dart';
import 'renderizador_ticket.dart';

/// Convierte un [TicketVenta] en el flujo de bytes **ESC/POS** que entiende la
/// impresora térmica.
///
/// Es el equivalente móvil de `TicketPrinterEscPos.ConstruirTicket`
/// (`src/PagoYa.Desktop/Servicios/Impresion/TicketPrinterEscPos.cs`). El
/// **formato del ticket no vive aquí** sino en [RenderizadorTicket]: esta clase
/// solo traduce líneas + estilos a comandos. Lo que cambia respecto al
/// escritorio es el transporte (Bluetooth en vez del spooler de Windows), no el
/// contenido.
///
/// No toca el hardware: es Dart puro y testeable con `flutter test`.
class GeneradorEscPos {
  GeneradorEscPos({
    RenderizadorTicket renderizador = const RenderizadorTicket(),
    CodificadorCp850 codificador = const CodificadorCp850(),
  })  : _renderizador = renderizador,
        _codificador = codificador;

  final RenderizadorTicket _renderizador;
  final CodificadorCp850 _codificador;

  CapabilityProfile? _perfil;

  /// Página de códigos que se activa antes de imprimir texto (`ESC t n`).
  /// CP850 = Multilingual, la misma que usa el escritorio.
  static const String _codeTable = 'CP850';

  /// Carga (una sola vez) el perfil de capacidades por defecto de
  /// `esc_pos_utils_plus`. Es una lectura de un JSON embebido, no toca red.
  Future<CapabilityProfile> _obtenerPerfil() async {
    return _perfil ??= await CapabilityProfile.load();
  }

  /// Bytes del ticket completo, listos para escribir en el transporte.
  ///
  /// Incluye, en este orden: `ESC @` (init) → pulso de cajón si aplica →
  /// líneas del ticket → avance de papel → corte. Igual que el escritorio.
  Future<List<int>> generarTicket(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    final perfil = await _obtenerPerfil();
    final g = Generator(_tamanoPapel(config.ancho), perfil);

    final bytes = <int>[];
    bytes.addAll(g.reset()); // ESC @
    bytes.addAll(g.setGlobalCodeTable(_codeTable));

    // El cajón se pulsa al inicio para que se abra en paralelo con la
    // impresión, igual que en `ConstruirTicket`. Solo en efectivo: Yape y
    // tarjeta no mueven el cajón.
    if (config.abrirCajonEnEfectivo &&
        ticket.metodoPago == MetodoPagoTicket.efectivo) {
      bytes.addAll(g.drawer());
    }

    final copias = config.copias < 1 ? 1 : config.copias;
    for (var i = 0; i < copias; i++) {
      bytes.addAll(_cuerpo(g, ticket, config));
      bytes.addAll(g.feed(config.lineasFinales));
      if (config.cortarPapel) {
        bytes.addAll(g.cut(mode: PosCutMode.partial));
      }
    }

    return bytes;
  }

  /// Solo el pulso de apertura del cajón portamonedas (`ESC p`).
  ///
  /// Port de `TicketPrinterEscPos.AbrirCajonAsync`: se manda `ESC @` antes del
  /// pulso para que se interprete igual sin depender del último ticket impreso.
  /// El cajón cuelga del RJ11/RJ12 de la impresora, así que abrirlo es mandarle
  /// un pulso a la misma impresora.
  Future<List<int>> generarPulsoCajon({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    final perfil = await _obtenerPerfil();
    final g = Generator(_tamanoPapel(config.ancho), perfil);
    return <int>[...g.reset(), ...g.drawer()];
  }

  /// Ticket de prueba para el botón "Probar impresora" de Configuración.
  /// Sirve para que el usuario verifique el ancho de papel y las tildes antes
  /// de su primera venta, no en medio de una cola de clientes.
  Future<List<int>> generarPruebaImpresion({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String nombreNegocio = 'PagoYa',
  }) async {
    final perfil = await _obtenerPerfil();
    final g = Generator(_tamanoPapel(config.ancho), perfil);
    final ancho = config.columnasEfectivas;

    final bytes = <int>[
      ...g.reset(),
      ...g.setGlobalCodeTable(_codeTable),
    ];

    bytes.addAll(_linea(
      g,
      LineaTicket(nombreNegocio,
          alineacion: AlineacionTicket.centro, negrita: true, doble: true),
      config,
    ));
    for (final l in <LineaTicket>[
      const LineaTicket('PRUEBA DE IMPRESION',
          alineacion: AlineacionTicket.centro, negrita: true),
      const LineaTicket.vacia(),
      LineaTicket(RenderizadorTicket.separador(ancho)),
      LineaTicket('Papel: ${config.ancho.milimetros} mm - $ancho columnas'),
      const LineaTicket('Tildes y enie: áéíóú ñÑ ¿¡ °'),
      LineaTicket(RenderizadorTicket.dosColumnas(
          'Alineacion:', RenderizadorTicket.soles(1234.5), ancho)),
      LineaTicket(RenderizadorTicket.separador(ancho)),
      const LineaTicket.vacia(),
      const LineaTicket('Si ves esta linea completa y sin',
          alineacion: AlineacionTicket.centro),
      const LineaTicket('simbolos raros, la impresora esta lista.',
          alineacion: AlineacionTicket.centro),
    ]) {
      bytes.addAll(_linea(g, l, config));
    }

    bytes.addAll(g.feed(config.lineasFinales));
    if (config.cortarPapel) bytes.addAll(g.cut(mode: PosCutMode.partial));
    return bytes;
  }

  // ------------------------------------------------------------------

  List<int> _cuerpo(
    Generator g,
    TicketVenta ticket,
    ConfiguracionImpresion config,
  ) {
    final bytes = <int>[];
    for (final linea in _renderizador.renderizar(ticket, config: config)) {
      bytes.addAll(_linea(g, linea, config));
    }
    return bytes;
  }

  /// Traduce una [LineaTicket] a comandos. El texto va como bytes ya
  /// codificados (`textEncoded`) para respetar CP850; si se usara `text()` la
  /// librería codificaría en latin1 y las tildes saldrían mal.
  List<int> _linea(
    Generator g,
    LineaTicket linea,
    ConfiguracionImpresion config,
  ) {
    final estilos = PosStyles(
      align: switch (linea.alineacion) {
        AlineacionTicket.izquierda => PosAlign.left,
        AlineacionTicket.centro => PosAlign.center,
        AlineacionTicket.derecha => PosAlign.right,
      },
      bold: linea.negrita,
      height: linea.doble ? PosTextSize.size2 : PosTextSize.size1,
      width: linea.doble ? PosTextSize.size2 : PosTextSize.size1,
      codeTable: _codeTable,
    );

    if (linea.texto.isEmpty) {
      return g.emptyLines(1);
    }

    final datos = _codificador.codificar(
      linea.texto,
      transliterar: config.transliterarAcentos,
    );
    return g.textEncoded(datos, styles: estilos);
  }

  static PaperSize _tamanoPapel(AnchoPapel ancho) => switch (ancho) {
        AnchoPapel.mm58 => PaperSize.mm58,
        AnchoPapel.mm80 => PaperSize.mm80,
      };
}