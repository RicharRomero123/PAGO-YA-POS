/// **API pública de `pagoya_core`.**
///
/// La app y `pagoya_hardware` importan `package:pagoya_core/pagoya_core.dart` y
/// nada más. Si algo hace falta afuera, se exporta aquí.
///
/// Dueño de ESTE archivo: `mobile-lead`.
///
/// ---
///
/// ## Estado real del paquete (leer antes de asumir)
///
/// Este barrel refleja lo que **existe hoy**, no lo que se planeó. Seis agentes
/// trabajaron en paralelo y algunos publicaron contratos propios además de sus
/// implementaciones; el arbitraje está resuelto en MOBILE-ARQUITECTURA §4.2 y
/// se resume así:
///
/// | Símbolo | Vive en | Dueño |
/// |---|---|---|
/// | `EstadoLicencia`, `TierLicencia`, `CaracteristicaLicencia`, `Flags`, `MotivoDegradacion`, `mapearTier` | `licencia/estado_licencia.dart` | flutter-licencia |
/// | `ServicioLicencia` (clase concreta), `LicenseTokenValidator`, `crearServicioLicencia` | `licencia/` | flutter-licencia |
/// | `IdentidadDispositivo`, `AlmacenSeguro` | `dispositivo/contratos.dart` (reexportados por `licencia/puertos_licencia.dart`) | **mobile-lead** |
/// | `AlmacenLicencia`, `RelojAuditado`, `MetaLicencia` | `licencia/puertos_licencia.dart`, `licencia/meta_licencia.dart` | flutter-licencia |
/// | `ServicioSync`, `ResultadoSync`, `OpcionesSync`, `TransporteSync`, `EstadoNube`, `FabricaSync` | `nube/` | flutter-sync |
/// | `AlmacenOutbox` | `nube/puerto_outbox.dart` (reexportado por `datos/contratos.dart`) | flutter-sync |
/// | `EventoSyncLocal`, `CambioRemoto`, `EntidadesSync` | `nube/contratos_sync.dart` | flutter-sync |
/// | `Dinero`, entidades, enums, `CalculoVenta` | `dominio/` | flutter-datos |
/// | `BaseDatosPagoYa`, `Esquema`, `EjecutorSql`, `OutboxStore` | `datos/` | flutter-datos |
/// | `Repositorio*`, `ReporteDia` y afines | `datos/contratos.dart` | **mobile-lead** |
/// | `ConfiguracionNegocio`, `AlmacenConfiguracion` | `configuracion/contratos.dart` | **mobile-lead** |
/// | `CatalogoPlantillasRubro`, `PlantillaRubro`, `ModuloRubro` | `rubros/contratos.dart` | **mobile-lead** |
/// | `ProductoPlantilla`, `PlantillasRubro`, `RubroInfo`, `IconosRubro` | `rubros/plantillas_rubro.dart` | flutter-datos |
/// | `MotorFacturacion`, `ResultadoEmision`, `ServicioDispositivos` | `nube/contratos.dart` | **mobile-lead** |
/// | `ImpresoraTickets`, `EscanerCodigos`, `CompartirArchivo`, `HardwarePagoYa` | **`pagoya_hardware`**, no aquí | flutter-hardware |
///
/// ## Lo que todavía falta (y quién lo debe) — verificado archivo por archivo
///
/// - **`flutter-datos`**:
///   - **Borrar** `enum TierLicencia` de `dominio/enums.dart`: duplica el de
///     `licencia/estado_licencia.dart`, que es el que gana (§4.2) porque tiene
///     cuatro suites de test detrás. Mientras siga ahí, este barril lo
///     **oculta** (ver el `hide` de abajo) para que el paquete siga compilando.
///   - **Retirar** `EventoSyncLocal`, `CambioRemoto` y `EntidadesSync` de
///     `datos/outbox.dart` y usar los de `nube/contratos_sync.dart`
///     (veredicto §4.2). El mapeo desde fila SQLite (`desdeFila`, `payload`,
///     `EntidadesSync.todas`, `EntidadesSync.aplicadasPorEscritorio`) se
///     conserva como **extensiones** sobre los tipos canónicos.
///   - `OutboxStore` debe declarar `implements AlmacenOutbox` y completarlo:
///     hoy le faltan `contarDeadLetter()` y `reencolarDeadLetter()`, y su
///     `registrarFallo` devuelve `void` donde el puerto pide `Future<int>`.
///   - Las implementaciones de los `Repositorio*` de `datos/contratos.dart`, de
///     `AlmacenConfiguracion` y de `RepositorioReportes`, publicadas como
///     **getters** de `BaseDatosPagoYa` (`.productos`, `.ventas`, `.caja`,
///     `.mesas`, `.hotel`, `.proveedores`, `.usuarios`, `.reportes`,
///     `.outbox`, `.configuracion`), para que `composicion.dart` no conozca
///     nombres de clase concreta.
///   - `CatalogoPlantillasRubro crearCatalogoPlantillas()` en
///     `rubros/plantillas_rubro.dart`.
/// - **`flutter-hardware`**: una implementación de `AlmacenSeguro` sobre
///   `flutter_secure_storage`, expuesta como `HardwarePagoYa.almacenSeguro`.
///   Es la única pieza que le falta al arranque para armar el licenciamiento.
/// - **`flutter-sync`**: `MotorFacturacion` real. `ServicioDispositivos` ya está
///   (`nube/servicio_dispositivos_http.dart`, `crearServicioDispositivos`) y
///   `composicion.dart` lo cablea.
/// - **`flutter-ui`**: `AppPagoYa` en `pagoya_movil/lib/app.dart`.
///
/// Un `import` roto hacia uno de estos NO es un error a "arreglar" borrando la
/// línea: es el contrato pendiente de otro agente.
library;

// --- Dominio (flutter-datos) ---
//
// `hide TierLicencia`: `dominio/enums.dart` declara un `TierLicencia` propio y
// `licencia/estado_licencia.dart` declara otro. Exportar los dos por el mismo
// barril es un error de compilación en el primer archivo que importe
// `package:pagoya_core/pagoya_core.dart` — es decir, en `main.dart`,
// `composicion.dart` y toda la UI a la vez.
//
// Gana el de `licencia/` (§4.1: "TierLicencia vive en licencia/, no en
// dominio/enums.dart"; y §4.2: gana quien tiene implementación y tests — el de
// licencia lo usan `estado_licencia`, `mapearTier` y cuatro suites; el de
// `enums.dart` no lo usa NADIE).
//
// Esto es un parche de arbitraje, no la solución: `flutter-datos` debe borrar
// su enum y entonces este `hide` se retira. Se hace por `hide` y no editando
// `enums.dart` porque ese archivo no es mío (§3) y porque la regla de la
// cicatriz de §4.2 manda **publicar el ganador antes de retirar al perdedor**:
// el ganador ya está publicado, así que ocultar al perdedor es seguro y
// reversible.
export 'dominio/dominio.dart' hide TierLicencia;

// --- Persistencia (flutter-datos + contratos de mobile-lead) ---
export 'datos/base_datos_drift.dart';
export 'datos/contratos.dart';
export 'datos/ejecutor_sql.dart';
export 'datos/esquema.dart';

// --- Licencia (flutter-licencia) ---
export 'licencia/licencia.dart';

// --- Nube (flutter-sync) + facturación y seats (mobile-lead) ---
export 'nube/contratos.dart';

// --- Contratos exclusivos de mobile-lead ---
export 'configuracion/contratos.dart';
// Puertos de plataforma canónicos del núcleo: `IdentidadDispositivo` y
// `AlmacenSeguro`. `pagoya_hardware` los importa DESDE ESTE BARRIL
// (`import 'package:pagoya_core/pagoya_core.dart' show IdentidadDispositivo;`),
// así que esta línea es carga estructural: si desaparece, no compila el
// paquete de hardware.
export 'dispositivo/contratos.dart';
export 'rubros/contratos.dart';
