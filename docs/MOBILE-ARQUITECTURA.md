# PagoYa Móvil — Arquitectura y contrato de trabajo en paralelo

> **Este documento es el contrato compartido de todos los agentes del equipo móvil.**
> Léelo ANTES de escribir una línea de Dart. Si algo aquí choca con lo que ibas a
> hacer, gana este documento; si crees que está mal, avisa a `mobile-lead` en vez
> de improvisar. La app móvil **replica la lógica del POS de escritorio**, no la
> reinventa: mismo backend, mismo esquema SQLite, mismo token de licencia.

---

## 1. Qué se reutiliza del POS de escritorio (NO se rediseña)

| Pieza del repo | Se reutiliza | Cómo |
|---|---|---|
| `src/PagoYa.Data/Esquema/esquema.sql` | **Tal cual** | SQLite es SQLite. Se copia a `mobile/packages/pagoya_core/lib/datos/esquema.sql` sin cambios de forma. |
| `docs/LICENSE-TOKEN.md` | **Tal cual** | Mismo formato `base64url(payload).base64url(firma)`, RSA-2048 PKCS#1 v1.5 + SHA-256. |
| `src/PagoYa.Licensing/ClavePublicaEmbebida.cs` | La clave PEM | Se embebe la **misma** clave pública en Dart. |
| `POST /sync/push`, `GET /sync/pull` (`server/PagoYa.Api/Program.cs`) | **Tal cual** | Auth `Authorization: Bearer <token de licencia>`; el tenant sale de `license_id`. |
| `POST /activate`, `POST /validate` | Se **extienden** (ver §6) | El móvil necesita seats, no traslado de HWID. |
| `src/PagoYa.Core/Enums/RubroNegocio.cs` + `src/PagoYa.Desktop/Servicios/PlantillasRubro.cs` | Se **porta a Dart** | Mismos rubros, mismas claves, mismos productos/categorías de plantilla. |
| `src/PagoYa.Desktop/Themes/PagoYaTheme.xaml` | Se **porta a Dart** | Mismos colores, tipografías y escala. |
| `iconos-app-mobil/*.png` (raíz del repo) | **Set oficial del móvil** | 46 PNG elegidos para la app. Se copian a `mobile/pagoya_movil/assets/iconos/`. Es la **fuente primaria**. |
| `Iconos-POS/*.png` y `src/PagoYa.Desktop/Assets/Iconos/*.png` | Solo para huecos | Si `iconos-app-mobil/` no cubre un concepto (candado, impresora, nube), se toma de aquí. No se inventan iconos nuevos. |

**Regla de oro:** si el escritorio ya resolvió algo (nombre de campo, cálculo de
IGV, clave de rubro, nombre de flag), el móvil usa **exactamente lo mismo**.
Divergir = tickets que no cuadran entre la PC y el celular.

---

## 2. Estructura de carpetas (fija)

```
mobile/
├─ analysis_options.yaml            # reglas estrictas compartidas .. mobile-lead
├─ README.md                        # comandos de puesta en marcha .. mobile-lead
├─ pagoya_movil/                    # App Flutter (Android + iOS)
│  ├─ lib/
│  │  ├─ main.dart                  # arranque + overrides ....... mobile-lead
│  │  ├─ composicion.dart           # grafo DI + feature-gating .. mobile-lead
│  │  ├─ app.dart                   # MaterialApp + go_router
│  │  ├─ ui/
│  │  │  ├─ tema/                   # design system  ......... mobile-ux
│  │  │  ├─ comun/                  # widgets compartidos ..... mobile-ux
│  │  │  ├─ onboarding/             # elección de rubro ....... mobile-ux
│  │  │  ├─ licencia/               # activación / upsell ..... flutter-licencia
│  │  │  ├─ cobro/                  # cobro rápido + carrito .. flutter-ui
│  │  │  ├─ caja/                   # apertura/cierre/arqueo .. flutter-ui
│  │  │  ├─ inventario/             # productos + kardex ...... flutter-ui
│  │  │  ├─ mesas/                  # comandas (rubro comida) . flutter-ui
│  │  │  ├─ habitaciones/           # hotel .................. flutter-ui
│  │  │  ├─ reportes/               # ventas del día ......... flutter-ui
│  │  │  └─ nube/                   # estado de sync ......... flutter-sync
│  │  └─ estado/                    # providers Riverpod ..... dueño del módulo
│  ├─ assets/iconos/                # PNG copiados ........... mobile-ux
│  ├─ android/ , ios/               # permisos y manifests ... flutter-hardware
│  └─ test/                         # widget tests ........... dueño del módulo
└─ packages/
   ├─ pagoya_core/                  # Dart PURO (sin import 'package:flutter/…')
   │  ├─ lib/
   │  │  ├─ pagoya_core.dart        # barrel = API pública ...... mobile-lead
   │  │  ├─ dominio/                # entidades, enums, Dinero .. flutter-datos
   │  │  ├─ datos/                  # drift, esquema, repos, outbox  flutter-datos
   │  │  ├─ rubros/                 # plantillas por rubro ...... flutter-datos
   │  │  ├─ licencia/               # validador RSA + EstadoLicencia  flutter-licencia
   │  │  ├─ nube/                   # cliente push/pull ......... flutter-sync
   │  │  ├─ configuracion/          # SOLO contratos.dart ....... mobile-lead
   │  │  └─ dispositivo/            # vacío tras el arbitraje §4.2
   │  └─ test/                      # tests unitarios ........... dueño del módulo
   └─ pagoya_hardware/              # plugins de plataforma ..... flutter-hardware
      └─ lib/                       # BT ESC/POS, escáner, device id
```

En **cada** carpeta de `pagoya_core/lib/`, el archivo `contratos.dart` es de
`mobile-lead`; el resto de archivos son del dueño de la carpeta. Las carpetas
`configuracion/` y `dispositivo/` solo contienen `contratos.dart`: sus
implementaciones viven en `datos/` (`flutter-datos`) y en `pagoya_hardware`
(`flutter-hardware`) respectivamente.

`pagoya_core` **no puede importar Flutter**. Es la regla que permite reusarlo
mañana en Flutter Web o en un backend Dart.

---

## 3. Mapa de propiedad de archivos (para no pisarse)

Cada agente escribe **solo** en sus carpetas. Si necesitas tocar la carpeta de
otro, pídele el cambio, no lo hagas tú.

| Agente | Escribe en |
|---|---|
| `mobile-lead` | `docs/MOBILE-*.md`, `mobile/README.md`, `mobile/**/pubspec.yaml`, todos los `analysis_options.yaml`, **todos** los `pagoya_core/lib/*/contratos.dart`, `pagoya_core/lib/pagoya_core.dart`, `pagoya_movil/lib/main.dart`, `pagoya_movil/lib/composicion.dart` |
| `flutter-datos` | `pagoya_core/lib/{dominio,datos,rubros}/` **menos** sus `contratos.dart`, `pagoya_core/test/{dominio,datos}/` |
| `flutter-licencia` | `pagoya_core/lib/licencia/` **menos** `contratos.dart`, `pagoya_movil/lib/ui/licencia/`, `pagoya_core/test/licencia/` |
| `flutter-sync` | `pagoya_core/lib/nube/` **menos** `contratos.dart`, `pagoya_movil/lib/ui/nube/`, `pagoya_core/test/nube/` |
| `mobile-ux` | `pagoya_movil/lib/ui/{tema,comun,onboarding}/`, `pagoya_movil/assets/` |
| `flutter-ui` | `pagoya_movil/lib/ui/{cobro,caja,inventario,mesas,habitaciones,reportes}/`, `pagoya_movil/lib/app.dart` |
| `flutter-hardware` | `packages/pagoya_hardware/`, `pagoya_movil/android/`, `pagoya_movil/ios/` |
| `backend-seats` | `server/PagoYa.Api/`, `tests/`, `server/README.md` (nada dentro de `mobile/`) |

### Dos precisiones añadidas en la pasada final (§4.3)

1. **`main.dart` puede IMPORTAR la carpeta de otro agente; no puede editarla.**
   El composition root existe para enchufar módulos ajenos, así que importa
   `ui/nube/proveedores_nube.dart` (de `flutter-sync`) para sobreescribir sus
   providers. Lo hace con prefijo — `import … as nube;` — para que en cada
   `override` se vea de qué módulo es el provider. Escribir en esa carpeta
   sigue prohibido.

2. **Un provider lo declara un solo archivo.** Dos providers con el mismo
   nombre en librerías distintas **no son el mismo provider**, y eso no da error
   de compilación: da un `UnimplementedError` en producción la primera vez que
   alguien abre la pantalla. Si dos módulos necesitan el mismo dato, lo declara
   el que lo consume y `main.dart` lo sobreescribe. Ver el caso real en §4.3.

---

## 4. Decisiones cerradas (no las re-discutas)

| Tema | Decisión | Por qué |
|---|---|---|
| Estado | **Riverpod 2.x** (sin code-gen) | Testeable sin widgets, no necesita BuildContext en la capa de datos. |
| Base local | **drift** sobre `sqlite3_flutter_libs`, con `customStatement` del `esquema.sql` | Mantiene paridad literal de esquema con la PC. **Prohibido** Isar/ObjectBox: rompería el outbox y la sync. |
| Router | **go_router** | Deep links para el flujo de activación. |
| HTTP | **dio** | Interceptores para el Bearer y los reintentos. |
| Cripto RSA | **pointycastle** + **asn1lib** | Verificar PKCS#1 v1.5 + SHA-256 contra la clave pública PEM embebida. |
| Almacenamiento seguro | **flutter_secure_storage** | Token e id de dispositivo. En iOS el Keychain sobrevive la reinstalación (deseado). |
| Escáner | **mobile_scanner** | Cámara como lector de código de barras. |
| Impresión | `esc_pos_utils_plus` (genera bytes) + transporte Bluetooth | La mayoría de térmicas baratas en Perú son **SPP clásico**, no BLE: `print_bluetooth_thermal` primero, BLE como respaldo. |
| Dinero | Clase **`Dinero`** en `dominio/dinero.dart`: entero de céntimos internamente, se persiste como `double` redondeado a 2 decimales | `double` acumulando centavos diverge del `decimal` de C#. |
| IGV | **18 %**, con la **misma** fórmula y redondeo que `CobroRapidoViewModel` | Paridad de totales con la PC. |
| Idioma | Dominio en **español** (`Venta`, `Caja`, `Comprobante`); técnico en inglés | Igual que el resto del repo. |
| Plataforma | **Android primero**, iOS después | El mercado (bodegas Perú) es Android; iOS necesita Mac + $99/año. |

### 4.1 Decisiones cerradas por `mobile-lead` al publicar los contratos

| Tema | Decisión | Por qué |
|---|---|---|
| `pagoya_core` es un paquete **Dart puro**, no Flutter | `environment: sdk` sin `flutter`, y `depend_on_referenced_packages: error` en su `analysis_options.yaml` | La invariante "core no importa Flutter" deja de ser un acuerdo de caballeros: cualquier `import 'package:flutter/…'` allí **falla el análisis**, porque flutter no está en sus dependencias. |
| Libs nativas de SQLite y ruta del `.db` | Viven en `pagoya_movil`, no en el core (`sqlite3_flutter_libs`, `path_provider`) | `BaseDatosPagoYa` recibe un `QueryExecutor` ya construido. Así el core se testea con `NativeDatabase.memory()` sin Flutter. |
| `esquema.sql` | Se embebe como **constante Dart** en `pagoya_core/lib/datos/esquema_sql.dart` (copia literal del `.sql` del escritorio) | Un paquete Dart puro no puede declarar assets de Flutter. Es el equivalente del `EmbeddedResource` de `PagoYa.Data`. |
| `Guid` de C# → **`String`** en Dart | Las PK ya son UUID en TEXT (ARQUITECTURA §4) | Un tipo `Guid` propio sería una capa de conversión sin ganancia. |
| `decimal` de C# | **`Dinero`** si es plata, `double` si es cantidad | Céntimos exactos solo hacen falta donde hay céntimos. Kilos y unidades no. |
| `DateOnly` de C# | `DateTime` a medianoche **local** | Es fecha de negocio (el día del POS), no un instante UTC. |
| `CancellationToken` | Se omite en las firmas Dart | No existe equivalente; se cancela cerrando el stream o descartando el `Future`. |
| `TierLicencia` | Vive en `licencia/`, **no** en `dominio/enums.dart` | Es parte del contrato del token, no del dominio de ventas. Así `flutter-licencia` no queda bloqueado esperando a `flutter-datos`. |
| Factory de `EstadoLicencia` | Se llama **`baseSegura()`**, no `base()` | `base` es identificador reservado por el modificador de clase de Dart 3. (Los dos agentes llegamos a lo mismo por separado.) |
| Null Objects (`ServicioSyncDeshabilitado`, `MotorFacturacionDeshabilitado`) | Viven junto a su interfaz, en el módulo que la define | Son parte del contrato (como `ResultadoSync.NoHabilitado()` en C#) y el composition root los necesita sin depender del motor real. |
| Puertos de plataforma | `IdentidadDispositivo`, `AlmacenLicencia`, `AlmacenMeta`, `RelojUtc` en `pagoya_core/lib/licencia/puertos_licencia.dart`; impresora, escáner y compartir en `pagoya_hardware` | Ver arbitraje en §4.2. Lo que el **núcleo** consume tiene que estar en el núcleo; lo que solo consume la UI puede vivir en el paquete de hardware. |
| Configuración del negocio | Carpeta nueva `pagoya_core/lib/configuracion/contratos.dart` (`ConfiguracionNegocio`, `AlmacenConfiguracion`), persistida en la tabla **`meta`** de SQLite | En el escritorio es un `config.json` suelto; en móvil va a `meta` para que entre en el mismo respaldo que los datos. |
| Acceso a repositorios | `BaseDatosPagoYa` los expone como **getters** (`.productos`, `.ventas`, …) | El composition root no necesita conocer los nombres de las clases drift: se puede reimplementar la capa de datos sin tocar `composicion.dart`. |
| Construcción de servicios entre agentes | **Un solo símbolo de entrada por módulo**: `FabricaSync.crear`, `PuertosHardware.*`, `crearCatalogoPlantillas`, y los getters de repositorio de `BaseDatosPagoYa` | Diez nombres de clase concreta acoplados entre agentes es diez oportunidades de romper el build ajeno. Las firmas exactas están al final de §4.2. |
| Lo que aún no existe | Se inyecta como **provider sobreescribible** (`fabricaMotorFacturacionProvider`, `servicioDispositivosProvider`), con Null Object por defecto | Permite que `composicion.dart` compile y gatee bien hoy, y que `flutter-sync` enchufe el motor real mañana **sin editar el composition root**. Fallo seguro: sin motor, "no disponible" en vez de emitir mal ante SUNAT. |
| Gate de arranque | `gateArranqueProvider` en `composicion.dart` devuelve `EstadoArranque.{cargando, requiereActivacion, requiereOnboarding, requiereLogin, listo}` | El `redirect` del `GoRouter` de `flutter-ui` **debe** consumirlo. Prohibido replicar la regla en las pantallas. |
| Navigator raíz | `navigatorKeyRaiz` (global en `composicion.dart`); `flutter-ui` lo pasa a `GoRouter(navigatorKey: …)` | El escáner de cámara vive en `pagoya_hardware`, fuera del árbol de widgets, y no puede recibir un `BuildContext` sin romper la pureza del core. |
| Desbloqueo tras activar | Los módulos premium hacen `ref.watch(estadoLicenciaProvider)`, así que se reconstruyen **sin reiniciar** | En el escritorio hay que reiniciar la app tras activar; en un celular eso es inaceptable en medio de una venta. |
| `permission_handler` y `device_info_plus` | Añadidos a `pagoya_hardware` (no estaban en la lista original) | Sin `permission_handler` el escáner y el Bluetooth fallan **en silencio** en Android 13/14. Sin `device_info_plus` no hay de dónde sacar el id del dispositivo. |
| Correlativo por dispositivo | `ConfiguracionNegocio.prefijoDispositivo` (`M01`) + `RepositorioVentas.siguienteNumero(prefijo)` | Materializa el formato `<prefijo>-<correlativo>` acordado en §6. |
| Ancho de papel por defecto | **58 mm** en móvil (32 columnas), contra 80 mm en el escritorio | La impresora que se lleva un mozo en el bolsillo casi siempre es de 58 mm. |
| Versiones de los `pubspec.yaml` | Fijadas con rango `^` a partir de las últimas estables **conocidas**, sin verificar contra pub.dev (no hay red en la sesión) | Si `pub get` falla por una versión, se reporta a `mobile-lead`; **nadie más edita dependencias** (§3). |

---

## 4.2 Arbitraje: contratos duplicados (resuelto por `mobile-lead`)

Los siete agentes trabajaron **a la vez y a ciegas** sobre el mismo `pagoya_core`.
Resultado previsible: `mobile-lead` publicó contratos que `flutter-licencia`,
`flutter-sync` y `flutter-hardware` ya habían escrito por su cuenta —dos
`EstadoLicencia`, dos `ServicioSync`, dos `IdentidadDispositivo`, dos
`AlmacenOutbox`—. Dos definiciones del mismo símbolo en un paquete es un error
de compilación, así que hubo que elegir.

**Criterio aplicado: gana la definición que ya tiene implementación y tests.**
Una interfaz sin nada detrás no vale más que la misma interfaz con un validador
RSA funcionando, y forzar el renombrado habría roto código probado sin ganar
nada.

| Símbolo | Ganador | Perdedor (ya retirado) |
|---|---|---|
| `EstadoLicencia`, `TierLicencia`, `CaracteristicaLicencia`, `Flags`, `MotivoDegradacion` | `licencia/estado_licencia.dart` (flutter-licencia) | los míos en `licencia/contratos.dart` |
| `ServicioLicencia` — **clase concreta**, no interfaz | `licencia/servicio_licencia.dart` | ídem |
| `AlmacenLicencia`, `IdentidadDispositivo`, `AlmacenMeta`, `RelojUtc` | `licencia/puertos_licencia.dart` | los míos en `dispositivo/contratos.dart` |
| `GuardiaReloj` (reloj monotónico, §5.5) | `licencia/guardia_reloj.dart` | mi `RelojAuditado` |
| `ServicioSync`, `ResultadoSync`, `OpcionesSync`, `EstadoNube`, `TransporteSync` | `nube/contratos_sync.dart` (flutter-sync) | los míos en `nube/contratos.dart` |
| `AlmacenOutbox`, `EventoSyncLocal`, `CambioRemoto` | `nube/puerto_outbox.dart` + `nube/contratos_sync.dart` — **cerrado en §4.3** | los míos en `datos/contratos.dart` |
| `ImpresoraTickets`, `EscanerCodigos`, `CompartirArchivo` | `pagoya_hardware` (flutter-hardware) | los míos en `dispositivo/contratos.dart` |
| Gating de sync | `FabricaSync.crear(featuresVerificadas: …)` | mi factory en el provider |

Las dos reglas de aquí abajo están cerradas:

1. **`IdentidadDispositivo` y `AlmacenSeguro` son canónicos en `pagoya_core`**,
   publicados en **`dispositivo/contratos.dart`** y reexportados por
   `licencia/puertos_licencia.dart`. El núcleo valida el `hwid` del token contra
   el id del dispositivo y guarda el token cifrado; **no puede depender de
   `pagoya_hardware`** sin romper la invariante de que es Dart puro.
   `flutter-hardware` ya implementa esa interfaz y retiró su copia.

   > **Cicatriz de este arbitraje, para no repetirla.** Al retirar los
   > duplicados, `dispositivo/contratos.dart` y `puertos_licencia.dart`
   > quedaron un rato **los dos vacíos apuntándose mutuamente**, y como
   > `flutter-hardware` ya había retirado la suya, `IdentidadDispositivo` dejó
   > de existir en el árbol: cinco archivos del núcleo sin compilar. Lección:
   > al arbitrar un duplicado, **primero se publica la versión ganadora y
   > después se retiran las perdedoras**, nunca al revés.

   Nombres correctos, los de producción (`flutter-hardware` ya los implementa):

   ```dart
   abstract interface class IdentidadDispositivo {
     Future<String> obtenerIdDispositivo();
     Future<String> obtenerNombreDispositivo();
     Future<String> obtenerPlataforma();   // 'android' | 'ios'
   }
   ```

   El doble de test `pagoya_core/test/licencia/dobles.dart` usa `obtenerId()` /
   `obtenerNombre()`, que es la forma vieja y **no** es la que gana.
   `flutter-licencia` lo está alineando.

   **El id es un UUID v4 persistido en el almacén seguro**, nunca derivado de
   `androidId` ni de `identifierForVendor`: los dos rotan solos y al rotar
   desactivarían al cliente en plena jornada de ventas.
2. **`ImpresoraTickets`, `EscanerCodigos` y `CompartirArchivo` se quedan en
   `pagoya_hardware`.** Ningún archivo del núcleo los usa: son puertos de UI, no
   de dominio. Las versiones de `flutter-hardware` además modelan estado de
   impresora, tipo de conexión y causa de fallo, que es justo donde duele el
   soporte por WhatsApp.

Lo que **sí** queda como contrato exclusivo de `mobile-lead`, porque nadie más
lo escribió y el composition root lo necesita:

- `datos/contratos.dart` → los ocho `Repositorio*` y la familia `ReporteDia`.
- `configuracion/contratos.dart` → `ConfiguracionNegocio`, `AlmacenConfiguracion`.
- `rubros/contratos.dart` → `CatalogoPlantillasRubro`, `PlantillaRubro`, `ModuloRubro`.
- `nube/contratos.dart` → `MotorFacturacion`, `ResultadoEmision`,
  `OpcionesFacturacion`, `MotorFacturacionDeshabilitado`, `ServicioDispositivos`.

Los archivos `licencia/contratos.dart` y `dispositivo/contratos.dart` quedan
como **redirecciones documentadas** (reexportan o explican dónde fue todo), para
no romper imports y para dejar constancia de por qué.

---

## 4.3 Pasada final de reconciliación (cerrada por `mobile-lead`)

Con los siete agentes cerrados se recorrió el árbol entero archivo por archivo.
**Nada de esto se compiló** (no hay shell en la sesión): son veredictos y
lecturas, no resultados de `flutter analyze`.

### Veredictos

| Conflicto | Gana | Pierde | Por qué |
|---|---|---|---|
| `TierLicencia` | `licencia/estado_licencia.dart` | `dominio/enums.dart` | El de licencia lo usan `mapearTier`, `EstadoLicencia` y 4 suites; el de `enums.dart` **no lo usa nadie**. Además §4.1 ya lo había decidido. Era `ambiguous_export` en el barril: rompía la app entera. |
| `AlmacenOutbox` | `nube/puerto_outbox.dart` | — (nadie más lo declaró) | El puerto pertenece a **quien lo consume**: así `nube/` no depende de drift, igual que `PagoYa.Cloud` depende de `IOutboxStore` y no de `PagoYa.Data`. `datos/contratos.dart` lo reexporta y ese `export` deja de ser provisional. |
| `EventoSyncLocal`, `CambioRemoto`, `EntidadesSync` | `nube/contratos_sync.dart` | `datos/outbox.dart` | Empate por el criterio de tests (ambos tienen). Decide la arquitectura: son el **contrato del cable**, sus campos deben coincidir con `server/…/Dtos.cs`, y la versión de `nube/` es la que sabe serializar. El mapeo desde fila SQLite se conserva como **extensiones**, así que `flutter-datos` no pierde nada. |
| `ProductoPlantilla` | `rubros/plantillas_rubro.dart` | `rubros/contratos.dart` | El suyo tiene los campos DIGEMID y la corrección de `AddMonths`; tiene `SembradorCatalogo` y tests detrás. El mío no tenía ni implementación ni tests. Ya retirado; `contratos.dart` reexporta el suyo. |
| `servicioSyncProvider`, `almacenOutboxProvider`, `tokenLicenciaProvider` | `ui/nube/proveedores_nube.dart` (flutter-sync) | `composicion.dart` | El suyo arma además transporte, sensor de conectividad, registrador, preferencia de datos móviles y planificador, y ya lo consumen tres archivos suyos. El mío era una fachada más pobre del mismo objeto. |
| Fachada de hardware | `HardwarePagoYa` (`.real()` / `.falso()`) | `PuertosHardware` (mi contrato) | `PuertosHardware` **nunca se construyó**; `HardwarePagoYa` existe y funciona. Contrato retirado: `main.dart` reescrito contra el que existe. |
| Puerto de selección de archivos | `SelectorArchivoLicencia` en `ui/licencia/proveedores_licencia.dart`, **diferido** | — | Ver abajo. |

### Dos providers con el mismo nombre NO son el mismo provider

Es la trampa que casi se cuela y merece quedar escrita, porque no da error de
compilación: `composicion.dart` y `ui/nube/proveedores_nube.dart` declaraban
cada uno un `tokenLicenciaProvider`. Sobrescribir el mío en el `ProviderScope`
dejaba el suyo lanzando `UnimplementedError`, y eso **no se nota al arrancar**:
se nota la primera vez que el dueño de la bodega abre la pantalla de nube.

Regla derivada: **un provider lo declara un solo archivo**. Si dos módulos
necesitan el mismo dato, lo declara el consumidor y `main.dart` lo sobreescribe.
El composition root sí puede importar el archivo de providers de otro agente —
es precisamente su trabajo— y lo hace con prefijo (`import … as nube;`) para que
se vea de dónde sale cada override.

### `codigo` en `ResultadoVinculacion` (añadido, no retirado)

`ResultadoVinculacion` exponía `{exito, tokenFirmado, mensaje}` y le faltaba
`codigo`. Consecuencia: el clasificador code-first de `flutter-licencia`
(`codigos_error_licencia.dart`) devolvía siempre `null` y **todo** el flujo de
asientos caía a la ruta de compatibilidad por subcadenas del mensaje — el
trabajo estaba hecho pero solo se ejercitaba en sus tests.

Campo añadido, y `flutter-sync` **ya lo rellena en los dos caminos** (error y
éxito) desde `ServicioDispositivosHttp`. El circuito está cerrado de punta a
punta, así que la ruta de compatibilidad por subcadenas de
`codigos_error_licencia.dart` **ya se puede borrar**: es la única deuda que deja
este arreglo.

Distinguir por código no es elegancia: "tu plan no incluye este equipo", "este
equipo fue desvinculado" y "tu licencia venció" se arreglan de tres formas y con
tres precios distintos, y por texto son indistinguibles en cuanto alguien
reescriba un mensaje.

> Añadir un campo en paralelo es seguro. El incidente de `IdentidadDispositivo`
> fue por **retirar** en paralelo, no por añadir.

### Los literales de código de error viven en UN sitio

El docstring de `codigo` ponía `sin_asientos_libres` como ejemplo y **ese código
no existe**: nunca estuvo en `CodigosError`. El real es
`cupo_dispositivos_lleno`. Corregido.

No es cosmética. Un ejemplo inventado en un doc es una **rama muerta en
potencia**: quien ramifique por él escribe un `if` que no dispara nunca, y eso
no lo ve el compilador ni un test — se ve el día que un cliente se queda sin
cupo de dispositivos y la app, en vez de ofrecerle el plan mayor, le muestra un
error genérico. Se pierde la venta justo en el momento en que el cliente estaba
pidiendo comprar.

Regla, ahora explícita en el propio docstring: **la fuente única del catálogo es
`server/README.md` §10 + `CodigosError` de `Dtos.cs`**. En el móvil los
literales se declaran en dos archivos y solo dos —
`licencia/codigos_error_licencia.dart` y `CodigosErrorSync` de
`nube/contratos_sync.dart`—; el resto los consume por constante. Verificados
carácter a carácter contra C#: los 16 que usa el móvil coinciden. El único que
no coincidía era el del docstring, que no lo usaba nadie precisamente porque no
existía.

### `revocar({idDispositivo})` → `revocar({idAsiento})`

Cambio de contrato en `ServicioDispositivos`, propuesto por `flutter-licencia`
tras investigarlo. **Elimina una clase de bug entera**, no un bug.

El sistema maneja dos identificadores que se parecen y no son intercambiables:

| Valor | De dónde sale | Dónde va |
|---|---|---|
| **Huella del equipo** | `IdentidadDispositivo.obtenerIdDispositivo()` (UUID v4 del almacén seguro) | cuerpo de `POST /devices` y claim `hwid` |
| **GUID del asiento** | claim `device_id` del token emitido, persistido en `meta` | ruta de `DELETE /devices/{id}` |

Pasarle la huella a `DELETE /devices/{id}` da **404**, y el daño no es un error
en pantalla: el dueño se queda fuera del POS *y* con el asiento todavía ocupado
en el servidor, así que tampoco puede activar otro celular. Justo el escenario
que el modelo de seats existía para evitar.

`flutter-licencia` ya lo había resuelto en su call site y lo había documentado.
No bastaba: **un comentario protege a quien lo lee, el nombre del parámetro
protege a todos**. El siguiente que implemente `ServicioDispositivos` —o que
llame a `revocar` desde una pantalla de ajustes— no va a leer ese comentario.

`vincular({idDispositivo})` **conserva** su nombre: ahí el valor correcto sí es
la huella. La asimetría de nombres es la señal.

Aplicado en un solo paso a las 8 apariciones (3 declaraciones: contrato,
`ServicioDispositivosHttp`, doble de test; 5 llamadas: `VinculadorAsiento` y
cuatro tests). Un rename de parámetro con nombre es atómico: dejar la
declaración y una implementación en desacuerdo no compila.

### Seats cableados (cierra el diferido de §6.1)

`backend-seats` publicó `POST /devices` y `DELETE /devices/{id}` con tests, y
`flutter-sync` publicó `crearServicioDispositivos`
(`nube/servicio_dispositivos_http.dart`). `composicion.dart` ya no devuelve
`null`: construye el cliente.

`servicioDispositivosProvider` **sigue siendo nullable**, y no por inercia: sin
`syncUrlBase` la app está en modo offline puro y no hay backend contra el que
vincular. Devolver un cliente apuntando a la cadena vacía convertiría un "nunca
configuraste una URL" en un fallo de red disfrazado de problema de licencia, que
es el mensaje que §4.3 evita en el resto del módulo. `null` significa "aquí no
hay nada que llamar".

### Puerto de selección de archivos: diferido, no olvidado

El botón "Desde archivo" de la activación (importar un `.lic`/`.txt` llegado por
WhatsApp o USB-OTG) necesita un selector de archivos. `file_picker` **no** se
añade todavía:

- `flutter-licencia` ya declaró el puerto `SelectorArchivoLicencia` en
  `ui/licencia/proveedores_licencia.dart`, con un provider que vale `null` por
  defecto y una pantalla que **oculta el botón** cuando no hay implementación.
  El flujo degrada solo; no hay botón muerto.
- Las otras dos rutas de activación sin internet —pegar el token y escanearlo
  con la cámara— ya funcionan y cubren el caso.
- El puerto se queda en `pagoya_movil`, **no** en `pagoya_core`: el núcleo no
  abre archivos, solo valida el texto del token. Meterlo en `dispositivo/
  contratos.dart` habría sido puerto de UI en el núcleo, justo lo que §4.2 evita
  con la impresora y el escáner.

Se añade `file_picker` cuando alguien pida el botón. Hasta entonces es una
dependencia menos que puede romper `pub get`.

### `asn1lib`: retirado

§4 lo listaba junto a `pointycastle`, pero ningún archivo lo importa:
`license_token_validator.dart` parsea el SPKI con un lector DER propio de ~60
líneas porque los getters de asn1lib para enteros y BIT STRING cambiaron entre
la 1.0 y la 1.5, y depender de ellos ataba la verificación de licencias a una
versión concreta de un paquete de terceros. Una dependencia declarada y no
importada solo aporta superficie de fallo en `pub get` y tienta a alguien a
"arreglar" el validador para usarla.

### Archivos inertes que hay que borrar a mano

Quedaron con solo un doc comment porque ningún agente tuvo shell. **Nadie los
importa ni los exporta** (verificado por nombre de archivo y por símbolo en todo
`mobile/`), así que se borran sin tocar una línea de código:

- `packages/pagoya_core/lib/licencia/cliente_licencia_api.dart`
- `packages/pagoya_core/lib/licencia/guardia_reloj.dart`
- `pagoya_movil/lib/ui/licencia/tarjeta_upsell.dart`

### Firmas exactas que `main.dart` ya invoca

`main.dart` está reescrito contra lo que **existe**. Lo que le falta es esto:

`flutter-hardware`, en `HardwarePagoYa`: un campo
`AlmacenSeguro get almacenSeguro`, con una implementación sobre
`flutter_secure_storage` (el mismo plugin que ya usa
`IdentidadDispositivoSegura`). Es la **única** pieza que le falta al arranque
para armar el licenciamiento. No se improvisa un fallback en
`SharedPreferences`: guardar el token en claro es un bug de seguridad, no una
comodidad.

> `PuertosHardware.registrarNavigator` queda **retirado**: `EscanerCodigos`
> abre una `SesionEscaneo`, no una pantalla, así que no necesita navigator.
> `navigatorKeyRaiz` sigue en `composicion.dart` para el `GoRouter` de
> `flutter-ui`, que es para lo que sirve de verdad.

`flutter-datos`, en `pagoya_core/lib/datos/base_datos_drift.dart`, añade a
`BaseDatosPagoYa` un getter por repositorio — `productos`, `ventas`, `caja`,
`mesas`, `hotel`, `proveedores`, `usuarios`, `reportes`, `outbox`,
`configuracion` — **tipados con las interfaces de `datos/contratos.dart`**, y
publica `CatalogoPlantillasRubro crearCatalogoPlantillas();` en
`rubros/plantillas_rubro.dart`. Hoy `BaseDatosPagoYa` no expone ninguno.

`flutter-ui` publica `class AppPagoYa extends StatelessWidget` con
`const AppPagoYa({super.key})` en `pagoya_movil/lib/app.dart`; su `GoRouter` usa
`navigatorKey: navigatorKeyRaiz` y un `redirect` basado en
`gateArranqueProvider`. **`app.dart` no existe**: es el único `import` del árbol
que no resuelve.

`flutter-sync` ya publicó el cliente de seats, y `servicioDispositivosProvider`
está cableado en `composicion.dart`. Lo que **sigue pendiente** es el motor de
facturación: cuando exista, se enchufa sobreescribiendo
`fabricaMotorFacturacionProvider`, sin tocar `composicion.dart`. Mientras valga
`null`, el gate devuelve el Null Object incluso con licencia Facturador Pro, que
es el fallo seguro correcto: mejor "no disponible" que emitir mal ante SUNAT.

---

## 5. Reglas de negocio que el móvil DEBE respetar

1. **Gate de activación.** Sin token auténtico (firma válida + dispositivo
   vinculado + no vencido) la app **no entra al POS**: muestra la pantalla de
   activación. Igual que en escritorio (`CLAUDE.md`).
2. **Feature gating por flag firmado**, nunca por tier ni por bandera local.
   Flags: `invoicing`, `cloud_sync`, `multi_site`
   (`docs/LICENSE-TOKEN.md` §5). Sin el flag → objeto Null Object deshabilitado
   + tarjeta de upsell con candado.
3. **Offline primero.** Toda venta se escribe en SQLite **y** en `outbox_sync`
   dentro de la **misma transacción**, antes de cualquier intento de red. La app
   nunca se bloquea por falta de internet.
4. **Grace period de 7 días** tras `exp` antes de degradar a Base.
5. **Reloj manipulable.** En móvil el usuario cambia la fecha fácil: guarda un
   `ultimo_visto_utc` monotónico en `meta` y trata un retroceso grande del reloj
   como sospechoso (no degrades de golpe, marca el estado).
6. **Nada de firmar XML SUNAT en el teléfono.** El `.pfx` no vive en el
   dispositivo: la facturación va por el backend/PSE. `IInvoiceEngine` en móvil
   es siempre un cliente remoto.

---

## 6. Cambios de backend que el móvil necesita (dueño: `backend-seats`)

Estos tres son **bloqueantes de diseño** y por eso van en paralelo desde el día 1:

1. ~~**Seats / dispositivos.**~~ **HECHO.** `backend-seats` publicó
   `MaxDispositivos`, `POST /devices` (vincular sin tocar `HwidActual`) y
   `DELETE /devices/{id}` (revocar desde el panel), con tests. El cliente móvil
   es `ServicioDispositivosHttp` y está cableado en `composicion.dart`. Se deja
   escrito el motivo por si alguien lo revive: si el celular llamara
   `/activate` con su id, **desvincularía la PC y quemaría uno de los dos
   traslados**.
2. **Filtro de eco en el pull.** `ServicioSync.ObtenerCambiosAsync` devuelve
   *todos* los eventos con `Secuencia > cursor`, **incluidos los que envió el
   propio dispositivo**. Con una caja es inofensivo; con PC + móvil es tráfico
   duplicado y riesgo de sobrescritura. Debe excluir `OrigenCajaId == el del
   solicitante`.
3. **Entidades de sync ampliadas.** `OutboxStore.AplicarCambiosRemotosAsync`
   solo maneja `producto`, `venta`, `caja`, `movimiento_caja`, `inventario`.
   El caso de uso estrella del móvil (mozo tomando comandas) exige además
   `mesa`, `pedido`, `pedido_linea`. Hay que ampliarlo **en ambos lados**.

### Riesgo conocido: stock con LWW multi-dispositivo

Con dos cajas vendiendo a la vez, `productos.stock_actual` resuelto por
last-write-wins pierde ventas. Regla: **`stock_actual` es caché derivada**; la
verdad es la tabla `inventario` (kardex append-only). Al aplicar cambios
remotos, recalcula el stock desde el kardex en vez de sobrescribir el campo.

### Riesgo conocido: correlativos

`ventas.numero` es "correlativo legible por caja". Con el móvil como segunda
caja colisiona. Formato acordado: **`<prefijo-dispositivo>-<correlativo>`**
(ej. `M01-000123` en el móvil, `C01-000123` en la PC).

---

## 7. Onboarding por rubro (requisito de producto)

Al crear la cuenta el usuario **elige su tipo de negocio** y la app queda usable
de inmediato. Portar de `PlantillasRubro.cs`, sin cambiar claves:

`bodega` · `restaurante` · `cafeteria` · `polleria` · `farmacia` ·
`ferreteria` · `licoreria` · `hotel` · `otro`

Elegir rubro precarga: **categorías sugeridas**, **productos de ejemplo**,
**pie de ticket**, y **qué módulos aparecen**:

| Rubro | Módulos extra |
|---|---|
| `restaurante`, `cafeteria`, `polleria` | **Mesas** + comandas + personalización de productos (`PlantillasRubro.EsRubroComida`) |
| `hotel` | **Habitaciones** + estadías + consumos cargados al cuarto |
| `farmacia` | Campos DIGEMID: principio activo, registro sanitario, lote, vencimiento, receta |
| `ferreteria` | Stock mínimo y alertas de reposición |
| resto | Catálogo simple |

---

## 8. Paridad con el escritorio (obligatorio)

Cualquier cálculo que exista en C# y en Dart necesita un **fixture JSON
compartido** en `tests/fixtures/paridad/`, consumido por los tests de ambos
lados. Aplica a: cálculo de IGV y totales, redondeo de vuelto, arqueo de caja,
generación del payload del outbox y verificación del token.

Si un test de paridad falla, **el móvil se adapta al escritorio**, no al revés.

---

## 9. Estado del entorno (leer antes de asumir)

- El proyecto Flutter **aún no está creado**. `flutter create` lo corre el
  usuario (los agentes de esta sesión no tienen shell disponible).
- Los agentes escriben archivos; la compilación y `flutter pub get` los ejecuta
  el usuario y reporta los errores de vuelta. Los comandos exactos están en
  `mobile/README.md`.
- No inventes que compilaste algo. Si no lo verificaste, dilo.

### Qué está ya publicado (por `mobile-lead`)

| Archivo | Contiene |
|---|---|
| `mobile/analysis_options.yaml` + los 3 por paquete | Reglas estrictas compartidas |
| `mobile/{pagoya_movil,packages/*}/pubspec.yaml` | Dependencias cerradas (§4) |
| `pagoya_core/lib/pagoya_core.dart` | Barrel + **el mapa de qué símbolo vive dónde** tras el arbitraje |
| `pagoya_core/lib/datos/contratos.dart` | Los ocho `Repositorio*` + familia `ReporteDia` |
| `pagoya_core/lib/nube/contratos.dart` | `MotorFacturacion`, `ResultadoEmision`, `OpcionesFacturacion`, `MotorFacturacionDeshabilitado`, `ServicioDispositivos` |
| `pagoya_core/lib/configuracion/contratos.dart` | `ConfiguracionNegocio`, `AlmacenConfiguracion` |
| `pagoya_core/lib/rubros/contratos.dart` | `CatalogoPlantillasRubro`, `PlantillaRubro`, `ModuloRubro` |
| `pagoya_core/lib/{licencia,dispositivo}/contratos.dart` | Redirecciones documentadas (ver §4.2) |
| `pagoya_movil/lib/composicion.dart` | Grafo de providers + **todo** el feature-gating + `gateArranqueProvider` |
| `pagoya_movil/lib/main.dart` | Arranque en 5 pasos y los overrides del `ProviderScope` |

Nada de esto se ha compilado ni analizado. Tras la pasada final (§4.3), los
símbolos que **todavía no existen** y contra los que hay código escrito son:
`app.dart` / `AppPagoYa`, `HardwarePagoYa.almacenSeguro`, los getters de
repositorio de `BaseDatosPagoYa` y `crearCatalogoPlantillas()`. Son el contrato
que cada agente debe cumplir, no un error a "arreglar" borrando el import.

**Aviso para `flutter-licencia`:** `servicio_licencia.dart` usa `@override` en
`desactivar` y `tieneCaracteristica`, pero `ServicioLicencia` se declara sin
`implements`. Eso es `override_on_non_overriding_member`, que en Dart es error,
no warning. O se le pone la interfaz o se quitan las anotaciones.
