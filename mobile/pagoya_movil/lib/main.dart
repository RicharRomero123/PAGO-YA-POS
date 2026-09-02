/// Punto de entrada de PagoYa Móvil.
///
/// Dueño de ESTE archivo: `mobile-lead`. Es el equivalente de `App.OnStartup`
/// del escritorio: abre la base, valida la licencia y arma el grafo. **No hay
/// una sola pantalla aquí** — las vistas son de `flutter-ui`, `mobile-ux` y
/// `flutter-licencia`; este archivo solo decide qué se inyecta.
///
/// ## Orden del arranque (importa)
///
/// 1. Abrir SQLite y aplicar el esquema si falta.
/// 2. Construir los puertos de hardware (almacén seguro, identidad).
/// 3. **Validar la licencia local** — antes de resolver nada premium.
/// 4. Leer la configuración del negocio.
/// 5. Componer el `ProviderScope` con los overrides y levantar la UI.
///
/// La licencia se valida en el paso 3 y no después porque los módulos caros se
/// resuelven mirando el estado ya cargado. Si se invirtiera el orden, durante
/// unos milisegundos el grafo tendría Null Objects donde debería haber motores
/// reales, y una venta hecha en ese instante no entraría al outbox.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';
import 'package:pagoya_hardware/pagoya_hardware.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'composicion.dart';
// El sub-grafo de la nube es de `flutter-sync` (arbitraje §4.2): sus providers
// se declaran allí y se sobreescriben desde aquí, que es lo que hace un
// composition root. Con prefijo para dejar visible de dónde sale cada uno.
import 'ui/nube/proveedores_nube.dart' as nube;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final overrides = await _componer();
    runApp(ProviderScope(overrides: overrides, child: const AppPagoYa()));
  } on Object catch (error, rastro) {
    // Si el arranque falla no hay Riverpod, ni router, ni tema: no se puede
    // usar ninguna pantalla del equipo. Se muestra lo mínimo para que el dueño
    // de la bodega pueda leernos el error por WhatsApp en vez de quedarse
    // mirando un rectángulo gris.
    debugPrint('Fallo de arranque de PagoYa: $error\n$rastro');
    runApp(_PantallaErrorArranque(error: error));
  }
}

/// Construye el grafo completo y devuelve los overrides del `ProviderScope`.
Future<List<Override>> _componer() async {
  // --- 1. Persistencia local (SQLite) --------------------------------------
  // Ruta: el directorio de soporte de la app. En Android es almacenamiento
  // interno privado (no lo ve el explorador de archivos ni otra app) y en iOS
  // queda fuera del respaldo automático de iCloud. Es la data de la caja: se
  // respalda por la nube de PagoYa, no por la de Apple.
  final carpeta = await getApplicationSupportDirectory();
  final rutaDb = p.join(carpeta.path, 'pagoya.db');

  final baseDatos = BaseDatosPagoYa(
    NativeDatabase(File(rutaDb), logStatements: false),
  );
  await baseDatos.inicializarEsquema();

  // --- 2. Puertos de plataforma --------------------------------------------
  // `HardwarePagoYa` es la fachada de `pagoya_hardware`. Su `identidad`
  // implementa `IdentidadDispositivo` de `pagoya_core/dispositivo/contratos.dart`,
  // que es la canónica: el núcleo la necesita para validar el `hwid` del token y
  // no puede depender del paquete de hardware.
  //
  // `--dart-define=SIN_HARDWARE=true` cambia a las implementaciones falsas, que
  // es lo que permite correr toda la app en el emulador sin impresora, sin
  // cámara y sin Keychain.
  final hardware = const bool.fromEnvironment('SIN_HARDWARE')
      ? HardwarePagoYa.falso()
      : HardwarePagoYa.real();

  // PENDIENTE (flutter-hardware): `HardwarePagoYa` todavía no expone un
  // `AlmacenSeguro`. Es la ÚNICA pieza que le falta a este arranque —
  // `crearServicioLicencia` y `crearAlmacenLicencia` la necesitan para guardar
  // el token en Keystore/Keychain. Lo que hace falta es una clase que
  // implemente `AlmacenSeguro` (leer/escribir/borrar) sobre
  // `flutter_secure_storage` —el mismo plugin que ya usa
  // `IdentidadDispositivoSegura`— publicada como campo `almacenSeguro` de
  // `HardwarePagoYa`. No se inventa aquí un fallback en `SharedPreferences`:
  // guardar el token en claro sería un bug de seguridad, no una comodidad.
  final AlmacenSeguro almacenSeguro = hardware.almacenSeguro;

  // --- 3. Licencia (ANTES de resolver cualquier módulo premium) ------------
  // Una sola función de fábrica: `crearServicioLicencia` arma por dentro el
  // validador RSA con la clave embebida, el almacén del token sobre
  // `AlmacenSeguro` y el `RelojAuditado` sobre la tabla `meta` (regla §5.5:
  // detectar el retroceso del reloj con la marca monotónica `ultimo_visto_utc`).
  //
  // `baseDatos` entra como `EjecutorSql`, y `BaseDatosPagoYa implements
  // EjecutorSql`, así que esto compila sin adaptador.
  final servicioLicencia = crearServicioLicencia(
    almacenSeguro: almacenSeguro,
    identidad: hardware.identidad,
    baseDatos: baseDatos,
  );
  final estadoLicencia = await servicioLicencia.cargarLicenciaLocal();

  // Token crudo para los `Authorization: Bearer` de la nube. Se lee del mismo
  // almacén que ya validó el servicio: aquí NO se vuelve a confiar en él para
  // nada de gating, solo se transporta.
  //
  // Se mantiene en una celda que se refresca con cada cambio de licencia
  // (activación, revalidación silenciosa por `POST /validate`) porque
  // `ProveedorToken` es **síncrono** —`String? Function()`— y `leerToken()` es
  // asíncrono: no se puede leer el Keychain dentro del getter. Sin este refresco
  // el transporte HTTP seguiría mandando el token viejo tras renovar, y la nube
  // devolvería 401 `token_expirado` para siempre.
  final almacenLicencia = crearAlmacenLicencia(almacenSeguro);
  String? tokenVigente = await almacenLicencia.leerToken();
  servicioLicencia.cambios.listen((_) async {
    tokenVigente = await almacenLicencia.leerToken();
  });

  // --- 4. Configuración del negocio ----------------------------------------
  // Si no hay nada guardado es el primer arranque: se parte de los valores por
  // defecto con `onboardingCompletado = false`, que es lo que hace que el gate
  // mande al usuario a elegir su rubro.
  final config =
      await baseDatos.configuracion.leer() ?? const ConfiguracionNegocio();

  return <Override>[
    // --- Núcleo -----------------------------------------------------------
    baseDatosProvider.overrideWithValue(baseDatos),
    identidadDispositivoProvider.overrideWithValue(hardware.identidad),
    servicioLicenciaProvider.overrideWithValue(servicioLicencia),
    configuracionInicialProvider.overrideWithValue(config),
    tokenLicenciaCrudoProvider.overrideWithValue(tokenVigente),
    catalogoPlantillasProvider.overrideWithValue(crearCatalogoPlantillas()),

    // --- Sub-grafo de la nube (dueño: flutter-sync) -----------------------
    // Estos cinco son los que `ui/nube/proveedores_nube.dart` declara lanzando
    // `UnimplementedError`: si falta uno, la app revienta al abrir la pantalla
    // de nube, no aquí. Por eso se sobreescriben TODOS, incluso los que hoy
    // valen su defecto.
    //
    // OJO con `featuresLicencia`: es lo que aplica el feature-gating de la
    // nube, y sale de `EstadoLicencia.featuresHabilitadas`, o sea del validador
    // RSA. Nunca del tier ni de una bandera guardada en claro (regla §5.2).
    nube.almacenOutboxProvider.overrideWithValue(baseDatos.outbox),
    nube.featuresLicenciaProvider
        .overrideWithValue(estadoLicencia.featuresHabilitadas),
    // Como función, no como valor: así la revalidación silenciosa
    // (`POST /validate`) rota el token sin reconstruir el transporte HTTP.
    nube.tokenLicenciaProvider.overrideWithValue(() => tokenVigente),
    // El prefijo lo asigna el SERVER en `POST /devices` y viaja en el claim
    // firmado `device_prefix`; el cliente lo persiste, **no lo inventa** (§6).
    // Por eso manda el del token y la configuración local es solo el respaldo:
    // `ConfiguracionNegocio.prefijoDispositivo` trae 'M01' por defecto, que es
    // precisamente el valor inventado que colisiona entre dos celulares de la
    // misma bodega.
    nube.origenCajaIdProvider.overrideWithValue(
      estadoLicencia.prefijoDispositivo ?? config.prefijoDispositivo,
    ),
    nube.urlBaseApiProvider.overrideWithValue(config.syncUrlBase ?? ''),
  ];
}

/// Última línea de defensa: la app no pudo arrancar.
///
/// Deliberadamente sin dependencias del tema ni del router: si algo de eso
/// estuviera roto, esta pantalla también lo estaría.
class _PantallaErrorArranque extends StatelessWidget {
  const _PantallaErrorArranque({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'PagoYa no pudo iniciar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Envía esta pantalla al soporte de PagoYa por WhatsApp. '
                  'Tus ventas guardadas no se han perdido.',
                ),
                const SizedBox(height: 20),
                SelectableText('$error'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
