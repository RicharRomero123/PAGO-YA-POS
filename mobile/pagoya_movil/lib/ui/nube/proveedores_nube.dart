/// Providers Riverpod del módulo de nube (dueño: `flutter-sync`).
///
/// Se declaran aquí, dentro de `ui/nube/`, para no pisar `lib/estado/`, que
/// según `docs/MOBILE-ARQUITECTURA.md` §3 es del dueño de cada módulo.
///
/// ## Lo que este módulo NECESITA que le inyecten
///
/// Dos providers quedan sin implementación a propósito, porque su dueño es otro
/// agente. `main.dart` (mobile-lead / flutter-ui) debe sobreescribirlos en el
/// `ProviderScope` raíz:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     almacenOutboxProvider.overrideWithValue(outboxDrift),        // flutter-datos
///     featuresLicenciaProvider.overrideWithValue(estado.features), // flutter-licencia
///     origenCajaIdProvider.overrideWithValue('M01'),               // flutter-hardware
///     tokenLicenciaProvider.overrideWithValue(() => estado.token), // flutter-licencia
///     urlBaseApiProvider.overrideWithValue('https://api.pagoya.pe'),
///   ],
///   child: const AppPagoYa(),
/// )
/// ```
///
/// Si alguno falta, el fallo es inmediato y ruidoso en el arranque (mejor que
/// una app que "sincroniza" contra la nada).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/nube/nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conectividad_flutter.dart';

// =============================================================================
//  Dependencias externas (las sobreescribe main.dart)
// =============================================================================

/// Outbox local. Lo implementa `flutter-datos` sobre drift.
final almacenOutboxProvider = Provider<AlmacenOutbox>((ref) {
  throw UnimplementedError(
      'almacenOutboxProvider debe sobreescribirse en main.dart con el outbox de drift.');
});

/// Features YA VERIFICADAS por el validador RSA. Nunca deducidas del tier ni de
/// una bandera guardada en claro (`docs/MOBILE-ARQUITECTURA.md` §5.2).
final featuresLicenciaProvider = Provider<Set<String>>((ref) {
  throw UnimplementedError(
      'featuresLicenciaProvider debe sobreescribirse con las features del token verificado.');
});

/// Token de licencia firmado, como función para que la renovación silenciosa
/// (`POST /validate`) no obligue a reconstruir el transporte.
final tokenLicenciaProvider = Provider<ProveedorToken>((ref) {
  throw UnimplementedError('tokenLicenciaProvider debe sobreescribirse en main.dart.');
});

/// Prefijo de este dispositivo (`M01`..`M99`).
///
/// **Lo asigna el SERVER** al vincular el asiento con `POST /devices`: llega en
/// la respuesta y en el claim `device_prefix` del token. El cliente lo
/// **persiste**; no lo genera. Dos móviles inventándose su prefijo colisionan
/// en los correlativos (`M01-000123`) y rompen el filtro de eco.
///
/// El mismo valor viaja como `origen_caja_id` de cada evento del outbox y como
/// parámetro `origen` del `GET /sync/pull`. Los tres tienen que coincidir
/// carácter a carácter.
final origenCajaIdProvider = Provider<String>((ref) {
  throw UnimplementedError(
      'origenCajaIdProvider debe sobreescribirse con el device_prefix que devolvió POST /devices.');
});

/// Sumidero de diagnóstico del módulo de nube. Recibe, entre otras cosas, las
/// `entidadesDesconocidas` que reporta el push: es la señal temprana de que los
/// nombres de entidad divergieron entre la PC, el móvil y el backend.
/// Sobreescríbelo para mandarlo a Crashlytics/Sentry.
final registradorSyncProvider = Provider<RegistradorSync>(
    (ref) => (mensaje) => debugPrint('[nube] $mensaje'));

/// URL base del backend de licencias/sync.
final urlBaseApiProvider = Provider<String>((ref) {
  throw UnimplementedError('urlBaseApiProvider debe sobreescribirse en main.dart.');
});

// =============================================================================
//  Preferencia del usuario: sincronizar en datos móviles
// =============================================================================

const String _clavePrefDatosMoviles = 'nube.permitir_datos_moviles';

/// Preferencia "usar datos móviles para respaldar". Por defecto **sí**: perder
/// una venta duele más que 40 KB de 4G, y el umbral de
/// [OpcionesSync.maxEventosEnDatosMoviles] ya frena los lotes gordos.
class PreferenciaDatosMoviles extends StateNotifier<bool> {
  PreferenciaDatosMoviles() : super(true) {
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_clavePrefDatosMoviles) ?? true;
    } catch (_) {
      // Si las preferencias fallan, el default seguro es permitir.
    }
  }

  Future<void> establecer(bool valor) async {
    state = valor;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clavePrefDatosMoviles, valor);
    } catch (_) {
      // Preferencia no persistida: no es motivo para romper nada.
    }
  }
}

final preferenciaDatosMovilesProvider =
    StateNotifierProvider<PreferenciaDatosMoviles, bool>(
        (ref) => PreferenciaDatosMoviles());

// =============================================================================
//  Composición del módulo
// =============================================================================

final opcionesSyncProvider = Provider<OpcionesSync>((ref) {
  return OpcionesSync(
    origenCajaId: ref.watch(origenCajaIdProvider),
    urlBase: ref.watch(urlBaseApiProvider),
    permitirDatosMoviles: ref.watch(preferenciaDatosMovilesProvider),
  );
});

final sensorConectividadProvider = Provider<SensorConectividad>((ref) {
  final sensor = SensorConectividadFlutter();
  ref.onDispose(sensor.liberar);
  return sensor;
});

/// Transporte HTTP. Se expone aparte del servicio porque el planificador lo usa
/// como sonda de internet real.
final transporteSyncProvider = Provider<TransporteSync>((ref) {
  final transporte = TransporteHttpSync(
    opciones: ref.watch(opcionesSyncProvider),
    proveedorToken: ref.watch(tokenLicenciaProvider),
  );
  ref.onDispose(transporte.cerrar);
  return transporte;
});

/// El servicio: motor real con `cloud_sync`, Null Object sin él.
final servicioSyncProvider = Provider<ServicioSync>((ref) {
  final servicio = FabricaSync.crear(
    featuresVerificadas: ref.watch(featuresLicenciaProvider),
    outbox: ref.watch(almacenOutboxProvider),
    opciones: ref.watch(opcionesSyncProvider),
    transporte: ref.watch(transporteSyncProvider),
    registrador: ref.watch(registradorSyncProvider),
  );
  ref.onDispose(servicio.liberar);
  return servicio;
});

final planificadorSyncProvider = Provider<PlanificadorSync>((ref) {
  final transporte = ref.watch(transporteSyncProvider);
  final plan = PlanificadorSync(
    servicio: ref.watch(servicioSyncProvider),
    opciones: ref.watch(opcionesSyncProvider),
    sensor: ref.watch(sensorConectividadProvider),
    sonda: transporte.hayInternet,
  );
  ref.onDispose(plan.detener);
  return plan;
});

/// Estado observable para la pantalla. Arranca con el último estado conocido
/// para que la UI nunca muestre un spinner vacío.
final estadoNubeProvider = StreamProvider<EstadoNube>((ref) {
  final servicio = ref.watch(servicioSyncProvider);
  return servicio.estado;
});

/// Atajo síncrono: `true` si la licencia habilita la nube.
final nubeHabilitadaProvider = Provider<bool>(
    (ref) => ref.watch(servicioSyncProvider).sincronizacionHabilitada);
