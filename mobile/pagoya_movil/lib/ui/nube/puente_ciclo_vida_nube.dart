/// Puente entre el ciclo de vida de la app y el [PlanificadorSync].
///
/// El planificador vive en `pagoya_core` (Dart puro) y por eso no puede saber
/// nada de `WidgetsBindingObserver`. Este widget le traduce los eventos.
///
/// Se envuelve una sola vez, lo más arriba posible del árbol:
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => PuenteCicloVidaNube(child: child!),
///   ...
/// )
/// ```
///
/// Es transparente: no dibuja nada propio y no bloquea el arranque.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proveedores_nube.dart';
import 'sync_background.dart';

class PuenteCicloVidaNube extends ConsumerStatefulWidget {
  const PuenteCicloVidaNube({
    super.key,
    required this.child,
    this.usarWorkerDeRefuerzo = true,
  });

  final Widget child;

  /// Registra además el worker de `workmanager`. Es refuerzo puro: ver la nota
  /// de fabricantes agresivos en `sync_background.dart`.
  final bool usarWorkerDeRefuerzo;

  @override
  ConsumerState<PuenteCicloVidaNube> createState() => _PuenteCicloVidaNubeState();
}

class _PuenteCicloVidaNubeState extends ConsumerState<PuenteCicloVidaNube>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Post-frame: no queremos que la primera pintura espere a la red.
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrancar());
  }

  Future<void> _arrancar() async {
    if (!mounted) return;
    final plan = ref.read(planificadorSyncProvider);
    // `iniciar()` no lanza: si no hay `cloud_sync` simplemente no programa nada.
    await plan.iniciar();

    if (widget.usarWorkerDeRefuerzo &&
        ref.read(nubeHabilitadaProvider) &&
        mounted) {
      await RegistroSyncBackground.registrarPeriodica();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final plan = ref.read(planificadorSyncProvider);
    switch (estado) {
      case AppLifecycleState.resumed:
        // El disparo más fiable de todos: el usuario abrió la app.
        plan.alVolverPrimerPlano();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        plan.alPasarASegundoPlano();
        // Si quedó cola, dejamos agendado un intento: si el sistema nos deja
        // correr, el respaldo avanza aunque el dueño no vuelva a abrir la app.
        if (widget.usarWorkerDeRefuerzo &&
            ref.read(servicioSyncProvider).estadoActual.pendientes > 0) {
          RegistroSyncBackground.registrarUnaVez(
              retraso: const Duration(minutes: 1));
        }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
