/// Dobles de prueba del módulo de nube.
///
/// [TransporteSyncEnMemoria] es el port de
/// `src/PagoYa.Cloud/TransporteSyncEnMemoria.cs`: acepta los lotes subidos y los
/// devuelve como cambios descargables, con la misma idempotencia por id de
/// evento y el mismo cursor = índice del registro global. Encima se le añade
/// **inyección de fallos**, que es lo único que permite probar los escenarios
/// que de verdad rompen en producción: el corte a mitad del push, el 403 por
/// licencia sin flag y el evento venenoso.
///
/// [AlmacenOutboxEnMemoria] reproduce la semántica de la tabla `outbox_sync`
/// (`estado` 0=Pendiente, 1=Enviado, 2=Dead-letter; `intentos`) sin drift.
library;

import 'dart:convert';

import 'package:pagoya_core/nube/nube.dart';

// =============================================================================
//  Transporte simulado
// =============================================================================

class TransporteSyncEnMemoria implements TransporteSync {
  TransporteSyncEnMemoria({this.excluirOrigen});

  /// Valor de `origen` que este cliente manda en `GET /sync/pull?origen=...`.
  /// El "servidor" excluye de la ventana los cambios con ese `origen_caja_id`,
  /// igual que `ServicioSync.ObtenerCambiosAsync`.
  ///
  /// `null` modela los dos casos en que el backend NO filtra: un cliente que no
  /// manda `origen` y cuyo token no trae `device_prefix`, o un backend anterior
  /// al filtro. Es el caso en el que el cliente tiene que defenderse solo, y por
  /// eso la defensa local se mantiene aunque el filtro server-side exista.
  String? excluirOrigen;

  /// Registro global de cambios (el "servidor").
  final List<CambioRemoto> registro = [];

  /// Ids de evento ya aceptados (idempotencia por `(licencia, id)`).
  final Set<String> aceptados = {};

  /// Lotes recibidos, en orden (para verificar que no se reenvía de más).
  final List<List<String>> lotesRecibidos = [];

  int llamadasPush = 0;
  int llamadasPull = 0;
  int llamadasSonda = 0;

  /// Veces que el "server" tuvo que acotar un cursor por delante de su
  /// secuencia máxima. Es el equivalente del WARN que emite el backend real.
  int cursoresAcotados = 0;

  // --- inyección de fallos ---------------------------------------------------

  /// Fallos encolados para las próximas llamadas a push (uno por llamada).
  /// `null` en una posición = esa llamada va bien.
  final List<TipoFalloSync?> fallosPushEncolados = [];

  /// Fallos encolados para las próximas llamadas a pull.
  final List<TipoFalloSync?> fallosPullEncolados = [];

  /// Fallo permanente aplicado a TODAS las llamadas (p. ej. 403 por licencia
  /// sin `cloud_sync`).
  TipoFalloSync? falloPermanente;

  /// Ids de evento "venenosos": cualquier lote que los contenga es rechazado
  /// con un 4xx permanente, como haría un backend con un payload malformado o
  /// una entidad que todavía no conoce (`mesa`/`pedido`).
  final Set<String> venenosos = {};

  /// Si es `true`, el push acepta el lote pero NO devuelve los ids (simula un
  /// 200 con cuerpo perdido: el cliente reenviará y el server deduplicará).
  bool ocultarAceptados = false;

  /// Resultado de la sonda de internet.
  bool internet = true;

  /// Tope de cambios por pull, igual que `ServicioSync.MaxPorPull` (500) del
  /// backend. En tests se baja a 2 o 3 para ejercitar la paginación.
  int maxPorPull = 500;

  // --- API -------------------------------------------------------------------

  @override
  Future<ResultadoLote> enviarLote(List<EventoSyncLocal> lote) async {
    llamadasPush++;
    lotesRecibidos.add(lote.map((e) => e.id).toList(growable: false));

    final forzado = falloPermanente ?? _siguiente(fallosPushEncolados);
    if (forzado != null) {
      return ResultadoLote.falla(forzado, 'fallo simulado ${forzado.name}');
    }

    if (lote.any((e) => venenosos.contains(e.id))) {
      return ResultadoLote.falla(
          TipoFalloSync.rechazoPermanente, 'push HTTP 400: evento inaceptable');
    }

    final ids = <String>[];
    final desconocidas = <String>{};
    for (final e in lote) {
      // El server NO descarta lo que no reconoce (perder datos del cliente sería
      // peor): lo guarda igual y lo reporta en `entidadesDesconocidas`.
      if (!EntidadesSync.esConocida(e.entidad)) desconocidas.add(e.entidad);

      // Idempotencia: un evento ya aceptado no se re-registra, pero se vuelve a
      // aceptar (idéntico a ServicioSync.ProcesarPushAsync del backend).
      if (aceptados.add(e.id)) {
        registro.add(CambioRemoto(
          entidad: e.entidad,
          entidadId: e.entidadId,
          operacion: e.operacion,
          payloadJson: e.payloadJson,
          actualizadoUtc: _extraerActualizado(e),
          origenCajaId: e.origenCajaId,
        ));
      }
      ids.add(e.id);
    }
    return ResultadoLote.exito(
      ocultarAceptados ? const [] : ids,
      entidadesDesconocidas: desconocidas.toList(growable: false),
    );
  }

  @override
  Future<PaqueteRemoto> descargarCambios(String? cursor) async {
    llamadasPull++;
    final cursorActual = cursor ?? '0';

    final forzado = falloPermanente ?? _siguiente(fallosPullEncolados);
    if (forzado != null) {
      return PaqueteRemoto.falla(
          forzado, 'fallo simulado ${forzado.name}', cursorActual);
    }

    // Cursor no numérico, vacío o negativo => 0, igual que el server:
    // `long.TryParse(cursor, out c) && c > 0 ? c : 0L`.
    final crudo = int.tryParse(cursorActual) ?? 0;
    final desde = crudo > 0 ? crudo : 0;

    // Ventana por SECUENCIA, igual que `ServicioSync.ObtenerCambiosAsync`:
    // `Where(Secuencia > cursor).OrderBy(Secuencia).Take(MaxPorPull)`.
    // En este doble la "secuencia" es el índice 1-based del registro, así que
    // la secuencia máxima de la licencia es `registro.length`.
    final ventana = registro.skip(desde).take(maxPorPull).toList(growable: false);

    // El filtro de origen se aplica DENTRO de la ventana, igual que el filtro
    // server-side: el cursor avanza aunque no quede nada visible (por eso puede
    // volver una página vacía con cursor nuevo).
    final visibles = ventana
        .where((c) =>
            excluirOrigen == null ||
            c.origenCajaId.toLowerCase() != excluirOrigen!.toLowerCase())
        .toList(growable: false);

    final int nuevoCursor;
    if (ventana.isNotEmpty) {
      // Secuencia del último evento de la ventana.
      nuevoCursor = desde + ventana.length;
    } else {
      // Ventana vacía: o el cliente está al día, o su cursor quedó por delante
      // de la secuencia real. El server acota a `min(recibido, maxSecuencia)`
      // (con WARN en el log) para que un cursor corrupto se AUTO-REPARE en el
      // siguiente pull, sin re-entregar el histórico.
      final maxSecuencia = registro.length;
      nuevoCursor = desde < maxSecuencia ? desde : maxSecuencia;
      if (desde > maxSecuencia) cursoresAcotados++;
    }

    return PaqueteRemoto(visibles, nuevoCursor.toString());
  }

  @override
  Future<bool> hayInternet() async {
    llamadasSonda++;
    return internet;
  }

  @override
  void cerrar() {}

  /// Inyecta un cambio remoto "de la otra caja" sin pasar por push.
  void sembrarCambioAjeno(CambioRemoto cambio) => registro.add(cambio);

  TipoFalloSync? _siguiente(List<TipoFalloSync?> cola) =>
      cola.isEmpty ? null : cola.removeAt(0);

  static DateTime _extraerActualizado(EventoSyncLocal e) {
    try {
      final doc = jsonDecode(e.payloadJson);
      if (doc is Map && doc['ActualizadoUtc'] is String) {
        final f = DateTime.tryParse(doc['ActualizadoUtc'] as String);
        if (f != null) return f.toUtc();
      }
    } catch (_) {
      // payload sin ese campo (p. ej. DELETE)
    }
    return e.creadoUtc;
  }
}

/// Transporte que revienta con una excepción cruda. Sirve para comprobar la
/// regla crítica: un fallo de red NUNCA sale como excepción hacia la UI.
class TransporteQueLanza implements TransporteSync {
  @override
  Future<ResultadoLote> enviarLote(List<EventoSyncLocal> lote) async =>
      throw StateError('socket cerrado por el sistema');

  @override
  Future<PaqueteRemoto> descargarCambios(String? cursor) async =>
      throw StateError('socket cerrado por el sistema');

  @override
  Future<bool> hayInternet() async => throw StateError('sin red');

  @override
  void cerrar() {}
}

// =============================================================================
//  Outbox simulado
// =============================================================================

class _Fila {
  _Fila(this.evento);

  EventoSyncLocal evento;

  /// 0 = Pendiente, 1 = Enviado, 2 = Dead-letter (igual que `outbox_sync.estado`).
  int estado = 0;
  int intentos = 0;
  int orden = 0;
}

class AlmacenOutboxEnMemoria implements AlmacenOutbox {
  final Map<String, _Fila> _filas = {}; // clave: id en minúsculas
  int _secuencia = 0;
  String? _cursor;

  /// Cambios remotos efectivamente aplicados (tras el filtro de eco).
  final List<CambioRemoto> aplicados = [];

  /// Marca LWW por entidad, para que aplicar dos veces el mismo cambio no
  /// cuente dos veces (igual que `OutboxStore.AplicarCambiosRemotosAsync`).
  final Map<String, DateTime> _ultimaMarca = {};

  /// Cursores guardados, en orden (para verificar la reanudabilidad).
  final List<String> cursoresGuardados = [];

  int llamadasGuardarCursor = 0;

  // --- ayudas de prueba ------------------------------------------------------

  void encolar(EventoSyncLocal e) {
    final fila = _Fila(e)..orden = _secuencia++;
    _filas[e.id.toLowerCase()] = fila;
  }

  void encolarVarios(Iterable<EventoSyncLocal> eventos) => eventos.forEach(encolar);

  List<String> get idsEnviados => _porEstado(1);
  List<String> get idsPendientes => _porEstado(0);
  List<String> get idsDeadLetter => _porEstado(2);

  int intentosDe(String id) => _filas[id.toLowerCase()]?.intentos ?? 0;

  List<String> _porEstado(int estado) => (_filas.values
          .where((f) => f.estado == estado)
          .toList()
        ..sort((a, b) => a.orden.compareTo(b.orden)))
      .map((f) => f.evento.id)
      .toList(growable: false);

  // --- AlmacenOutbox ---------------------------------------------------------

  @override
  Future<List<EventoSyncLocal>> leerPendientes(int max) async {
    final pendientes = _filas.values.where((f) => f.estado == 0).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return pendientes
        .take(max)
        .map((f) => EventoSyncLocal(
              id: f.evento.id,
              entidad: f.evento.entidad,
              entidadId: f.evento.entidadId,
              operacion: f.evento.operacion,
              payloadJson: f.evento.payloadJson,
              intentos: f.intentos,
              origenCajaId: f.evento.origenCajaId,
              creadoUtc: f.evento.creadoUtc,
            ))
        .toList(growable: false);
  }

  @override
  Future<void> marcarEnviados(List<String> ids) async {
    for (final id in ids) {
      final f = _filas[id.toLowerCase()];
      if (f != null) f.estado = 1;
    }
  }

  @override
  Future<int> registrarFallo(List<String> ids, int maxIntentos) async {
    var muertos = 0;
    for (final id in ids) {
      final f = _filas[id.toLowerCase()];
      if (f == null || f.estado != 0) continue;
      f.intentos++;
      if (f.intentos >= maxIntentos) {
        f.estado = 2;
        muertos++;
      }
    }
    return muertos;
  }

  @override
  Future<int> aplicarCambiosRemotos(List<CambioRemoto> cambios) async {
    var aplicadosAhora = 0;
    for (final c in cambios) {
      final clave = '${c.entidad}:${c.entidadId}';
      final previa = _ultimaMarca[clave];
      // Last-write-wins: solo gana el cambio estrictamente más nuevo.
      if (previa != null && !c.actualizadoUtc.isAfter(previa)) continue;
      _ultimaMarca[clave] = c.actualizadoUtc;
      aplicados.add(c);
      aplicadosAhora++;
    }
    return aplicadosAhora;
  }

  @override
  Future<String?> leerCursor() async => _cursor;

  @override
  Future<void> guardarCursor(String cursor) async {
    llamadasGuardarCursor++;
    _cursor = cursor;
    cursoresGuardados.add(cursor);
  }

  @override
  Future<int> contarPendientes() async =>
      _filas.values.where((f) => f.estado == 0).length;

  @override
  Future<int> contarDeadLetter() async =>
      _filas.values.where((f) => f.estado == 2).length;

  @override
  Future<int> reencolarDeadLetter() async {
    var n = 0;
    for (final f in _filas.values.where((f) => f.estado == 2)) {
      f.estado = 0;
      f.intentos = 0;
      n++;
    }
    return n;
  }
}

// =============================================================================
//  Fábrica de eventos
// =============================================================================

int _n = 0;

/// Crea un evento de venta con el payload en el mismo formato que escribe el
/// outbox del escritorio (PascalCase con `ActualizadoUtc`).
EventoSyncLocal eventoDePrueba({
  String? id,
  String entidad = 'venta',
  String operacion = 'INSERT',
  String origen = 'M01',
  DateTime? actualizado,
}) {
  _n++;
  final marca = actualizado ?? DateTime.utc(2026, 1, 1).add(Duration(seconds: _n));
  final idFinal = id ?? 'evt-${_n.toString().padLeft(6, '0')}';
  return EventoSyncLocal(
    id: idFinal,
    entidad: entidad,
    entidadId: 'ent-${_n.toString().padLeft(6, '0')}',
    operacion: operacion,
    payloadJson: jsonEncode({
      'Id': 'ent-${_n.toString().padLeft(6, '0')}',
      'Total': 12.5,
      'ActualizadoUtc': marca.toIso8601String(),
    }),
    intentos: 0,
    origenCajaId: origen,
    creadoUtc: marca,
  );
}

/// Reinicia el contador para que los ids sean estables entre tests.
void reiniciarContadorEventos() => _n = 0;

/// Opciones típicas de prueba.
OpcionesSync opcionesDePrueba({
  int tamanoLote = 100,
  int maxIntentos = 3,
  String origen = 'M01',
  int maxPorPull = 500,
}) =>
    OpcionesSync(
      origenCajaId: origen,
      tamanoLote: tamanoLote,
      maxIntentos: maxIntentos,
      maxPorPull: maxPorPull,
      urlBase: 'https://api.pagoya.test',
      tokenLicencia: 'token-de-prueba',
    );
