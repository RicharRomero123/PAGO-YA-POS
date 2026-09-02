/// Motor de sincronización con la nube de PagoYa Móvil.
///
/// Es el port de `src/PagoYa.Cloud/CloudSyncService.cs`. Mismo ciclo:
///
///   1. **PUSH** — lee el outbox pendiente por lotes hasta vaciarlo, marca los
///      aceptados como enviados (idempotente por `(licencia, id de evento)` en
///      el backend) y cuenta los intentos fallidos: al superar `maxIntentos` el
///      evento va a **dead-letter**, para que uno venenoso no bloquee la cola.
///   2. **PULL** — descarga desde el cursor, aplica con **last-write-wins** y
///      avanza el cursor.
///
/// Es **reanudable**: lo enviado queda marcado y el cursor se persiste después
/// de aplicar cada página, así que un corte a mitad no reenvía ni pierde.
///
/// Lo que añade el móvil sobre el escritorio:
///   - **Defensa contra eco.** El filtro principal ya es server-side
///     (`GET /sync/pull?origen=<origen_caja_id>`), pero aquí se vuelve a
///     filtrar: el server no filtra si `origen` llega vacío y no controlamos
///     contra qué versión del backend corre cada instalación. Con PC + móvil,
///     el eco es tráfico duplicado y riesgo de que un LWW tardío pise un dato
///     más nuevo.
///   - **Paginación por salto de cursor.** El cursor del backend avanza sobre la
///     ventana SIN filtrar, así que una página puede venir vacía y aun así tener
///     más detrás. La condición de "hay más" mira cuánto saltó la secuencia, no
///     cuántos cambios visibles llegaron.
///   - **Dos 403 distintos.** Licencia sin `cloud_sync` (se arregla comprando) y
///     asiento revocado con `DELETE /devices/{id}` (se arregla re-vinculando).
///     Ninguno se reintenta en bucle.
///   - **Alarma de contrato.** `entidadesDesconocidas` del push se registra en
///     el log: es la señal temprana de que los nombres de entidad divergieron
///     entre la PC, el móvil y el backend.
///   - **Aislamiento del evento venenoso por bisección.** Si el backend rechaza
///     un lote entero con un 4xx permanente, partimos el lote a la mitad hasta
///     dar con el evento culpable; los inocentes suben en el mismo ciclo.
///   - **Single-flight.** Los disparos oportunistas (abrir la app, cerrar caja,
///     reconectar) llegan en ráfaga; un solo ciclo corre a la vez.
///
/// REGLA CRÍTICA: `sincronizar()` **nunca** lanza. La venta ya está en SQLite;
/// la nube es eventual por diseño y un fallo de red no puede llegar a la UI de
/// cobro como excepción.
library;

import 'dart:async';

import 'contratos_sync.dart';
import 'puerto_outbox.dart';

class ServicioSyncNube implements ServicioSync {
  ServicioSyncNube({
    required AlmacenOutbox outbox,
    required TransporteSync transporte,
    required OpcionesSync opciones,
    RegistradorSync? registrador,
    DateTime Function()? ahoraUtc,
  })  : _outbox = outbox,
        _transporte = transporte,
        _opciones = opciones,
        _registrar = registrador ?? _sinRegistro,
        _ahoraUtc = ahoraUtc ?? (() => DateTime.now().toUtc()) {
    _estado = const EstadoNube(habilitada: true);
  }

  static void _sinRegistro(String _) {}

  final AlmacenOutbox _outbox;
  final TransporteSync _transporte;
  final OpcionesSync _opciones;
  final RegistradorSync _registrar;
  final DateTime Function() _ahoraUtc;

  final StreamController<EstadoNube> _controlador =
      StreamController<EstadoNube>.broadcast();

  late EstadoNube _estado;

  /// Single-flight: si ya hay un ciclo corriendo, el segundo disparo se cuelga
  /// del mismo Future en vez de duplicar tráfico.
  Future<ResultadoSync>? _cicloEnCurso;

  bool _liberado = false;

  @override
  bool get sincronizacionHabilitada => true;

  @override
  Stream<EstadoNube> get estado => _controlador.stream;

  @override
  EstadoNube get estadoActual => _estado;

  // ===========================================================================
  //  Ciclo público
  // ===========================================================================

  @override
  Future<ResultadoSync> sincronizar() {
    if (_liberado) {
      return Future.value(const ResultadoSync(
        exito: false,
        mensaje: 'El servicio de nube ya fue liberado.',
        motivo: MotivoFalloSync.desconocido,
      ));
    }
    final enCurso = _cicloEnCurso;
    if (enCurso != null) return enCurso;

    final futuro = _ejecutarCiclo().whenComplete(() => _cicloEnCurso = null);
    _cicloEnCurso = futuro;
    return futuro;
  }

  Future<ResultadoSync> _ejecutarCiclo() async {
    _publicar(_estado.copiarCon(sincronizando: true));
    try {
      final resultado = await _cicloProtegido();
      await _refrescarContadoresInterno();
      _publicar(_estado.copiarCon(
        sincronizando: false,
        ultimaSyncUtc: resultado.exito ? _ahoraUtc() : _estado.ultimaSyncUtc,
        ultimaSyncExitosa: resultado.exito,
        entidadesDesconocidas: resultado.entidadesDesconocidas,
        mensaje: resultado.mensaje,
        motivo: resultado.motivo,
      ));
      return resultado;
    } catch (ex) {
      // Red de seguridad final: NADA sale de aquí como excepción.
      final resultado = ResultadoSync(
        exito: false,
        mensaje: 'Error inesperado de sincronización: $ex',
        motivo: MotivoFalloSync.desconocido,
      );
      _publicar(_estado.copiarCon(
        sincronizando: false,
        ultimaSyncExitosa: false,
        mensaje: resultado.mensaje,
        motivo: resultado.motivo,
      ));
      return resultado;
    }
  }

  Future<ResultadoSync> _cicloProtegido() async {
    final push = await _subirPendientes();

    // Si el push abortó, el pull va a fallar por lo mismo (no hay red, el token
    // no sirve, el server está caído): no gastamos otra llamada ni batería.
    // El escritorio hace lo mismo — allí `SubirPendientesAsync` lanza y
    // `BajarCambiosAsync` nunca llega a ejecutarse.
    if (push.motivo != MotivoFalloSync.ninguno) {
      return ResultadoSync(
        exito: false,
        enviados: push.enviados,
        enviadosADeadLetter: push.aDeadLetter,
        entidadesDesconocidas: push.entidadesDesconocidas,
        mensaje: push.mensaje,
        motivo: push.motivo,
      );
    }

    final pull = await _bajarCambios();

    if (pull.motivo != MotivoFalloSync.ninguno) {
      return ResultadoSync(
        exito: false,
        enviados: push.enviados,
        recibidos: pull.recibidos,
        ignoradosPorEco: pull.eco,
        enviadosADeadLetter: push.aDeadLetter,
        entidadesDesconocidas: push.entidadesDesconocidas,
        mensaje: pull.mensaje,
        motivo: pull.motivo,
      );
    }

    return ResultadoSync(
      exito: true,
      enviados: push.enviados,
      recibidos: pull.recibidos,
      ignoradosPorEco: pull.eco,
      enviadosADeadLetter: push.aDeadLetter,
      entidadesDesconocidas: push.entidadesDesconocidas,
      mensaje: 'Sincronización completa: ${push.enviados} enviados, '
          '${pull.recibidos} recibidos.',
    );
  }

  // ===========================================================================
  //  PUSH
  // ===========================================================================

  Future<_ResumenPush> _subirPendientes() async {
    var enviados = 0;
    var aDeadLetter = 0;
    final desconocidas = <String>{};

    // Ids ya intentados en ESTE ciclo. Sin esto, un evento que el backend
    // rechaza pero que sigue pendiente (aún no llegó a maxIntentos) haría que
    // `leerPendientes` devuelva siempre el mismo lote: bucle infinito.
    final intentadosEnEsteCiclo = <String>{};

    while (true) {
      final lote = await _outbox.leerPendientes(_opciones.tamanoLote);
      if (lote.isEmpty) break;

      final frescos =
          lote.where((e) => !intentadosEnEsteCiclo.contains(e.id)).toList();
      if (frescos.isEmpty) break; // sin progreso posible: se reintenta luego

      intentadosEnEsteCiclo.addAll(frescos.map((e) => e.id));
      _avisarEntidadesFueraDeCatalogo(frescos);

      final res = await _enviarConAislamiento(frescos, profundidad: 0);
      enviados += res.aceptados.length;
      aDeadLetter += res.aDeadLetter;
      desconocidas.addAll(res.entidadesDesconocidas);

      if (res.abortar) {
        return _ResumenPush(
          enviados: enviados,
          aDeadLetter: aDeadLetter,
          entidadesDesconocidas: desconocidas,
          motivo: res.motivo,
          mensaje: res.mensaje,
        );
      }

      // Lote incompleto: no hay más pendientes que leer (igual que el escritorio).
      if (lote.length < _opciones.tamanoLote) break;
    }

    if (desconocidas.isNotEmpty) {
      _registrar('SYNC: el backend no reconoce estas entidades: '
          '${desconocidas.join(", ")}. Las guardó igual, pero NADIE las va a '
          'aplicar en el otro extremo. Revisa EntidadesSync.catalogo en los tres lados.');
    }

    return _ResumenPush(
      enviados: enviados,
      aDeadLetter: aDeadLetter,
      entidadesDesconocidas: desconocidas,
    );
  }

  /// Aviso local ANTES de enviar: si estamos a punto de subir una entidad que
  /// ni siquiera está en nuestro propio catálogo, el problema es nuestro y se
  /// detecta sin esperar la respuesta del server.
  void _avisarEntidadesFueraDeCatalogo(List<EventoSyncLocal> lote) {
    final raras = lote
        .map((e) => e.entidad)
        .where((e) => !EntidadesSync.esConocida(e))
        .toSet();
    if (raras.isNotEmpty) {
      _registrar('SYNC: entidades fuera del catálogo local en el outbox: '
          '${raras.join(", ")}.');
    }
  }

  /// Envía [lote]; si el backend lo rechaza con un 4xx permanente, lo parte en
  /// dos para aislar el evento venenoso en vez de castigar a todo el lote.
  ///
  /// Sin esto, un solo evento malformado (un payload corrupto, una entidad que
  /// el backend todavía no conoce — `mesa`/`pedido` antes de que `backend-seats`
  /// los amplíe) haría que los otros 99 eventos del lote acumulen intentos y
  /// acaben en dead-letter sin culpa ninguna.
  Future<_ResultadoEnvio> _enviarConAislamiento(
    List<EventoSyncLocal> lote, {
    required int profundidad,
  }) async {
    final res = await _transporte.enviarLote(lote);

    if (res.ok) {
      final aceptados = res.aceptadosIds.map((e) => e.toLowerCase()).toSet();
      if (aceptados.isNotEmpty) {
        await _outbox.marcarEnviados(aceptados.toList(growable: false));
      }

      // Rechazados silenciosamente por el backend: cuentan intento / dead-letter.
      final rechazados = lote
          .where((e) => !aceptados.contains(e.id.toLowerCase()))
          .map((e) => e.id)
          .toList(growable: false);
      var muertos = 0;
      if (rechazados.isNotEmpty) {
        muertos = await _outbox.registrarFallo(rechazados, _opciones.maxIntentos);
      }
      return _ResultadoEnvio(
        aceptados: aceptados,
        aDeadLetter: muertos,
        entidadesDesconocidas: res.entidadesDesconocidas.toSet(),
      );
    }

    final tipo = res.tipoFallo ?? TipoFalloSync.red;

    // 403 nº1: la licencia perdió (o nunca tuvo) el flag `cloud_sync`. No es
    // culpa del lote: no gastamos intentos ni mandamos nada a dead-letter.
    if (tipo == TipoFalloSync.sinPermiso) {
      return _ResultadoEnvio(
        abortar: true,
        motivo: MotivoFalloSync.sinPermisoCloud,
        mensaje: 'El respaldo en la nube requiere el plan PagoYa Cloud.',
      );
    }

    // 403 nº2: el asiento fue revocado con DELETE /devices/{id}. El token sigue
    // siendo válido hasta `exp`, así que esto SOLO se sabe por la respuesta.
    // Distinto problema y distinta solución: hay que re-vincular el equipo.
    if (tipo == TipoFalloSync.asientoRevocado) {
      _registrar('SYNC: asiento revocado por el servidor. '
          'Este dispositivo ya no está vinculado a la licencia.');
      return _ResultadoEnvio(
        abortar: true,
        motivo: MotivoFalloSync.dispositivoRevocado,
        mensaje: 'Este dispositivo fue desvinculado de la licencia. '
            'Vuelve a vincularlo para seguir respaldando en la nube.',
      );
    }

    // 401 `token_expirado`: la licencia venció. NO es lo mismo que un token
    // inválido — se renueva con `POST /validate` y lo hace `flutter-licencia`
    // por su cuenta. Como el token se lee por `ProveedorToken` en cada llamada,
    // el siguiente reintento con backoff lo recoge sin que nadie toque nada.
    if (tipo == TipoFalloSync.tokenExpirado) {
      return _ResultadoEnvio(
        abortar: true,
        motivo: MotivoFalloSync.tokenExpirado,
        mensaje: 'Tu licencia venció. Renuévala para seguir respaldando en la nube.',
      );
    }

    if (tipo == TipoFalloSync.autenticacion) {
      return _ResultadoEnvio(
        abortar: true,
        motivo: MotivoFalloSync.tokenInvalido,
        mensaje: 'La licencia no fue aceptada por el servidor (revisa la activación).',
      );
    }

    // Fallo de red / servidor: el transporte ya agotó su backoff. Contamos el
    // intento y cortamos; se reintenta en el próximo ciclo.
    if (esReintentable(tipo)) {
      final muertos =
          await _outbox.registrarFallo(lote.map((e) => e.id).toList(), _opciones.maxIntentos);
      return _ResultadoEnvio(
        abortar: true,
        aDeadLetter: muertos,
        motivo: tipo == TipoFalloSync.servidor
            ? MotivoFalloSync.servidor
            : MotivoFalloSync.sinRed,
        mensaje: res.error,
      );
    }

    // Rechazo permanente (400/404/422/respuesta ilegible).
    if (lote.length == 1 || profundidad >= _maxProfundidadBiseccion) {
      final muertos =
          await _outbox.registrarFallo(lote.map((e) => e.id).toList(), _opciones.maxIntentos);
      return _ResultadoEnvio(
        aDeadLetter: muertos,
        // No abortamos: el resto de la cola tiene que poder seguir subiendo.
        motivo: MotivoFalloSync.ninguno,
        mensaje: res.error,
      );
    }

    final mitad = lote.length ~/ 2;
    final izq = await _enviarConAislamiento(lote.sublist(0, mitad),
        profundidad: profundidad + 1);
    if (izq.abortar) return izq;
    final der = await _enviarConAislamiento(lote.sublist(mitad),
        profundidad: profundidad + 1);

    return _ResultadoEnvio(
      aceptados: {...izq.aceptados, ...der.aceptados},
      aDeadLetter: izq.aDeadLetter + der.aDeadLetter,
      entidadesDesconocidas: {
        ...izq.entidadesDesconocidas,
        ...der.entidadesDesconocidas
      },
      abortar: der.abortar,
      motivo: der.abortar ? der.motivo : MotivoFalloSync.ninguno,
      mensaje: der.mensaje ?? izq.mensaje,
    );
  }

  static const int _maxProfundidadBiseccion = 8; // 2^8 = 256 >= tamanoLote típico

  // ===========================================================================
  //  PULL
  // ===========================================================================

  Future<_ResumenPull> _bajarCambios() async {
    var recibidos = 0;
    var eco = 0;
    var cursor = await _outbox.leerCursor();

    for (var pagina = 0; pagina < _opciones.maxPaginasPull; pagina++) {
      final paquete = await _transporte.descargarCambios(cursor);

      if (!paquete.ok) {
        final tipo = paquete.tipoFallo!;
        return _ResumenPull(
          recibidos: recibidos,
          eco: eco,
          motivo: switch (tipo) {
            TipoFalloSync.sinPermiso => MotivoFalloSync.sinPermisoCloud,
            TipoFalloSync.asientoRevocado => MotivoFalloSync.dispositivoRevocado,
            TipoFalloSync.tokenExpirado => MotivoFalloSync.tokenExpirado,
            TipoFalloSync.autenticacion => MotivoFalloSync.tokenInvalido,
            TipoFalloSync.servidor => MotivoFalloSync.servidor,
            TipoFalloSync.red || TipoFalloSync.limite => MotivoFalloSync.sinRed,
            _ => MotivoFalloSync.desconocido,
          },
          mensaje: switch (tipo) {
            TipoFalloSync.asientoRevocado =>
              'Este dispositivo fue desvinculado de la licencia. '
                  'Vuelve a vincularlo para seguir respaldando en la nube.',
            TipoFalloSync.tokenExpirado =>
              'Tu licencia venció. Renuévala para seguir respaldando en la nube.',
            _ => paquete.error,
          },
        );
      }

      // Defensa contra eco (cinturón y tirantes). El backend YA filtra por el
      // parámetro `origen`, pero seguimos filtrando aquí porque no controlamos
      // contra qué versión del backend corre cada instalación, y re-aplicar un
      // evento propio puede pisar una edición local más reciente.
      final ajenos = _sinEco(paquete.cambios);
      eco += paquete.cambios.length - ajenos.length;

      if (ajenos.isNotEmpty) {
        recibidos += await _outbox.aplicarCambiosRemotos(ajenos);
      }

      // El backend devolvió nuestro mismo cursor => ventana vacía y cursor ya
      // correcto => estamos al día. Es la ÚNICA condición de parada fiable
      // ahora que el filtro de eco es server-side (una página puede venir vacía
      // y tener más detrás).
      if (paquete.cursor == cursor) break;

      // Cursor DESPUÉS de aplicar: si nos cortan aquí, la próxima vez volvemos
      // a bajar esta página y el LWW la vuelve inocua (at-least-once). Al revés
      // perderíamos cambios para siempre.
      await _outbox.guardarCursor(paquete.cursor);

      // ¿Queda otra página? OJO: con el filtro server-side, el cursor avanza
      // sobre la ventana SIN filtrar, así que una página puede venir vacía (o
      // corta) y aun así tener más detrás. Por eso la señal no puede ser
      // "cuántos cambios visibles llegaron" sino "cuánto saltó la secuencia":
      // si saltó una ventana completa, el backend cortó por tope y hay más.
      //
      // Un salto NEGATIVO es el caso de auto-reparación: nuestro cursor estaba
      // por delante de la secuencia real y el server lo acotó a su máximo. Se
      // adopta el cursor reparado y se corta — no hay nada detrás.
      final salto = _delta(cursor, paquete.cursor);
      final hayMas = salto == null
          ? paquete.cambios.length >= _opciones.maxPorPull
          : salto >= _opciones.maxPorPull;

      cursor = paquete.cursor;
      if (!hayMas) break;
    }

    return _ResumenPull(recibidos: recibidos, eco: eco);
  }

  /// Cuánto avanzó el cursor, si ambos son numéricos (lo son: el backend usa
  /// `EventoSync.Secuencia`). `null` si algún día dejan de serlo — en ese caso
  /// nos quedamos con la señal de "página llena".
  static int? _delta(String? anterior, String nuevo) {
    final a = int.tryParse(anterior ?? '0');
    final b = int.tryParse(nuevo);
    if (a == null || b == null) return null;
    return b - a;
  }

  /// Defensa contra eco, capa cliente.
  ///
  /// El filtro principal es server-side (`GET /sync/pull?origen=<origen_caja_id>`)
  /// y este es el cinturón sobre los tirantes: no controlamos contra qué versión
  /// del backend corre cada instalación, el server no filtra si `origen` llega
  /// vacío, y re-aplicar un evento nuestro puede pisar una edición local más
  /// reciente. El coste de mantenerlo es una comparación de strings.
  List<CambioRemoto> _sinEco(List<CambioRemoto> cambios) {
    final mio = _opciones.origenCajaId.trim().toLowerCase();
    if (mio.isEmpty) return cambios; // sin identidad no podemos filtrar
    return cambios
        .where((c) => c.origenCajaId.trim().toLowerCase() != mio)
        .toList(growable: false);
  }

  // ===========================================================================
  //  Contadores / ciclo de vida
  // ===========================================================================

  @override
  Future<void> refrescarContadores() async {
    await _refrescarContadoresInterno();
    _publicar(_estado);
  }

  Future<void> _refrescarContadoresInterno() async {
    try {
      final pendientes = await _outbox.contarPendientes();
      final muertos = await _outbox.contarDeadLetter();
      _estado = _estado.copiarCon(pendientes: pendientes, enDeadLetter: muertos);
    } catch (_) {
      // Contar es informativo; si la BD está ocupada no rompemos el ciclo.
    }
  }

  void _publicar(EstadoNube nuevo) {
    _estado = nuevo;
    if (!_controlador.isClosed) _controlador.add(nuevo);
  }

  @override
  Future<void> liberar() async {
    _liberado = true;
    _transporte.cerrar();
    await _controlador.close();
  }
}

// =============================================================================
//  Tipos internos
// =============================================================================

class _ResumenPush {
  const _ResumenPush({
    required this.enviados,
    required this.aDeadLetter,
    this.entidadesDesconocidas = const {},
    this.motivo = MotivoFalloSync.ninguno,
    this.mensaje,
  });

  final int enviados;
  final int aDeadLetter;
  final Set<String> entidadesDesconocidas;
  final MotivoFalloSync motivo;
  final String? mensaje;
}

class _ResumenPull {
  const _ResumenPull({
    required this.recibidos,
    required this.eco,
    this.motivo = MotivoFalloSync.ninguno,
    this.mensaje,
  });

  final int recibidos;
  final int eco;
  final MotivoFalloSync motivo;
  final String? mensaje;
}

class _ResultadoEnvio {
  const _ResultadoEnvio({
    this.aceptados = const {},
    this.aDeadLetter = 0,
    this.entidadesDesconocidas = const {},
    this.abortar = false,
    this.motivo = MotivoFalloSync.ninguno,
    this.mensaje,
  });

  final Set<String> aceptados;
  final int aDeadLetter;
  final Set<String> entidadesDesconocidas;
  final bool abortar;
  final MotivoFalloSync motivo;
  final String? mensaje;
}
