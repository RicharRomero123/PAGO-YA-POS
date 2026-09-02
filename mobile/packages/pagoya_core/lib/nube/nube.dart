/// Módulo de sincronización en la nube de PagoYa Móvil (dueño: `flutter-sync`).
///
/// Punto de entrada único: el resto de la app importa
/// `package:pagoya_core/nube/nube.dart` y nada más de esta carpeta.
///
/// Mapa rápido:
///   - `contratos_sync.dart`  — modelos del cable + interfaces del servicio.
///   - `puerto_outbox.dart`   — lo que este módulo espera de `flutter-datos`.
///   - `transporte_http_sync.dart` — dio contra `/sync/push` y `/sync/pull`.
///   - `servicio_sync_nube.dart`   — ciclo push/pull reanudable (LWW + eco).
///   - `servicio_sync_deshabilitado.dart` — Null Object sin `cloud_sync`.
///   - `politica_red.dart`    — intervalo adaptativo y política de datos.
///   - `planificador_sync.dart` — cuándo corre el ciclo (oportunista).
///   - `fabrica_sync.dart`    — composición según el flag firmado.
///   - `servicio_dispositivos_http.dart` — cliente de seats (`/devices`),
///     implementación de la interfaz que declara `nube/contratos.dart`.
library;

export 'contratos_sync.dart';
export 'fabrica_sync.dart';
export 'planificador_sync.dart';
export 'politica_red.dart';
export 'puerto_outbox.dart';
export 'servicio_dispositivos_http.dart';
export 'servicio_sync_deshabilitado.dart';
export 'servicio_sync_nube.dart';
export 'transporte_http_sync.dart';
