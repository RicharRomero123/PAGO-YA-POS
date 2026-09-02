/// Patrón **Null Object** de [ServicioSync]. Port de
/// `src/PagoYa.Cloud/SyncServiceDeshabilitado.cs`.
///
/// Se inyecta cuando el token de licencia NO trae el flag `cloud_sync`
/// (`docs/LICENSE-TOKEN.md` §5) — el mismo caso en el que el backend responde
/// **403** a `/sync/push` y `/sync/pull`.
///
/// Es un no-op total: no abre sockets, no toca el outbox, no programa timers y
/// no lanza. El resto de la app (cobro, caja, inventario) sigue escribiendo su
/// fila en `outbox_sync` como siempre; el día que el dueño compre el tier Cloud
/// esa cola se sube entera sin haber perdido nada. Esa es la razón de que el
/// Null Object no vacíe ni desactive el outbox.
library;

import 'dart:async';

import 'contratos_sync.dart';

class ServicioSyncDeshabilitado implements ServicioSync {
  ServicioSyncDeshabilitado({this.pendientesConocidos = 0});

  /// Opcional: cuántos eventos hay esperando en el outbox. La pantalla lo usa
  /// para el upsell ("tienes 342 ventas listas para respaldar").
  final int pendientesConocidos;

  @override
  bool get sincronizacionHabilitada => false;

  @override
  EstadoNube get estadoActual => EstadoNube(
        habilitada: false,
        pendientes: pendientesConocidos,
        mensaje: 'El respaldo en la nube requiere el plan PagoYa Cloud.',
        motivo: MotivoFalloSync.sinPermisoCloud,
      );

  @override
  Stream<EstadoNube> get estado => Stream<EstadoNube>.value(estadoActual);

  @override
  Future<ResultadoSync> sincronizar() async => ResultadoSync.noHabilitado();

  @override
  Future<void> refrescarContadores() async {}

  @override
  Future<void> liberar() async {}
}
