/// Planificador de sincronización: decide CUÁNDO corre el ciclo push/pull.
///
/// El motor ([ServicioSync]) sabe *cómo* sincronizar; este objeto sabe *cuándo*,
/// que en móvil es la mitad difícil del problema.
///
/// Filosofía: **sync oportunista**, no sync programada.
/// Xiaomi (MIUI), Huawei (EMUI) y Oppo (ColorOS) matan procesos en background
/// de forma agresiva y, salvo que el usuario meta la app en la lista blanca de
/// batería, un worker periódico simplemente no corre. Por eso los disparos que
/// de verdad mantienen la nube al día son eventos del usuario:
///
///   - abrir la app                  → [alVolverPrimerPlano]
///   - cerrar caja / arqueo          → [alCerrarCaja]
///   - recuperar la conexión         → suscripción a [SensorConectividad]
///   - botón "Sincronizar ahora"     → [sincronizarAhora]
///
/// El temporizador adaptativo y `workmanager` son **refuerzo**: si corren, bien;
/// si el fabricante los mata, no se pierde nada porque la venta ya está en
/// SQLite y el outbox la conserva hasta el próximo disparo oportunista.
///
/// Dart PURO: no toca `WidgetsBindingObserver` ni `workmanager`; la app le
/// avisa de los eventos de ciclo de vida desde `pagoya_movil/lib/ui/nube/`.
library;

import 'dart:async';

import 'contratos_sync.dart';
import 'politica_red.dart';

/// Sonda de internet real. Por defecto es [TransporteSync.hayInternet].
typedef SondaInternet = Future<bool> Function();

class PlanificadorSync {
  PlanificadorSync({
    required ServicioSync servicio,
    required OpcionesSync opciones,
    SensorConectividad? sensor,
    SondaInternet? sonda,
    PoliticaRedMovil politica = const PoliticaRedMovil(),
    Duration debounceReconexion = const Duration(seconds: 3),
  })  : _servicio = servicio,
        _opciones = opciones,
        _sensor = sensor ?? const SensorConectividadSiempreOnline(),
        _sonda = sonda ?? (() async => true),
        _politica = politica,
        _debounceReconexion = debounceReconexion;

  final ServicioSync _servicio;
  final OpcionesSync _opciones;
  final SensorConectividad _sensor;
  final SondaInternet _sonda;
  final PoliticaRedMovil _politica;
  final Duration _debounceReconexion;

  Timer? _temporizador;
  Timer? _debounce;
  StreamSubscription<TipoRed>? _suscripcionRed;

  ModoApp _modo = ModoApp.primerPlano;
  bool _cajaAbierta = false;
  TipoRed _red = TipoRed.otra;
  int _fallosSeguidos = 0;
  bool _activo = false;

  /// Motivo bloqueante activo (403 por falta de flag, 403 por asiento revocado,
  /// 401). Mientras esté puesto NO se programan más ciclos automáticos: ninguno
  /// de esos casos mejora reintentando, y machacar el servidor con un 403 cada
  /// minuto solo gasta batería y datos. El botón manual sí sigue funcionando —
  /// es como el dueño comprueba que ya arregló el problema.
  MotivoFalloSync _bloqueo = MotivoFalloSync.ninguno;

  /// Motivo por el que la sync automática está detenida, o `null` si corre.
  MotivoFalloSync? get bloqueo =>
      _bloqueo == MotivoFalloSync.ninguno ? null : _bloqueo;

  final StreamController<ResultadoSync> _resultados =
      StreamController<ResultadoSync>.broadcast();

  /// Resultado de cada ciclo (para toasts discretos y para la pantalla de nube).
  Stream<ResultadoSync> get resultados => _resultados.stream;

  /// Último motivo por el que NO se sincronizó (p. ej. datos móviles sin
  /// permiso). La pantalla lo muestra tal cual.
  String? get ultimoMotivoOmision => _ultimoMotivoOmision;
  String? _ultimoMotivoOmision;

  /// Qué disparó el último ciclo ("cierre de caja", "reconexión de red", …).
  /// La pantalla de nube lo muestra junto a la hora: da confianza ver
  /// "hace 2 min · por cierre de caja" en vez de un timestamp pelado.
  String? get ultimoDisparo => _ultimoDisparo;
  String? _ultimoDisparo;

  ModoApp get modo => _modo;
  bool get cajaAbierta => _cajaAbierta;

  // ===========================================================================
  //  Ciclo de vida
  // ===========================================================================

  /// Arranca el planificador: se suscribe a la conectividad, sincroniza una vez
  /// (oportunista, al abrir la app) y programa el temporizador adaptativo.
  ///
  /// [sincronizarAlArrancar] solo se pone en `false` en tests, para poder
  /// ejercitar la política sin el disparo de apertura.
  Future<void> iniciar({bool sincronizarAlArrancar = true}) async {
    if (_activo) return;
    _activo = true;

    if (!_servicio.sincronizacionHabilitada) {
      // Null Object: no programamos nada. Sin flag `cloud_sync` no hay ni
      // timers ni radio encendida — solo el upsell en la pantalla.
      return;
    }

    _red = await _leerRedSegura();
    _suscripcionRed = _sensor.cambios.listen(_alCambiarRed, onError: (_) {});

    await _servicio.refrescarContadores();
    if (sincronizarAlArrancar) {
      unawaited(_disparar(motivoOportunista: 'apertura de la app'));
    }
    _reprogramar();
  }

  Future<void> detener() async {
    _activo = false;
    _temporizador?.cancel();
    _temporizador = null;
    _debounce?.cancel();
    _debounce = null;
    await _suscripcionRed?.cancel();
    _suscripcionRed = null;
    if (!_resultados.isClosed) await _resultados.close();
  }

  // ===========================================================================
  //  Disparos oportunistas (los que de verdad importan)
  // ===========================================================================

  /// La app volvió a ser visible. Es el disparo más fiable de todos.
  void alVolverPrimerPlano() {
    _modo = ModoApp.primerPlano;
    _reprogramar();
    unawaited(_disparar(motivoOportunista: 'app en primer plano'));
  }

  /// La app pasó a background: espaciamos y dejamos de insistir.
  void alPasarASegundoPlano() {
    _modo = ModoApp.segundoPlano;
    _reprogramar();
  }

  /// La caja se abrió: entramos en cadencia rápida.
  void alAbrirCaja() {
    _cajaAbierta = true;
    _reprogramar();
  }

  /// Cierre de caja / arqueo: es el momento en que el dueño MÁS quiere que su
  /// día esté respaldado. Se dispara sí o sí, aunque el intervalo no toque.
  void alCerrarCaja() {
    _cajaAbierta = false;
    _reprogramar();
    unawaited(_disparar(motivoOportunista: 'cierre de caja'));
  }

  /// Se registró una venta. No sincroniza de inmediato (sería un ciclo por
  /// ticket en hora punta); solo asegura que los contadores de la pantalla
  /// estén frescos. El temporizador de caja abierta se encarga del resto.
  void alRegistrarVenta() {
    unawaited(_servicio.refrescarContadores());
  }

  void _alCambiarRed(TipoRed red) {
    final antes = _red;
    _red = red;
    if (red == TipoRed.ninguna) {
      _reprogramar();
      return;
    }
    if (antes == TipoRed.ninguna || antes != red) {
      // Reconexión: debounce porque Android emite varios eventos seguidos al
      // asociarse a una red, y no queremos tres ciclos por una sola reconexión.
      _debounce?.cancel();
      _debounce = Timer(_debounceReconexion, () {
        _reprogramar();
        unawaited(_disparar(motivoOportunista: 'reconexión de red'));
      });
    }
  }

  // ===========================================================================
  //  Disparo manual
  // ===========================================================================

  /// Botón "Sincronizar ahora" de la pantalla de nube.
  ///
  /// [forzar] salta la política (el usuario aceptó gastar datos móviles) pero
  /// NO salta el motor: si no hay internet, devuelve un [ResultadoSync] con
  /// `exito: false` y un mensaje entendible. Nunca lanza.
  Future<ResultadoSync> sincronizarAhora({bool forzar = true}) =>
      _disparar(motivoOportunista: 'botón manual', forzar: forzar);

  // ===========================================================================
  //  Núcleo
  // ===========================================================================

  Future<ResultadoSync> _disparar({
    required String motivoOportunista,
    bool forzar = false,
  }) async {
    if (!_servicio.sincronizacionHabilitada) {
      return ResultadoSync.noHabilitado();
    }
    // Bloqueo activo: solo el usuario puede desbloquearlo (pulsando el botón
    // tras comprar el plan o re-vincular el equipo).
    if (_bloqueo != MotivoFalloSync.ninguno && !forzar) {
      return ResultadoSync(
          exito: false, mensaje: _ultimoMotivoOmision, motivo: _bloqueo);
    }

    _ultimoDisparo = motivoOportunista;

    final ctx = ContextoSync(
      modo: _modo,
      red: _red,
      cajaAbierta: _cajaAbierta,
      pendientes: _servicio.estadoActual.pendientes,
    );

    if (!forzar) {
      final decision = _politica.decidir(ctx, _opciones);
      if (!decision.procede) {
        _ultimoMotivoOmision = decision.mensaje;
        return ResultadoSync(
          exito: false,
          mensaje: decision.mensaje,
          motivo: decision.decision == DecisionSync.esperarPermisoDatos
              ? MotivoFalloSync.datosMovilesBloqueados
              : MotivoFalloSync.sinRed,
        );
      }

      // Conectividad REAL. `connectivity_plus` ya dijo que hay wifi; esto
      // comprueba que además haya ruta hasta nuestro backend (portal cautivo,
      // DNS secuestrado, hotspot sin salida).
      if (!await _sondaSegura()) {
        _ultimoMotivoOmision =
            'Hay red pero no internet. Se reintentará automáticamente.';
        _registrarFallo();
        return const ResultadoSync(
          exito: false,
          mensaje: 'Hay red pero no internet. Se reintentará automáticamente.',
          motivo: MotivoFalloSync.sinRed,
        );
      }
    }

    _ultimoMotivoOmision = null;
    // `sincronizar()` es single-flight y no lanza: si dos disparos oportunistas
    // caen juntos, ambos se cuelgan del mismo ciclo.
    final resultado = await _servicio.sincronizar();

    if (resultado.exito) {
      _fallosSeguidos = 0;
      _bloqueo = MotivoFalloSync.ninguno; // el usuario ya lo arregló
    } else {
      _registrarFallo();
      if (esMotivoBloqueante(resultado.motivo)) {
        // 403 (sin plan / dispositivo revocado) o 401. Paramos los ciclos
        // automáticos hasta que alguien haga algo. Nada de bucles de reintento.
        _bloqueo = resultado.motivo;
        _ultimoMotivoOmision = resultado.mensaje;
        _temporizador?.cancel();
        _temporizador = null;
        if (!_resultados.isClosed) _resultados.add(resultado);
        return resultado;
      }
    }
    if (!_resultados.isClosed) _resultados.add(resultado);
    _reprogramar();
    return resultado;
  }

  void _registrarFallo() {
    _fallosSeguidos = _fallosSeguidos >= 5 ? 5 : _fallosSeguidos + 1;
  }

  Future<bool> _sondaSegura() async {
    try {
      return await _sonda();
    } catch (_) {
      return false; // falla suave: nunca propaga
    }
  }

  Future<TipoRed> _leerRedSegura() async {
    try {
      return await _sensor.tipoActual();
    } catch (_) {
      return TipoRed.otra;
    }
  }

  void _reprogramar() {
    _temporizador?.cancel();
    _temporizador = null;
    if (!_activo || !_servicio.sincronizacionHabilitada) return;
    if (_bloqueo != MotivoFalloSync.ninguno) return;

    final ctx = ContextoSync(
      modo: _modo,
      red: _red,
      cajaAbierta: _cajaAbierta,
      pendientes: _servicio.estadoActual.pendientes,
    );
    final espera = _fallosSeguidos == 0
        ? _politica.intervalo(ctx)
        : _politica.intervaloTrasFallo(ctx, _fallosSeguidos);

    _temporizador = Timer(espera, () {
      unawaited(_disparar(motivoOportunista: 'temporizador adaptativo'));
    });
  }
}
