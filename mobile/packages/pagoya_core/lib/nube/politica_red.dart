/// Política de red móvil: cuándo vale la pena sincronizar y cada cuánto.
///
/// El POS de escritorio no necesitaba esto — está enchufado y con cable. En un
/// celular de bodega, mal cargado y con un plan de datos de 3 GB, el polling
/// agresivo es la diferencia entre una app que se usa y una que se desinstala.
///
/// Tres reglas, todas de este archivo:
///   1. **Intervalo adaptativo.** Frecuente solo cuando el negocio está
///      operando (app en primer plano y caja abierta); muy espaciado si no.
///   2. **Conectividad real, no declarada.** `connectivity_plus` dice que hay
///      wifi asociado, no que haya internet: el wifi del mercado con portal
///      cautivo asocia y no enruta. La verificación real la hace
///      [TransporteSync.hayInternet] contra `/health` del propio backend.
///   3. **Datos móviles con consentimiento.** Un lote grande (la cola de una
///      semana sin señal) no se sube por 4G sin que el dueño lo permita.
///
/// Dart PURO: la implementación de [SensorConectividad] que usa
/// `connectivity_plus` vive en la app (`pagoya_movil/lib/ui/nube/`), porque ese
/// paquete depende de Flutter y `pagoya_core` no puede.
library;

import 'contratos_sync.dart';

/// Tipo de red declarada por el sistema operativo. NO implica internet.
enum TipoRed { ninguna, wifi, movil, otra }

/// Fuente de señales de conectividad del sistema. La implementa la app.
abstract class SensorConectividad {
  /// Tipo de red en este instante.
  Future<TipoRed> tipoActual();

  /// Cambios de red. Cada evento es una oportunidad de sync (reconexión).
  Stream<TipoRed> get cambios;
}

/// Sensor que siempre reporta wifi. Útil en tests y en el arranque antes de que
/// la app instale el sensor real.
class SensorConectividadSiempreOnline implements SensorConectividad {
  const SensorConectividadSiempreOnline();

  @override
  Future<TipoRed> tipoActual() async => TipoRed.wifi;

  @override
  Stream<TipoRed> get cambios => const Stream<TipoRed>.empty();
}

/// Estado de la app en el momento de decidir.
enum ModoApp { primerPlano, segundoPlano }

/// Todo lo que la política necesita saber para decidir.
class ContextoSync {
  const ContextoSync({
    required this.modo,
    required this.red,
    this.cajaAbierta = false,
    this.pendientes = 0,
  });

  final ModoApp modo;
  final TipoRed red;

  /// Con la caja abierta se está vendiendo: los datos frescos importan y el
  /// teléfono suele estar en el mostrador, a menudo enchufado.
  final bool cajaAbierta;

  /// Eventos esperando en el outbox.
  final int pendientes;
}

/// Qué hacer ahora mismo.
enum DecisionSync {
  /// Adelante.
  sincronizar,

  /// No hay red declarada: no gastamos ni la sonda. Esperamos la reconexión.
  esperarRed,

  /// Hay red móvil y el lote es grande sin permiso del usuario.
  esperarPermisoDatos,

  /// No hay nada pendiente y no toca el pull todavía.
  nadaQueHacer,
}

/// Motivo legible de la decisión, para la pantalla de nube.
class ResultadoDecision {
  const ResultadoDecision(this.decision, this.mensaje);

  final DecisionSync decision;
  final String mensaje;

  bool get procede => decision == DecisionSync.sincronizar;
}

class PoliticaRedMovil {
  const PoliticaRedMovil({
    this.intervaloCajaAbierta = const Duration(minutes: 1),
    this.intervaloPrimerPlano = const Duration(minutes: 5),
    this.intervaloSegundoPlano = const Duration(minutes: 30),
    this.intervaloSinRed = const Duration(minutes: 15),
  });

  /// App visible + caja abierta: es el único caso que justifica un minuto.
  final Duration intervaloCajaAbierta;

  /// App visible, caja cerrada (mirando reportes, cargando inventario).
  final Duration intervaloPrimerPlano;

  /// App en background. `workmanager` en Android no baja de 15 min de todos
  /// modos, y en Xiaomi/Huawei/Oppo puede no correr nunca: por eso la sync de
  /// verdad es **oportunista** (abrir la app, cerrar caja, reconectar) y esto
  /// es solo el refuerzo.
  final Duration intervaloSegundoPlano;

  /// Sin red no tiene sentido despertar seguido; igual el reconnect dispara.
  final Duration intervaloSinRed;

  /// Cada cuánto reintentar en el contexto dado.
  Duration intervalo(ContextoSync ctx) {
    if (ctx.red == TipoRed.ninguna) return intervaloSinRed;
    if (ctx.modo == ModoApp.segundoPlano) return intervaloSegundoPlano;
    return ctx.cajaAbierta ? intervaloCajaAbierta : intervaloPrimerPlano;
  }

  /// Backoff del planificador tras un ciclo fallido: duplica el intervalo hasta
  /// un tope, para no machacar la batería contra un backend caído.
  Duration intervaloTrasFallo(ContextoSync ctx, int fallosSeguidos) {
    final base = intervalo(ctx);
    final factor = 1 << (fallosSeguidos > 5 ? 5 : fallosSeguidos);
    final ms = base.inMilliseconds * factor;
    const topeMs = 60 * 60 * 1000; // 1 hora
    return Duration(milliseconds: ms > topeMs ? topeMs : ms);
  }

  /// Decide si procede sincronizar. NO hace I/O: la sonda de internet real la
  /// dispara el planificador solo si esto dice que sí.
  ResultadoDecision decidir(ContextoSync ctx, OpcionesSync opciones) {
    if (ctx.red == TipoRed.ninguna) {
      return const ResultadoDecision(
          DecisionSync.esperarRed, 'Sin conexión. Se subirá cuando vuelva la red.');
    }

    if (ctx.red == TipoRed.movil &&
        !opciones.permitirDatosMoviles &&
        ctx.pendientes > opciones.maxEventosEnDatosMoviles) {
      return ResultadoDecision(
        DecisionSync.esperarPermisoDatos,
        'Hay ${ctx.pendientes} operaciones pendientes. Se subirán al conectarte '
        'a una red Wi-Fi, o actívalo en datos móviles desde esta pantalla.',
      );
    }

    // Aunque no haya nada pendiente, el PULL sigue siendo útil: es como llega
    // lo que vendió la otra caja. Solo lo saltamos en background sin pendientes,
    // que es el caso que no justifica despertar la radio.
    if (ctx.pendientes == 0 && ctx.modo == ModoApp.segundoPlano) {
      return const ResultadoDecision(
          DecisionSync.nadaQueHacer, 'Todo al día. Nada por subir.');
    }

    return const ResultadoDecision(DecisionSync.sincronizar, 'Sincronizando…');
  }
}
