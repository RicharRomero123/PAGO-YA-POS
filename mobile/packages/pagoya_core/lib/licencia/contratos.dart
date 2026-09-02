/// Contratos del subsistema de **licenciamiento**.
///
/// ## Arbitraje de `mobile-lead` (MOBILE-ARQUITECTURA §4.2)
///
/// `flutter-licencia` publicó estos contratos **junto con sus implementaciones
/// y sus tests** mientras yo escribía una versión paralela de los mismos
/// símbolos. Dos definiciones de `EstadoLicencia` en el mismo paquete es un
/// error de compilación, así que hay que elegir una.
///
/// **Gana la que ya está implementada y probada.** Una interfaz sin
/// implementación no vale más que la misma interfaz con un validador RSA
/// funcionando detrás, y forzar el renombrado habría roto
/// `license_token_validator.dart`, `servicio_licencia.dart`, `guardia_reloj.dart`
/// y sus cuatro archivos de test sin ganar nada.
///
/// Este archivo queda como **punto de entrada estable**: quien importe
/// `licencia/contratos.dart` sigue encontrando todo. Las definiciones viven en
/// `licencia/licencia.dart` y son de `flutter-licencia`.
///
/// ## Dónde está cada cosa ahora
///
/// | Símbolo | Archivo |
/// |---|---|
/// | `EstadoLicencia`, `TierLicencia`, `CaracteristicaLicencia`, `Flags`, `MotivoDegradacion`, `mapearTier` | `estado_licencia.dart` |
/// | `ServicioLicencia` (clase concreta, no interfaz) | `servicio_licencia.dart` |
/// | `crearServicioLicencia`, `crearAlmacenLicencia`, `crearRevalidadorLicencia`, `crearVinculadorAsiento` | `fabrica.dart` |
/// | `AlmacenLicencia`, `RelojAuditado` | `puertos_licencia.dart` |
/// | `IdentidadDispositivo`, `AlmacenSeguro` | `../dispositivo/contratos.dart` (reexportados por `puertos_licencia.dart`) |
/// | `AlmacenLicenciaSegura`, `ClavesSeguras` | `almacen_licencia.dart` |
/// | `RelojAuditadoMeta` (reloj monotónico, regla §5.5) | `reloj_auditado.dart` |
/// | `MetaLicencia`, `ClavesMetaLicencia` | `meta_licencia.dart` |
/// | `RevalidadorLicencia`, `VinculadorAsiento` | archivos homónimos |
/// | `LicenseToken`, `LicenseTokenValidator` | `license_token*.dart` |
///
/// ## Corrección de esta tabla (pasada final de reconciliación, §4.2)
///
/// La versión anterior nombraba cuatro símbolos que **no existen**:
/// `AlmacenMeta` y `RelojUtc` (se fusionaron en `RelojAuditado` +
/// `MetaLicencia`), `ClienteLicenciaApi` (lo sustituyó `ServicioDispositivos`
/// de `nube/contratos.dart`) y `GuardiaReloj` (se convirtió en el puerto
/// `RelojAuditado` con su implementación `RelojAuditadoMeta`).
///
/// Los archivos `guardia_reloj.dart` y `cliente_licencia_api.dart` siguen en
/// disco pero están **inertes** —solo llevan un doc comment— porque el entorno
/// donde se escribieron no tenía shell para borrarlos. Nadie los importa ni los
/// exporta: se pueden borrar sin tocar una línea de código.
///
/// Dos diferencias respecto de lo que yo había propuesto, ambas aceptadas:
///
/// - El catálogo de flags se llama **`Flags`** (igual que la clase estática de
///   C#), no `FlagsLicencia`. Mejor paridad con el escritorio.
/// - **`IdentidadDispositivo` es canónico aquí, en `pagoya_core`**, no en
///   `pagoya_hardware`. El core lo necesita para validar el `hwid` del token, y
///   el core no puede depender del paquete de hardware. `flutter-hardware` debe
///   implementar **esta** interfaz y retirar la suya de
///   `pagoya_hardware/lib/src/identidad/contrato_identidad.dart`.
library;

export 'licencia.dart';
