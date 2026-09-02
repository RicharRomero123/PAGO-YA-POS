import 'dart:async';

import '../modelo/resultados.dart';
import '../modelo/ticket.dart';
import 'configuracion_impresion.dart';
import 'contrato_impresora.dart';
import 'renderizador_ticket.dart';

/// Implementación **falsa** de [ImpresoraTickets].
///
/// Para qué sirve:
/// - Correr toda la app en el **emulador**, donde no hay Bluetooth ni
///   impresora, sin que la pantalla de cobro se rompa.
/// - **Tests**: verificar que la venta se completa aunque la impresión falle
///   (poner [fallarSiempre] en `true`).
/// - Demos comerciales por videollamada: el ticket "impreso" queda en
///   [ticketsImpresos] y se puede mostrar en pantalla.
class ImpresoraTicketsFalsa implements ImpresoraTickets {
  ImpresoraTicketsFalsa({
    this.fallarSiempre = false,
    this.demora = const Duration(milliseconds: 300),
    List<ImpresoraDisponible>? impresoras,
    RenderizadorTicket renderizador = const RenderizadorTicket(),
  })  : _renderizador = renderizador,
        _impresoras = impresoras ??
            const <ImpresoraDisponible>[
              ImpresoraDisponible(
                id: '00:11:22:33:44:55',
                nombre: 'POS-58 (simulada)',
                tipo: TipoConexionImpresora.simulada,
                emparejada: true,
              ),
              ImpresoraDisponible(
                id: '00:11:22:33:44:66',
                nombre: 'XP-P323B (simulada)',
                tipo: TipoConexionImpresora.simulada,
                emparejada: true,
              ),
            ];

  /// Si es `true`, toda impresión devuelve fallo. Para probar que la venta no
  /// se bloquea (regla de negocio, no un detalle).
  bool fallarSiempre;

  /// Retardo simulado, para que la UI muestre su spinner como en la realidad.
  final Duration demora;

  final List<ImpresoraDisponible> _impresoras;
  final RenderizadorTicket _renderizador;

  final StreamController<EstadoImpresora> _estado =
      StreamController<EstadoImpresora>.broadcast();

  EstadoImpresora _estadoActual = EstadoImpresora.sinConfigurar;
  ImpresoraDisponible? _impresora;
  TicketVenta? _ultimoTicket;
  bool _conectada = false;

  /// Texto plano de cada ticket "impreso", en orden. Los tests comparan contra
  /// esto; la demo lo muestra en un diálogo.
  final List<String> ticketsImpresos = <String>[];

  /// Bytes ESC/POS crudos recibidos por [imprimirBytes].
  final List<List<int>> bytesRecibidos = <List<int>>[];

  /// Cuántas veces se pulsó el cajón.
  int pulsosCajon = 0;

  @override
  Stream<EstadoImpresora> get estado => _estado.stream;

  @override
  EstadoImpresora get estadoActual => _estadoActual;

  @override
  ImpresoraDisponible? get impresoraActual => _impresora;

  @override
  TicketVenta? get ultimoTicket => _ultimoTicket;

  @override
  Future<bool> get estaConectada async => _conectada;

  @override
  Future<bool> get bluetoothEncendido async => true;

  void _emitir(EstadoImpresora e) {
    _estadoActual = e;
    if (!_estado.isClosed) _estado.add(e);
  }

  @override
  Future<List<ImpresoraDisponible>> buscarImpresoras({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await Future<void>.delayed(demora);
    return List<ImpresoraDisponible>.unmodifiable(_impresoras);
  }

  @override
  Future<ResultadoImpresion> seleccionarImpresora(
    ImpresoraDisponible impresora,
  ) async {
    _impresora = impresora;
    return conectar();
  }

  @override
  Future<void> restaurarImpresoraGuardada() async {
    _impresora = _impresoras.isEmpty ? null : _impresoras.first;
    _emitir(_impresora == null
        ? EstadoImpresora.sinConfigurar
        : EstadoImpresora.desconectada);
  }

  @override
  Future<ResultadoImpresion> conectar() async {
    if (_impresora == null) {
      _emitir(EstadoImpresora.sinConfigurar);
      return ResultadoImpresion.fallo(
        'Todavía no elegiste una impresora.',
        CausaFalloImpresion.sinImpresoraConfigurada,
      );
    }
    _emitir(EstadoImpresora.conectando);
    await Future<void>.delayed(demora);
    if (fallarSiempre) {
      _conectada = false;
      _emitir(EstadoImpresora.error);
      return ResultadoImpresion.fallo(
        'No se pudo conectar con la impresora (simulado).',
        CausaFalloImpresion.sinConexion,
      );
    }
    _conectada = true;
    _emitir(EstadoImpresora.conectada);
    return ResultadoImpresion.ok();
  }

  @override
  Future<void> desconectar() async {
    _conectada = false;
    _emitir(_impresora == null
        ? EstadoImpresora.sinConfigurar
        : EstadoImpresora.desconectada);
  }

  @override
  Future<void> olvidarImpresora() async {
    _impresora = null;
    _conectada = false;
    _emitir(EstadoImpresora.sinConfigurar);
  }

  @override
  Future<ResultadoImpresion> imprimirTicket(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    _ultimoTicket = ticket;
    _emitir(EstadoImpresora.imprimiendo);
    await Future<void>.delayed(demora);
    if (fallarSiempre) {
      _emitir(EstadoImpresora.error);
      return ResultadoImpresion.fallo(
        'La impresora no respondió (simulado). La venta sí quedó registrada.',
        CausaFalloImpresion.escrituraFallida,
      );
    }
    ticketsImpresos.add(_renderizador.comoTextoPlano(ticket, config: config));
    _emitir(EstadoImpresora.conectada);
    return ResultadoImpresion.ok();
  }

  @override
  Future<ResultadoImpresion> reimprimirUltimo() async {
    final t = _ultimoTicket;
    if (t == null) {
      return ResultadoImpresion.fallo('No hay ningún ticket para reimprimir.');
    }
    return imprimirTicket(
      TicketVenta(
        numero: t.numero,
        fechaHora: t.fechaHora,
        metodoPago: t.metodoPago,
        subTotal: t.subTotal,
        igv: t.igv,
        total: t.total,
        lineas: t.lineas,
        negocio: t.negocio,
        montoRecibido: t.montoRecibido,
        titulo: t.titulo,
        esReimpresion: true,
      ),
    );
  }

  @override
  Future<ResultadoImpresion> imprimirBytes(List<int> bytes) async {
    await Future<void>.delayed(demora);
    if (fallarSiempre) {
      return ResultadoImpresion.fallo(
        'La impresora no respondió (simulado).',
        CausaFalloImpresion.escrituraFallida,
      );
    }
    bytesRecibidos.add(List<int>.unmodifiable(bytes));
    return ResultadoImpresion.ok();
  }

  @override
  Future<ResultadoImpresion> abrirCajon({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    if (fallarSiempre) {
      return ResultadoImpresion.fallo('No se pudo abrir el cajón (simulado).');
    }
    pulsosCajon++;
    return ResultadoImpresion.ok();
  }

  @override
  Future<ResultadoImpresion> probarImpresion({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String nombreNegocio = 'PagoYa',
  }) async {
    if (fallarSiempre) {
      return ResultadoImpresion.fallo('Prueba fallida (simulado).');
    }
    ticketsImpresos.add('--- PRUEBA DE IMPRESION ($nombreNegocio) ---');
    return ResultadoImpresion.ok();
  }

  @override
  Future<void> liberar() async {
    await _estado.close();
  }
}