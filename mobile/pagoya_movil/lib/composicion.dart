/// **Composition root de PagoYa Móvil.**
///
/// Puerto de `src/PagoYa.Desktop/Servicios/CompositionRoot.cs`: aquí se arma el
/// grafo de dependencias y aquí —y **solo** aquí— se aplica el feature-gating
/// por flag firmado.
///
/// Dueño de ESTE archivo: `mobile-lead`. Nadie más lo edita.
///
/// ## Las dos reglas que este archivo hace cumplir
///
/// 1. **Prohibido `if (tier == ...)` esparcido por la app.** Los módulos caros
///    se resuelven al motor real o a un **Null Object** según el flag, y el
///    resto del código siempre depende de la interfaz. Cambiar de plan =
///    cambiar qué objeto se inyecta, no tocar 40 pantallas.
/// 2. **El gating sale del token firmado, nunca de una bandera local.** Un
///    `bool` en preferencias no es una licencia; es un bug de seguridad
///    esperando a que alguien lo encuentre con un editor de APK. Por eso lo que
///    se le pasa a `FabricaSync` es `estado.featuresHabilitadas`, que sale del
///    validador RSA, y no el `tier` ni nada guardado en claro.
///
/// ## Qué NO está aquí
///
/// Pantallas. El router y las vistas son de `flutter-ui` (`app.dart`) y de los
/// dueños de cada carpeta de `lib/ui/`. Este archivo expone
/// [gateArranqueProvider] y ellos deciden qué pintar con él.
///
/// **Tampoco está aquí el sub-grafo de la nube.** Ver la nota de arbitraje de
/// más abajo (§5): `servicioSyncProvider`, `almacenOutboxProvider` y
/// `tokenLicenciaProvider` los declara `flutter-sync` en
/// `lib/ui/nube/proveedores_nube.dart`, y `main.dart` es quien los
/// sobreescribe. Este archivo los declaraba también, y dos providers con el
/// mismo nombre en librerías distintas **no son el mismo provider**: sobrescribir
/// uno dejaba al otro lanzando `UnimplementedError` la primera vez que el dueño
/// de la bodega abriera la pantalla de nube.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

// ===========================================================================
// 0. Claves globales
// ===========================================================================

/// Navigator raíz de la app.
///
/// `flutter-ui` **debe** pasárselo a su router:
/// `GoRouter(navigatorKey: navigatorKeyRaiz, ...)`.
///
/// Existe porque el escáner de cámara vive en `pagoya_hardware`, fuera del
/// árbol de widgets de la app: para abrir su pantalla necesita un navigator y
/// no puede recibir un `BuildContext` sin arrastrar Flutter al núcleo.
final GlobalKey<NavigatorState> navigatorKeyRaiz =
    GlobalKey<NavigatorState>(debugLabel: 'pagoya-raiz');

// ===========================================================================
// 1. Dependencias que se SOBREESCRIBEN en main.dart
// ===========================================================================
//
// Se declaran lanzando a propósito: si alguien olvida el override, la app falla
// al arrancar con un mensaje que dice qué falta y de quién es, en vez de morir
// en producción con un null misterioso.

Never _faltaOverride(String nombre, String duenio) => throw UnimplementedError(
      'El provider "$nombre" no fue sobreescrito en main.dart. '
      'Su implementación la aporta $duenio.',
    );

/// Base de datos local ya abierta y con el esquema aplicado.
///
/// El `QueryExecutor` lo construye `main.dart`, que es quien tiene
/// `sqlite3_flutter_libs` y `path_provider`; `pagoya_core` recibe la conexión
/// hecha y así se puede testear con `NativeDatabase.memory()`.
final Provider<BaseDatosPagoYa> baseDatosProvider =
    Provider<BaseDatosPagoYa>((ref) => _faltaOverride(
          'baseDatosProvider',
          'main.dart, con BaseDatosPagoYa de flutter-datos',
        ));

/// Servicio de licencia ya construido y con la licencia local cargada.
final Provider<ServicioLicencia> servicioLicenciaProvider =
    Provider<ServicioLicencia>((ref) => _faltaOverride(
          'servicioLicenciaProvider',
          'main.dart, con ServicioLicencia de flutter-licencia',
        ));

/// Configuración leída en el arranque. Semilla de [configuracionProvider].
final Provider<ConfiguracionNegocio> configuracionInicialProvider =
    Provider<ConfiguracionNegocio>((ref) => _faltaOverride(
          'configuracionInicialProvider',
          'main.dart, leyendo AlmacenConfiguracion',
        ));

/// Token firmado en crudo, **solo para la facturación electrónica**.
///
/// Se sobreescribe en `main.dart` con lo que devuelva `AlmacenLicencia`. Aquí
/// **no** se usa para nada de gating: solo se transporta. El gating sale del
/// estado ya validado por firma.
///
/// Se llama `…Crudo` y no `tokenLicenciaProvider` a propósito: ese nombre es de
/// `flutter-sync` (`ui/nube/proveedores_nube.dart`), donde además es un
/// `Provider<ProveedorToken>` —una **función**, no un `String?`— para que la
/// revalidación silenciosa (`POST /validate`) rote el token sin reconstruir el
/// transporte HTTP. Esa forma es mejor y gana (§4.2); esta se queda con otro
/// nombre para que `main.dart` pueda importar los dos archivos sin ambigüedad.
final Provider<String?> tokenLicenciaCrudoProvider =
    Provider<String?>((ref) => null);

/// Identidad de este dispositivo (el "HWID" del móvil). La implementa
/// `flutter-hardware` contra la interfaz de `licencia/puertos_licencia.dart`.
final Provider<IdentidadDispositivo> identidadDispositivoProvider =
    Provider<IdentidadDispositivo>((ref) => _faltaOverride(
          'identidadDispositivoProvider',
          'flutter-hardware (pagoya_hardware)',
        ));

// ===========================================================================
// 2. Repositorios — derivados de la base de datos
// ===========================================================================
//
// `BaseDatosPagoYa` expone sus repositorios como getters (contrato de §4), así
// que aquí no hace falta conocer los nombres de las clases concretas: se puede
// reimplementar la capa de datos entera sin tocar este archivo.
//
// PENDIENTE (flutter-datos): estos getters todavía no existen en
// `datos/base_datos_drift.dart`. Es el contrato acordado, no un error.

/// Catálogo de productos.
final Provider<RepositorioProductos> repositorioProductosProvider =
    Provider<RepositorioProductos>(
        (ref) => ref.watch(baseDatosProvider).productos);

/// Ventas y su detalle.
final Provider<RepositorioVentas> repositorioVentasProvider =
    Provider<RepositorioVentas>((ref) => ref.watch(baseDatosProvider).ventas);

/// Sesiones de caja y movimientos de efectivo.
final Provider<RepositorioCaja> repositorioCajaProvider =
    Provider<RepositorioCaja>((ref) => ref.watch(baseDatosProvider).caja);

/// Salón: mesas y comandas.
final Provider<RepositorioMesas> repositorioMesasProvider =
    Provider<RepositorioMesas>((ref) => ref.watch(baseDatosProvider).mesas);

/// Hospedaje: habitaciones, estadías y consumos.
final Provider<RepositorioHotel> repositorioHotelProvider =
    Provider<RepositorioHotel>((ref) => ref.watch(baseDatosProvider).hotel);

/// Proveedores.
final Provider<RepositorioProveedores> repositorioProveedoresProvider =
    Provider<RepositorioProveedores>(
        (ref) => ref.watch(baseDatosProvider).proveedores);

/// Usuarios locales del POS.
final Provider<RepositorioUsuarios> repositorioUsuariosProvider =
    Provider<RepositorioUsuarios>(
        (ref) => ref.watch(baseDatosProvider).usuarios);

/// Agregaciones de reportes.
final Provider<RepositorioReportes> repositorioReportesProvider =
    Provider<RepositorioReportes>(
        (ref) => ref.watch(baseDatosProvider).reportes);

// `almacenOutboxProvider` NO se declara aquí. Lo declara `flutter-sync` en
// `ui/nube/proveedores_nube.dart` y lo sobreescribe `main.dart` con
// `baseDatos.outbox`. Ver la nota de arbitraje de §5.

/// Persistencia de la configuración del negocio.
final Provider<AlmacenConfiguracion> almacenConfiguracionProvider =
    Provider<AlmacenConfiguracion>(
        (ref) => ref.watch(baseDatosProvider).configuracion);

// ===========================================================================
// 3. Estado vivo: licencia, configuración y sesión
// ===========================================================================

/// Estado de licencia observable. **Única** fuente de verdad del gating.
///
/// Se siembra con lo que ya validó `main.dart` y se mantiene al día con el
/// stream del servicio. Eso permite que activar una licencia desbloquee la app
/// **sin reiniciar**: en el escritorio hay que reiniciar, pero en un celular
/// eso sería inaceptable en medio de una venta.
final NotifierProvider<NotificadorLicencia, EstadoLicencia>
    estadoLicenciaProvider =
    NotifierProvider<NotificadorLicencia, EstadoLicencia>(
        NotificadorLicencia.new);

/// Mantiene [estadoLicenciaProvider] sincronizado con `ServicioLicencia`.
final class NotificadorLicencia extends Notifier<EstadoLicencia> {
  @override
  EstadoLicencia build() {
    final servicio = ref.watch(servicioLicenciaProvider);
    final suscripcion = servicio.cambios.listen((estado) => state = estado);
    ref.onDispose(suscripcion.cancel);
    return servicio.estadoActual;
  }
}

/// Configuración del negocio, viva.
final NotifierProvider<NotificadorConfiguracion, ConfiguracionNegocio>
    configuracionProvider =
    NotifierProvider<NotificadorConfiguracion, ConfiguracionNegocio>(
        NotificadorConfiguracion.new);

/// Mantiene [configuracionProvider] al día con lo guardado en `meta`.
final class NotificadorConfiguracion extends Notifier<ConfiguracionNegocio> {
  @override
  ConfiguracionNegocio build() {
    final suscripcion = ref
        .watch(almacenConfiguracionProvider)
        .observar()
        .listen((config) => state = config);
    ref.onDispose(suscripcion.cancel);
    return ref.watch(configuracionInicialProvider);
  }

  /// Guarda y publica una configuración nueva.
  Future<void> guardar(ConfiguracionNegocio config) async {
    await ref.read(almacenConfiguracionProvider).guardar(config);
    state = config;
  }
}

/// Usuario con sesión iniciada, o `null` si nadie entró todavía.
///
/// En una PC de bodega hay un solo cajero; en un restaurante hay tres mozos
/// compartiendo el mismo celular, así que cada comanda tiene que quedar
/// atribuida a quien la tomó.
final NotifierProvider<NotificadorSesion, Usuario?> sesionProvider =
    NotifierProvider<NotificadorSesion, Usuario?>(NotificadorSesion.new);

/// Guarda quién está operando el POS ahora mismo.
final class NotificadorSesion extends Notifier<Usuario?> {
  @override
  Usuario? build() => null;

  /// Registra el ingreso de un usuario.
  void iniciarSesion(Usuario usuario) => state = usuario;

  /// Cierra la sesión (vuelve al login, no a la activación).
  void cerrarSesion() => state = null;
}

// ===========================================================================
// 4. Gate de arranque
// ===========================================================================

/// A dónde debe mandar la app al usuario al abrirse.
///
/// `flutter-ui` consume esto en el `redirect` de su `GoRouter`. **No repliques
/// la lógica en las pantallas**: si mañana cambia la regla de negocio, tiene
/// que cambiar en un solo sitio.
enum EstadoArranque {
  /// Aún cargando licencia o base de datos. Mostrar splash.
  cargando,

  /// No hay token auténtico: pantalla de activación, sin acceso al POS.
  ///
  /// Aplica **también al plan Base** (`CLAUDE.md`): el instalador por sí solo
  /// es un cascarón.
  requiereActivacion,

  /// Licencia OK, pero el dueño todavía no eligió su rubro.
  requiereOnboarding,

  /// Todo listo, falta que alguien inicie sesión.
  requiereLogin,

  /// Entrar al POS.
  listo,
}

/// Decide la pantalla de arranque. Regla §5.1 de MOBILE-ARQUITECTURA.
final Provider<EstadoArranque> gateArranqueProvider =
    Provider<EstadoArranque>((ref) {
  // 1. Licencia primero: sin token auténtico no se entra, sea el plan que sea.
  if (!ref.watch(estadoLicenciaProvider).estaActivada) {
    return EstadoArranque.requiereActivacion;
  }

  // 2. Onboarding: elegir rubro deja la app usable de inmediato (§7).
  if (!ref.watch(configuracionProvider).onboardingCompletado) {
    return EstadoArranque.requiereOnboarding;
  }

  // 3. Quién opera la caja.
  if (ref.watch(sesionProvider) == null) return EstadoArranque.requiereLogin;

  return EstadoArranque.listo;
});

// ===========================================================================
// 5. Módulos premium — FEATURE-GATING por flag firmado
// ===========================================================================
//
// Corazón del archivo y espejo de los dos `AddSingleton` con factory de
// CompositionRoot.cs. Ambos hacen `watch` del estado de licencia, así que si el
// usuario compra un plan superior desde la pantalla de upsell, Riverpod
// reconstruye el motor real sin reiniciar la app.

// ---------------------------------------------------------------------------
// ARBITRAJE (pasada final, MOBILE-ARQUITECTURA §4.2): la nube NO se compone
// aquí.
// ---------------------------------------------------------------------------
//
// Yo declaraba un `servicioSyncProvider` que llamaba a `FabricaSync.crear` con
// lo mínimo. `flutter-sync` declaró otro con el mismo nombre en
// `ui/nube/proveedores_nube.dart`, y el suyo además arma el transporte HTTP, el
// sensor de conectividad, el registrador de diagnóstico, la preferencia de
// datos móviles y el `PlanificadorSync` — y ya lo consumen tres archivos suyos
// (`pantalla_estado_nube.dart`, `puente_ciclo_vida_nube.dart`,
// `sync_background.dart`).
//
// **Gana el suyo**, por el criterio de siempre: tiene implementación y
// consumidores. El mío era una fachada más pobre del mismo objeto.
//
// El gating sigue cumpliendo la regla 2 de la cabecera de este archivo: lo
// aplica `FabricaSync.crear(featuresVerificadas: …)`, y lo que se le pasa sale
// de `estadoLicencia.featuresHabilitadas` —o sea del validador RSA— porque
// `main.dart` sobreescribe `featuresLicenciaProvider` con ese valor. El gating
// no se ha esparcido: solo se mudó de archivo, y sigue habiendo un único punto
// donde se decide.
//
// Quien necesite el servicio de sync hace:
//   import 'ui/nube/proveedores_nube.dart';
//   ref.watch(servicioSyncProvider);

/// Fábrica del motor de facturación real.
///
/// Queda como provider sobreescribible en vez de una llamada directa porque
/// `flutter-sync` todavía no publicó el cliente remoto. Mientras valga `null`,
/// [motorFacturacionProvider] devuelve el Null Object incluso con licencia
/// Facturador Pro — que es el fallo seguro correcto: mejor "no disponible" que
/// emitir mal ante SUNAT.
final Provider<MotorFacturacion Function(OpcionesFacturacion)?>
    fabricaMotorFacturacionProvider =
    Provider<MotorFacturacion Function(OpcionesFacturacion)?>((ref) => null);

/// Facturación electrónica. Motor real solo con el flag `invoicing`.
///
/// Aunque esté habilitada, en móvil **siempre** es un cliente remoto: el `.pfx`
/// no baja al teléfono y aquí no se firma ningún XML (regla §5.6).
final Provider<MotorFacturacion> motorFacturacionProvider =
    Provider<MotorFacturacion>((ref) {
  final licencia = ref.watch(estadoLicenciaProvider);
  if (!licencia.tieneCaracteristica(CaracteristicaLicencia.invoicing)) {
    return const MotorFacturacionDeshabilitado();
  }

  final fabrica = ref.watch(fabricaMotorFacturacionProvider);
  if (fabrica == null) return const MotorFacturacionDeshabilitado();

  final config = ref.watch(configuracionProvider);
  return fabrica(
    OpcionesFacturacion(
      urlBase: config.syncUrlBase,
      tokenLicencia: ref.watch(tokenLicenciaCrudoProvider),
      ruc: config.ruc,
      razonSocial: config.nombreNegocio,
    ),
  );
});

/// Registro de este teléfono como dispositivo secundario (seats).
///
/// **No** está gateado por flag: vincular el celular es parte de la activación
/// y tiene que funcionar incluso en el plan Base. Es justo al revés que la nube
/// o la facturación — aquí el cliente ya pagó, lo único que falta es decirle al
/// backend en qué aparato va a usar lo que compró.
///
/// Ya no devuelve `null` a secas: `backend-seats` publicó `POST /devices` /
/// `DELETE /devices/{id}` y `flutter-sync` publicó el cliente HTTP
/// (`crearServicioDispositivos`), así que el diferido de §6.1 está cerrado.
///
/// **Sigue siendo nullable, y no por inercia**: sin `syncUrlBase` la app está en
/// modo offline puro y no hay backend contra el que vincular. Devolver un
/// cliente apuntando a la cadena vacía daría un fallo de red disfrazado de
/// problema de licencia —"tu licencia tiene un problema" a alguien que solo
/// nunca configuró una URL—, y ese es exactamente el mensaje que no hay que
/// dar. `null` significa "aquí no hay nada que llamar", que es la verdad.
/// `VinculadorAsiento` y `RevalidadorLicencia` ya distinguen ese caso.
final Provider<ServicioDispositivos?> servicioDispositivosProvider =
    Provider<ServicioDispositivos?>((ref) {
  final urlBase = ref.watch(configuracionProvider).syncUrlBase?.trim() ?? '';
  if (urlBase.isEmpty) return null;
  return crearServicioDispositivos(urlBase: urlBase);
});

// ===========================================================================
// 6. Módulos por RUBRO (esto NO es licencia)
// ===========================================================================

/// Catálogo de plantillas por rubro.
final Provider<CatalogoPlantillasRubro> catalogoPlantillasProvider =
    Provider<CatalogoPlantillasRubro>((ref) => _faltaOverride(
          'catalogoPlantillasProvider',
          'flutter-datos (rubros/plantillas_rubro.dart)',
        ));

/// Módulos visibles según el rubro elegido en el onboarding (§7).
///
/// **No confundir con el feature-gating.** Que aparezca "Mesas" depende del
/// giro del negocio; que funcione la nube depende de un flag firmado. Mezclar
/// los dos mecanismos es cómo se termina poniéndole un candado a un botón que
/// el cliente ya pagó.
final Provider<Set<ModuloRubro>> modulosVisiblesProvider =
    Provider<Set<ModuloRubro>>((ref) {
  final rubro = ref.watch(configuracionProvider).rubro;
  return ref.watch(catalogoPlantillasProvider).obtener(rubro).modulos;
});
