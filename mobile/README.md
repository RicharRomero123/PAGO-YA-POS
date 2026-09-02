# PagoYa Móvil — puesta en marcha

> **Estado: esqueleto escrito a mano, sin compilar.** Los agentes de esta sesión
> no tienen shell disponible, así que nadie corrió `flutter create`, `flutter
> pub get` ni `flutter analyze`. Los archivos están escritos según
> `docs/MOBILE-ARQUITECTURA.md`; **la primera compilación la haces tú** y
> reportas los errores de vuelta.

La arquitectura, el mapa de propiedad de archivos y las decisiones cerradas
están en `docs/MOBILE-ARQUITECTURA.md`. Este README es solo la receta de
comandos.

---

## 1. Requisitos

| Herramienta | Versión |
|---|---|
| Flutter SDK | ≥ 3.24 (canal stable) |
| Dart | ≥ 3.5 (viene con Flutter) |
| Android Studio o Android SDK | API 34+, con `cmdline-tools` |
| Java | JDK 17 (el que trae Android Studio) |

Comprueba que todo esté en orden antes de empezar:

```powershell
flutter --version
flutter doctor
```

`flutter doctor` debe salir sin cruces rojas en **Flutter** y **Android
toolchain**. Lo de Chrome y Visual Studio da igual: el objetivo es Android
(decisión §4: Android primero, iOS después).

---

## 2. Generar las plataformas nativas

Las carpetas `android/` e `ios/` **no están en el repo**: las genera Flutter.
El truco es correr `flutter create` **sobre la carpeta que ya existe**, con un
punto como destino: eso conserva `lib/`, `pubspec.yaml` y
`analysis_options.yaml` y solo añade lo que falta.

```powershell
cd C:\Users\otin174\Documents\PagaloYa\PAGO-YA-POS\mobile\pagoya_movil
flutter create --platforms=android,ios --org pe.pagoya --project-name pagoya_movil .
```

> ⚠️ **El punto final es obligatorio.** Sin él, Flutter crea un proyecto nuevo
> en un subdirectorio y no sirve de nada.
>
> ⚠️ `--org pe.pagoya` fija el application id en `pe.pagoya.pagoya_movil`.
> **Cámbialo ahora o nunca**: una vez publicado en Play Store no se puede
> modificar.

Si Flutter avisa de que va a sobrescribir `pubspec.yaml` o `main.dart`,
**responde que no** (o restáuralos con `git checkout` después): los nuestros
llevan las dependencias y el composition root.

---

## 3. Crear la carpeta de assets

`pubspec.yaml` declara `assets/iconos/`. Si la carpeta no existe,
`flutter pub get` **falla**. Créala y copia los PNG del escritorio — son
literalmente los mismos archivos (MOBILE-ARQUITECTURA §1):

```powershell
cd C:\Users\otin174\Documents\PagaloYa\PAGO-YA-POS\mobile\pagoya_movil
New-Item -ItemType Directory -Force assets\iconos
Copy-Item ..\..\src\PagoYa.Desktop\Assets\Iconos\*.png assets\iconos\
```

Si esa carpeta de iconos todavía no existe en el escritorio, deja el directorio
vacío con un marcador para que `pub get` no proteste:

```powershell
New-Item -ItemType File assets\iconos\.gitkeep
```

---

## 4. Resolver dependencias

Son tres paquetes y cada uno resuelve por su cuenta. El orden importa: los
paquetes de `packages/` primero, porque la app los referencia por `path:`.

```powershell
cd C:\Users\otin174\Documents\PagaloYa\PAGO-YA-POS\mobile\packages\pagoya_core
flutter pub get

cd ..\pagoya_hardware
flutter pub get

cd ..\..\pagoya_movil
flutter pub get
```

> Las versiones del `pubspec.yaml` están fijadas con rango amplio (`^`) a partir
> de las últimas estables conocidas, **sin haberlas verificado contra pub.dev**
> (no hay red aquí). Si `pub get` se queja de una versión inexistente o de un
> conflicto, **no edites el pubspec por tu cuenta**: pásale el error a
> `mobile-lead`, que es el único que toca dependencias (§3).

---

## 5. Generar el código de drift — **no hace falta**

`flutter-datos` implementó la capa de datos **sin code-gen**: `BaseDatosPagoYa`
extiende `GeneratedDatabase` con `allTables` vacío y ejecuta el esquema literal
con `customStatement`, que es justo lo que exige la decisión de §4 ("paridad
literal de esquema con la PC"). No hay ningún `part '…g.dart'`, así que **no
corras `build_runner`**.

`drift_dev` y `build_runner` siguen en `dev_dependencies` por si algún día se
generan tablas; hasta entonces son peso muerto y se pueden ignorar.

---

## 6. Analizar y ejecutar

```powershell
cd C:\Users\otin174\Documents\PagaloYa\PAGO-YA-POS\mobile\pagoya_movil
flutter analyze
flutter run -d <id-del-dispositivo>
```

Lista los dispositivos conectados con `flutter devices`. Para el APK de prueba:

```powershell
flutter build apk --release
```

---

## 7. Borra estos tres archivos antes de nada

Quedaron con **solo un doc comment** (los agentes no tenían shell para
borrarlos). Nadie los importa ni los exporta — verificado por nombre de archivo
y por símbolo en todo `mobile/` — así que se van sin tocar código:

```powershell
cd C:\Users\otin174\Documents\PagaloYa\PAGO-YA-POS\mobile
Remove-Item packages\pagoya_core\lib\licencia\cliente_licencia_api.dart
Remove-Item packages\pagoya_core\lib\licencia\guardia_reloj.dart
Remove-Item pagoya_movil\lib\ui\licencia\tarjeta_upsell.dart
```

---

## 8. Qué va a fallar en la primera pasada, en orden

Siete agentes trabajaron en paralelo y **nadie compiló nada**. `mobile-lead`
recorrió el árbol archivo por archivo en la pasada final de reconciliación
(`docs/MOBILE-ARQUITECTURA.md` **§4.3**) y arregló lo que era suyo. Esto es lo
que queda, ordenado por lo pronto que te va a morder.

### A. `flutter pub get`

1. **`assets/iconos/` no existe** → `pub get` falla en `pagoya_movil`. Es el
   paso 3 de este README; hazlo antes.
2. **Versiones sin verificar contra pub.dev.** Ninguna se comprobó (no había
   red). Las de mayor riesgo: `workmanager: ^0.5.2` (lleva tiempo sin release y
   es la única con restricción `^0` — un cambio de minor rompe), `drift ^2.23.1`
   + `drift_dev` + `sqlite3_flutter_libs ^0.5.26` (tienen que casar entre sí), y
   `intl ^0.19.0`, que suele chocar con el `intl` que fija el SDK de Flutter.
   Si algo falla, **pásame el error**: nadie más toca dependencias (§3).

### B. `flutter analyze` — errores de compilación reales

Por orden de cuántos archivos tumba cada uno:

| # | Error | Dueño | Qué hay que hacer |
|---|---|---|---|
| 1 | `ambiguous_export: TierLicencia` en el barril | `flutter-datos` | Borrar `enum TierLicencia` de `dominio/enums.dart` (líneas ~305-317). **Ya está parcheado** con un `hide` en `pagoya_core.dart` para que el paquete compile; al borrarlo, quita el `hide`. Nadie usa ese enum. |
| 2 | `uri_does_not_exist: 'app.dart'` en `main.dart:32` | `flutter-ui` | Es el **único** import del árbol que no resuelve. Falta `AppPagoYa`. |
| 3 | `BaseDatosPagoYa` no tiene los getters de repositorio | `flutter-datos` | `composicion.dart` y `main.dart` usan `.productos`, `.ventas`, `.caja`, `.mesas`, `.hotel`, `.proveedores`, `.usuarios`, `.reportes`, `.outbox`, `.configuracion`. Hoy la clase solo declara `allTables`, `schemaVersion` e `inicializarEsquema`. |
| 4 | `HardwarePagoYa.almacenSeguro` no existe | `flutter-hardware` | Única pieza que le falta al arranque: una clase que implemente `AlmacenSeguro` sobre `flutter_secure_storage`. Sin ella no se puede guardar el token. |
| 5 | `crearCatalogoPlantillas()` no existe | `flutter-datos` | En `rubros/plantillas_rubro.dart`. Debe devolver la interfaz `CatalogoPlantillasRubro` de `rubros/contratos.dart`. |
| 6 | `OutboxStore` no encaja en `FabricaSync.crear(outbox:)` | `flutter-datos` | Falta `implements AlmacenOutbox`, más `contarDeadLetter()`, `reencolarDeadLetter()` y que `registrarFallo` devuelva `Future<int>`. |
| 7 | Tres símbolos duplicados en `pagoya_core` | `flutter-datos` | `EventoSyncLocal`, `CambioRemoto` y `EntidadesSync` están en `datos/outbox.dart` **y** en `nube/contratos_sync.dart`. Hoy no chocan porque el barril no exporta `datos/datos.dart`; chocan en cuanto alguien importe los dos barriles. Veredicto y receta (extensiones, sin perder nada) en §4.3. |
| 8 | `override_on_non_overriding_member` en `servicio_licencia.dart` | `flutter-licencia` | `@override` en `desactivar` y `tieneCaracteristica` sobre una clase sin `implements`. En Dart es error, no warning. |
| 9 | Ningún `Repositorio*` está implementado como tal | `flutter-datos` | Las clases de `datos/repositorios/` no declaran `implements`. Además faltan del todo: `RepositorioReportes` (no hay archivo), `AlmacenConfiguracion`, `listarCategorias`, `siguienteNumero` y los cinco `Stream` de observación. Marcados uno a uno como `PENDIENTE` en `datos/contratos.dart`. |

### C. Lo que NO es un error aunque lo parezca

- El `hide TierLicencia` de `pagoya_core.dart`: es un parche de arbitraje
  deliberado, con su explicación al lado.
- Los `_faltaOverride` de `composicion.dart`: lanzan a propósito, para que un
  override olvidado se vea en el arranque y no en producción.
- Los `throw UnimplementedError` de `ui/nube/proveedores_nube.dart`: los
  sobreescribe `main.dart`, y ya lo hace.
- Que `servicioDispositivosProvider` devuelva `null`: solo pasa **sin**
  `syncUrlBase`, o sea en modo offline puro, donde no hay backend contra el que
  vincular. Con URL configurada construye el cliente HTTP de seats.
- Que `fabricaMotorFacturacionProvider` valga `null`: el motor de facturación es
  lo único de `flutter-sync` que falta. Hasta que exista, la facturación
  responde "no disponible" incluso con licencia Facturador Pro — es el fallo
  seguro: mejor eso que emitir mal ante SUNAT.

Ya están escritos y completos: el dominio (`Dinero`, entidades, enums, cálculo
de IGV con sus tests de paridad), la capa drift (`BaseDatosPagoYa`, `Esquema`,
`OutboxStore`, seis repositorios), el licenciamiento entero (validador RSA,
`ServicioLicencia`, revalidador, vinculador de asiento, reloj auditado), el
motor de sync con su transporte HTTP y su planificador, el paquete de hardware
(impresión ESC/POS, escáner, identidad, compartir) y el sistema de diseño.

> **Ojo:** varios contratos se escribieron **por duplicado** durante la sesión
> en paralelo. `mobile-lead` arbitró cuál gana; las tablas de decisiones están
> en `docs/MOBILE-ARQUITECTURA.md` **§4.2** y **§4.3**. Léelas antes de
> "arreglar" un import que parezca roto o de borrar un símbolo que parezca
> muerto.

---

## 9. Permisos nativos (los pone `flutter-hardware`)

Tras el `flutter create`, los manifiestos quedan vírgenes. `flutter-hardware`
debe añadir en `android/app/src/main/AndroidManifest.xml`:

- `android.permission.CAMERA` — escáner de códigos.
- `android.permission.BLUETOOTH_CONNECT` y `BLUETOOTH_SCAN` (API 31+),
  más los antiguos `BLUETOOTH` / `BLUETOOTH_ADMIN` con `maxSdkVersion="30"`.
- `android.permission.INTERNET` — sync y facturación.

Y en `ios/Runner/Info.plist`: `NSCameraUsageDescription` y
`NSBluetoothAlwaysUsageDescription`. **Sin el texto de justificación, Apple
rechaza el binario en revisión** — no es opcional.

---

## 10. Estructura

```
mobile/
├─ analysis_options.yaml          # reglas estrictas compartidas (mobile-lead)
├─ README.md                      # este archivo
├─ pagoya_movil/                  # la app Flutter
│  ├─ lib/main.dart               # arranque + overrides   (mobile-lead)
│  ├─ lib/composicion.dart        # grafo + feature-gating (mobile-lead)
│  ├─ lib/app.dart                # MaterialApp + router   (flutter-ui)
│  └─ lib/ui/…                    # pantallas
└─ packages/
   ├─ pagoya_core/                # Dart PURO, sin Flutter
   │  └─ lib/*/contratos.dart     # los puertos            (mobile-lead)
   └─ pagoya_hardware/            # Bluetooth, cámara, Keystore
```
