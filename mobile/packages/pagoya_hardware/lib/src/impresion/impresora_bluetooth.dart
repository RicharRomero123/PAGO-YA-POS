import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../modelo/resultados.dart';
import '../modelo/ticket.dart';
import 'configuracion_impresion.dart';
import 'contrato_impresora.dart';
import 'generador_escpos.dart';
import 'transporte.dart';
import 'transporte_ble.dart';
import 'transporte_spp.dart';

/// Implementación real de [ImpresoraTickets] sobre Bluetooth.
///
/// Combina los dos transportes ([TransporteSpp] prioritario, [TransporteBle]
/// de respaldo) y añade lo que hace que esto funcione en una bodega de verdad:
///
/// ### 1. La impresora se recuerda, la conexión no
/// La elección del usuario se persiste (MAC + tipo). La **conexión física se
/// abre bajo demanda** al imprimir. No hay servicio en segundo plano
/// manteniendo el socket vivo: en Xiaomi/MIUI, Huawei/EMUI y Oppo/ColorOS el
/// sistema mata ese proceso sin avisar y el resultado sería un cajero mirando
/// un "conectando..." eterno. Reconectar tarda ~1 s y es fiable.
///
/// ### 2. Reintento automático, una sola vez
/// Estas impresoras se desconectan solas todo el tiempo (ahorro de batería).
/// Si la escritura falla, se reconecta y se reintenta **una** vez. Más
/// reintentos solo alargan la espera del cliente en la cola.
///
/// ### 3. Un fallo de impresión NUNCA bloquea la venta
/// Todos los métodos devuelven [ResultadoImpresion]; ninguno lanza. La venta ya
/// está en SQLite y en el outbox antes de llegar aquí. Si no se pudo imprimir,
/// la UI ofrece "Imprimir de nuevo" o "Enviar por WhatsApp"; el cobro ya está
/// hecho.
///
/// ### 4. "Imprimir de nuevo" siempre disponible
/// Se guarda el último ticket en memoria, incluso si la impresión falló. Es el
/// botón que más se usa (se acabó el papel, la impresora estaba apagada).
class ImpresoraTicketsBluetooth implements ImpresoraTickets {
  ImpresoraTicketsBluetooth({
    TransporteImpresora? transporteSpp,
    TransporteImpresora? transporteBle,
    GeneradorEscPos? generador,
  })  : _spp = transporteSpp ?? TransporteSpp(),
        _ble = transporteBle ?? TransporteBle(),
        _generador = generador ?? GeneradorEscPos();

  final TransporteImpresora _spp;
  final TransporteImpresora _ble;
  final GeneradorEscPos _generador;

  static const String _claveImpresoraGuardada = 'pagoya.impresora.seleccionada';
  static const String _claveNombreGuardado = 'pagoya.impresora.nombre';

  final StreamController<EstadoImpresora> _estado =
      StreamController<EstadoImpresora>.broadcast();

  EstadoImpresora _estadoActual = EstadoImpresora.sinConfigurar;
  ImpresoraDisponible? _impresora;
  TicketVenta? _ultimoTicket;

  /// Serializa las impresiones: dos tickets simultáneos por el mismo socket
  /// salen intercalados y la impresora escupe basura.
  Future<void> _cola = Future<void>.value();

  @override
  Stream<EstadoImpresora> get estado => _estado.stream;

  @override
  EstadoImpresora get estadoActual => _estadoActual;

  @override
  ImpresoraDisponible? get impresoraActual => _impresora;

  @override
  TicketVenta? get ultimoTicket => _ultimoTicket;

  void _emitir(EstadoImpresora e) {
    _estadoActual = e;
    if (!_estado.isClosed) _estado.add(e);
  }

  TransporteImpresora _transporteDe(TipoConexionImpresora tipo) =>
      tipo == TipoConexionImpresora.ble ? _ble : _spp;

  TransporteImpresora? get _transporteActual {
    final i = _impresora;
    return i == null ? null : _transporteDe(i.tipo);
  }

  @override
  Future<bool> get estaConectada async {
    final t = _transporteActual;
    if (t == null) return false;
    try {
      return await t.conectado;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get bluetoothEncendido async {
    try {
      if (await _spp.soportado && await _spp.adaptadorEncendido) return true;
      return await _ble.adaptadorEncendido;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ImpresoraDisponible>> buscarImpresoras({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final resultado = <ImpresoraDisponible>[];
    try {
      // Primero SPP: son las que el usuario espera ver (ya emparejadas) y la
      // consulta es instantánea, así que la lista aparece de inmediato.
      if (await _spp.soportado) {
        resultado.addAll(await _spp.buscar(timeout: timeout));
      }
    } catch (_) {}
    try {
      if (await _ble.soportado) {
        final bles = await _ble.buscar(timeout: timeout);
        // No repetir una impresora que ya salió por SPP (mismo MAC en Android).
        final ids = resultado.map((e) => e.id.toUpperCase()).toSet();
        resultado.addAll(
          bles.where((b) => !ids.contains(b.id.toUpperCase())),
        );
      }
    } catch (_) {}
    return resultado;
  }

  @override
  Future<ResultadoImpresion> seleccionarImpresora(
    ImpresoraDisponible impresora,
  ) async {
    // Si había otra conectada, se cierra antes de cambiar.
    final anterior = _transporteActual;
    if (anterior != null && _impresora != impresora) {
      try {
        await anterior.desconectar();
      } catch (_) {}
    }

    _impresora = impresora;
    _emitir(EstadoImpresora.desconectada);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveImpresoraGuardada, impresora.clavePersistencia);
      await prefs.setString(_claveNombreGuardado, impresora.nombre);
    } catch (_) {
      // Persistir es un lujo; no impedir el uso si falla.
    }

    return conectar();
  }

  @override
  Future<void> restaurarImpresoraGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clave = prefs.getString(_claveImpresoraGuardada);
      if (clave == null) return;
      final partes = ImpresoraDisponible.desdeClave(clave);
      if (partes == null) return;
      _impresora = ImpresoraDisponible(
        id: partes.id,
        nombre: prefs.getString(_claveNombreGuardado) ?? 'Impresora',
        tipo: partes.tipo,
        emparejada: partes.tipo == TipoConexionImpresora.sppClasico,
      );
      _emitir(EstadoImpresora.desconectada);
    } catch (_) {
      // Sin impresora guardada; la app arranca igual.
    }
  }

  @override
  Future<ResultadoImpresion> conectar() async {
    final impresora = _impresora;
    if (impresora == null) {
      _emitir(EstadoImpresora.sinConfigurar);
      return ResultadoImpresion.fallo(
        'Todavía no elegiste una impresora. Ve a Configuración > Impresora.',
        CausaFalloImpresion.sinImpresoraConfigurada,
      );
    }
    _emitir(EstadoImpresora.conectando);
    try {
      final r = await _transporteDe(impresora.tipo).conectar(impresora);
      _emitir(r.exito ? EstadoImpresora.conectada : EstadoImpresora.error);
      return r;
    } catch (_) {
      _emitir(EstadoImpresora.error);
      return ResultadoImpresion.fallo(
        'No se pudo conectar con la impresora.',
        CausaFalloImpresion.sinConexion,
      );
    }
  }

  @override
  Future<void> desconectar() async {
    try {
      await _transporteActual?.desconectar();
    } catch (_) {}
    _emitir(_impresora == null
        ? EstadoImpresora.sinConfigurar
        : EstadoImpresora.desconectada);
  }

  @override
  Future<void> olvidarImpresora() async {
    await desconectar();
    _impresora = null;
    _emitir(EstadoImpresora.sinConfigurar);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveImpresoraGuardada);
      await prefs.remove(_claveNombreGuardado);
    } catch (_) {}
  }

  @override
  Future<ResultadoImpresion> imprimirTicket(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    // Se recuerda ANTES de intentar: si falla, "Imprimir de nuevo" y
    // "Compartir por WhatsApp" tienen que funcionar igual.
    _ultimoTicket = ticket;
    try {
      final bytes = await _generador.generarTicket(ticket, config: config);
      return _enviar(bytes);
    } catch (_) {
      return ResultadoImpresion.fallo(
        'No se pudo preparar el ticket. La venta sí quedó registrada.',
      );
    }
  }

  @override
  Future<ResultadoImpresion> reimprimirUltimo() async {
    final ticket = _ultimoTicket;
    if (ticket == null) {
      return ResultadoImpresion.fallo('No hay ningún ticket para reimprimir.');
    }
    final copia = TicketVenta(
      numero: ticket.numero,
      fechaHora: ticket.fechaHora,
      metodoPago: ticket.metodoPago,
      subTotal: ticket.subTotal,
      igv: ticket.igv,
      total: ticket.total,
      lineas: ticket.lineas,
      negocio: ticket.negocio,
      montoRecibido: ticket.montoRecibido,
      titulo: ticket.titulo,
      esReimpresion: true,
    );
    return imprimirTicket(copia);
  }

  @override
  Future<ResultadoImpresion> imprimirBytes(List<int> bytes) => _enviar(bytes);

  @override
  Future<ResultadoImpresion> abrirCajon({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  }) async {
    try {
      final bytes = await _generador.generarPulsoCajon(config: config);
      return _enviar(bytes);
    } catch (_) {
      return ResultadoImpresion.fallo('No se pudo abrir el cajón.');
    }
  }

  @override
  Future<ResultadoImpresion> probarImpresion({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String nombreNegocio = 'PagoYa',
  }) async {
    try {
      final bytes = await _generador.generarPruebaImpresion(
        config: config,
        nombreNegocio: nombreNegocio,
      );
      return _enviar(bytes);
    } catch (_) {
      return ResultadoImpresion.fallo('No se pudo enviar la prueba.');
    }
  }

  /// Envía bytes al transporte, encolado y con **un** reintento con
  /// reconexión. Punto único por el que pasa todo lo que se imprime.
  Future<ResultadoImpresion> _enviar(List<int> bytes) {
    final completer = Completer<ResultadoImpresion>();
    _cola = _cola.then((_) async {
      completer.complete(await _enviarAhora(bytes));
    }).catchError((Object _) {
      if (!completer.isCompleted) {
        completer.complete(
          ResultadoImpresion.fallo('No se pudo imprimir el ticket.'),
        );
      }
    });
    return completer.future;
  }

  Future<ResultadoImpresion> _enviarAhora(List<int> bytes) async {
    final impresora = _impresora;
    if (impresora == null) {
      return ResultadoImpresion.fallo(
        'Todavía no elegiste una impresora. La venta quedó registrada; puedes '
        'enviar el comprobante por WhatsApp.',
        CausaFalloImpresion.sinImpresoraConfigurada,
      );
    }

    final transporte = _transporteDe(impresora.tipo);
    _emitir(EstadoImpresora.imprimiendo);

    try {
      // Intento 1: reconecta si hace falta.
      var conectada = await transporte.conectado;
      if (!conectada) {
        final r = await transporte.conectar(impresora);
        if (!r.exito) {
          _emitir(EstadoImpresora.error);
          return r;
        }
        conectada = true;
      }

      var resultado = await transporte.escribir(bytes);
      if (resultado.exito) {
        _emitir(EstadoImpresora.conectada);
        return resultado;
      }

      // Intento 2 (único): la impresora se durmió entre el chequeo y la
      // escritura, que es lo que pasa el 90 % de las veces.
      await transporte.desconectar();
      final reconexion = await transporte.conectar(impresora);
      if (!reconexion.exito) {
        _emitir(EstadoImpresora.error);
        return reconexion;
      }
      resultado = await transporte.escribir(bytes);
      _emitir(resultado.exito
          ? EstadoImpresora.conectada
          : EstadoImpresora.error);
      return resultado;
    } catch (_) {
      _emitir(EstadoImpresora.error);
      return ResultadoImpresion.fallo(
        'No se pudo imprimir. La venta sí quedó registrada: puedes reintentar '
        'o enviar el comprobante por WhatsApp.',
        CausaFalloImpresion.escrituraFallida,
      );
    }
  }

  @override
  Future<void> liberar() async {
    try {
      await _spp.liberar();
    } catch (_) {}
    try {
      await _ble.liberar();
    } catch (_) {}
    await _estado.close();
  }
}