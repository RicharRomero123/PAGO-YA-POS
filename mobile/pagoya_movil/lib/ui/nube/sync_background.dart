/// Refuerzo de sincronización en segundo plano con `workmanager`.
///
/// ## Léelo antes de tocarlo: esto es un REFUERZO, no la base
///
/// En Android, un worker periódico:
///   - no baja de **15 minutos** (límite de WorkManager);
///   - en **Xiaomi/MIUI**, **Huawei/EMUI** y **Oppo/ColorOS** puede no ejecutarse
///     **nunca** si la app no está en la lista blanca de batería, cosa que el
///     dueño de una bodega no va a configurar;
///   - en iOS (`BGAppRefreshTask`) corre cuando el sistema quiere, que puede ser
///     una vez al día.
///
/// Por eso la sincronización de verdad es **oportunista** y vive en
/// [PlanificadorSync]: al abrir la app, al cerrar caja, al reconectar, y con el
/// botón "Sincronizar ahora". Si este worker corre, adelanta trabajo; si el
/// fabricante lo mata, no se pierde nada: la venta está en SQLite y el outbox
/// la conserva hasta el próximo disparo oportunista.
///
/// ## El isolate no ve nada de la app
///
/// El callback de `workmanager` corre en un **isolate separado**: no hay
/// `ProviderScope`, ni la base de drift abierta, ni el token en memoria. Hay que
/// ensamblar todo desde cero con estado persistido. Como el armado de la base y
/// la lectura del token pertenecen a `flutter-datos` y `flutter-licencia`, este
/// archivo deja la costura y no la inventa: `main.dart` asigna
/// [ensambladorSyncAislado] al principio del entrypoint del isolate.
library;

import 'package:pagoya_core/nube/nube.dart';
import 'package:workmanager/workmanager.dart';

/// Nombre único de la tarea periódica.
const String tareaSyncPeriodica = 'pagoya.sync.periodica';

/// Nombre de la tarea de una sola vez (se agenda al detectar que quedó cola
/// pendiente cuando el usuario cierra la app).
const String tareaSyncUnaVez = 'pagoya.sync.unavez';

/// Cada cuánto pedimos el worker. 15 min es el mínimo de WorkManager; pedir
/// menos no lo acelera, solo lo hace inválido.
const Duration frecuenciaWorker = Duration(minutes: 15);

/// Ensambla el servicio de sync DENTRO del isolate de background.
///
/// Debe: abrir la base drift, leer el token de `flutter_secure_storage`,
/// verificar la firma, y devolver el [ServicioSync] resultante (o `null` si la
/// licencia no habilita `cloud_sync`, o si no hay token).
typedef EnsambladorSyncAislado = Future<ServicioSync?> Function();

/// Costura que `main.dart` rellena al principio del entrypoint del isolate.
/// Es una global porque el isolate de background NO comparte memoria con el
/// isolate de la UI: no hay forma de pasarle un provider.
EnsambladorSyncAislado? ensambladorSyncAislado;

/// Entrypoint del isolate de background.
///
/// Uso desde `main.dart` (dueño: mobile-lead / flutter-ui):
///
/// ```dart
/// @pragma('vm:entry-point')
/// void despachadorPagoYa() {
///   ensambladorSyncAislado = () async {
///     final db = await abrirBaseLocal();              // flutter-datos
///     final lic = await LicenciaServicio.cargar();    // flutter-licencia
///     if (!lic.features.contains(flagCloudSync)) return null;
///     return FabricaSync.crear(
///       featuresVerificadas: lic.features,
///       outbox: OutboxDrift(db),
///       opciones: OpcionesSync(origenCajaId: lic.origenCajaId, urlBase: urlApi),
///       proveedorToken: () => lic.token,
///     );
///   };
///   despachadorSyncBackground();
/// }
///
/// await Workmanager().initialize(despachadorPagoYa);
/// await RegistroSyncBackground.registrarPeriodica();
/// ```
@pragma('vm:entry-point')
void despachadorSyncBackground() {
  Workmanager().executeTask((tarea, datos) async {
    final ensamblar = ensambladorSyncAislado;
    if (ensamblar == null) {
      // Sin costura configurada no hay nada que hacer; devolver true evita que
      // WorkManager reintente en bucle una tarea que nunca va a funcionar.
      return true;
    }

    ServicioSync? servicio;
    try {
      servicio = await ensamblar();
      if (servicio == null || !servicio.sincronizacionHabilitada) return true;

      final resultado = await servicio.sincronizar();

      // `false` le dice a WorkManager que reintente con SU política de backoff.
      // Solo lo pedimos si fue un fallo transitorio; un 403 por licencia sin
      // `cloud_sync` no mejora reintentando.
      if (!resultado.exito &&
          (resultado.motivo == MotivoFalloSync.sinRed ||
              resultado.motivo == MotivoFalloSync.servidor)) {
        return false;
      }
      return true;
    } catch (_) {
      // REGLA CRÍTICA: ni aquí se propaga nada. Una excepción sin capturar en
      // el isolate de background aparece como un crash en Play Console.
      return true;
    } finally {
      await servicio?.liberar();
    }
  });
}

/// Alta y baja de las tareas de background.
class RegistroSyncBackground {
  const RegistroSyncBackground._();

  /// Programa el refuerzo periódico. Requiere red y, para no vaciar la batería
  /// del celular del mostrador, no exige que esté cargando pero sí que no esté
  /// en ahorro de batería extremo.
  static Future<void> registrarPeriodica() async {
    try {
      await Workmanager().registerPeriodicTask(
        tareaSyncPeriodica,
        tareaSyncPeriodica,
        frequency: frecuenciaWorker,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (_) {
      // Si el fabricante no deja registrar tareas, seguimos sin worker. La sync
      // oportunista es la que sostiene el sistema.
    }
  }

  /// Agenda un intento único, típico al salir de la app con cola pendiente.
  static Future<void> registrarUnaVez({Duration retraso = Duration.zero}) async {
    try {
      await Workmanager().registerOneOffTask(
        '$tareaSyncUnaVez.${DateTime.now().millisecondsSinceEpoch}',
        tareaSyncUnaVez,
        initialDelay: retraso,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // Ídem.
    }
  }

  static Future<void> cancelarTodo() async {
    try {
      await Workmanager().cancelAll();
    } catch (_) {}
  }
}
