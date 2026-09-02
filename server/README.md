# PagoYa — Licensing Backend (`server/PagoYa.Api`)

Microservicio de **licenciamiento** de PagoYa: emite, activa, valida y renueva
licencias firmando tokens **RSA-2048** que el cliente de escritorio valida
**offline**. ASP.NET Core 8 Minimal API + EF Core (SQLite en dev).

> ⚠ **Este proyecto NUNCA se entrega al cliente.** Vive en la carpeta hermana
> `server/`, fuera de `src/`. La **clave privada RSA vive solo aquí**; el cliente
> únicamente embebe la **clave pública** (`src/PagoYa.Licensing/ClavePublicaEmbebida.cs`).

---

## 1. Seguridad de la clave privada (LEER PRIMERO)

- La clave **privada** RSA firma los tokens. Si se filtra, cualquiera puede emitir
  licencias válidas. **Nunca** se versiona, **nunca** se registra en logs.
- En **dev** vive en `appsettings.Development.json` bajo `Firma:PrivateKeyPem`
  (ese archivo está en `.gitignore`) o en un `.pem` fuera de git referenciado por
  `Firma:PrivateKeyPath`. La opción recomendada es **user-secrets**.
- La clave **pública** embebida en el cliente y la privada de este server forman un
  par de **DESARROLLO**. En **producción** se genera un par nuevo (KMS/HSM) y se
  reemplaza la pública del cliente.

`.gitignore` ya excluye: `appsettings.Development.json`, `server/**/keys/`,
`*_private*.pem`, `server/**/*.db*`.

---

## 2. Cómo correr la API

```bash
# desde la raíz del repo
dotnet run --project server/PagoYa.Api
# Escucha en http://localhost:5080 (perfil "http" de launchSettings)
# Swagger UI (solo Development): http://localhost:5080/swagger
```

El esquema SQLite se crea solo al arrancar (`EnsureCreated`) en
`server/PagoYa.Api/pagoya-licencias.db`.

> Nota de entorno: si tu máquina solo tiene runtime .NET preview (p.ej. net10),
> ejecuta con `DOTNET_ROLL_FORWARD=LatestMajor dotnet run --project server/PagoYa.Api`.
> El aviso `NETSDK1057` (SDK preview) es esperado.

### Configuración mínima

`appsettings.Development.json` (gitignored) ya trae valores de dev:

| Clave                 | Uso |
|-----------------------|-----|
| `Firma:PrivateKeyPem` | Clave privada RSA-2048 (PKCS#8 PEM). |
| `Admin:ApiKey`        | API key para endpoints admin/emisión (`dev-admin-key-cambia-esto`). |
| `Webhook:HmacSecret`  | Secreto HMAC del proveedor de pago. Vacío = se omite verificación (solo dev). |
| `ConnectionStrings:Licencias` | Cadena SQLite. |

---

## 3. Generar un par de claves

```bash
# Genera pagoya_private_dev.pem + pagoya_public_dev.pem e imprime instrucciones
dotnet run --project server/PagoYa.Api -- gen-keys ./server/PagoYa.Api/keys

# Guardar la privada como user-secret (recomendado, fuera de appsettings):
cd server/PagoYa.Api
dotnet user-secrets set "Firma:PrivateKeyPath" "C:\\ruta\\keys\\pagoya_private_dev.pem"
```

Luego copia la **clave pública** impresa dentro de
`src/PagoYa.Licensing/ClavePublicaEmbebida.cs` (constante `PemPublicKey`).
Al rotar, embebe pública vieja + nueva durante la transición.

---

## 4. Endpoints

Base URL dev: `http://localhost:5080`. Los ejemplos usan `curl`.
Cabecera admin: `X-Admin-ApiKey: dev-admin-key-cambia-esto`.

### `POST /licenses` — emisión manual (admin)

Crea una licencia (venta por WhatsApp/Facebook). Protegido con API key admin.

Request:
```json
{
  "tier": "facturador",
  "features": ["invoicing", "cloud_sync", "multi_site"],
  "ruc": "20512345678",
  "hwid": null,
  "diasVigencia": 30,
  "canalVenta": "whatsapp",
  "maxTraslados": 2,
  "maxDispositivos": 5,
  "notas": "Venta FB Ads"
}
```
- `tier`: `base` | `cloud` | `facturador`.
- `maxDispositivos`: cupo de dispositivos activos (principal + secundarios).
  Si se omite, el default del tier: base 1, cloud 3, facturador 5 (ver §6).
- `features`: opcional; si se omite se usan los defaults del tier
  (`base`=[], `cloud`=`cloud_sync,multi_site`, `facturador`=+`invoicing`).
- `hwid`: opcional; pre-vincula el equipo en la emisión.
- `diasVigencia`: solo suscripciones (`base` es perpetua, `exp=0`).

```bash
curl -X POST http://localhost:5080/licenses \
  -H "X-Admin-ApiKey: dev-admin-key-cambia-esto" \
  -H "Content-Type: application/json" \
  -d '{"tier":"facturador","ruc":"20512345678","diasVigencia":30,"canalVenta":"whatsapp"}'
```

Response `201`:
```json
{
  "licenciaId": "a59c4d73-34cc-42eb-90fd-65a92c8a00c1",
  "claveLicencia": "PAGOYA-S4WN-QGC5-TPYN-NY6S",
  "tier": "facturador",
  "features": ["cloud_sync","multi_site","invoicing"],
  "expUnix": 1790050599,
  "estado": "Emitida"
}
```
La `claveLicencia` es lo que el vendedor entrega al cliente.

### `POST /activate` — vincular HWID y obtener token firmado

El cliente envía su clave + el HWID del equipo. Vincula el HWID si está libre
(o aplica política de traslado) y devuelve el **token firmado**.

```bash
curl -X POST http://localhost:5080/activate \
  -H "Content-Type: application/json" \
  -d '{"licenseKey":"PAGOYA-S4WN-QGC5-TPYN-NY6S","hwid":"ABC123"}'
```

Response `200`:
```json
{
  "token": "eyJsaWNlbnNlX2lkIjoi...QUFB.Rk9PQkFS...",
  "tier": "facturador",
  "features": ["cloud_sync","multi_site","invoicing"],
  "expUnix": 1790050599,
  "esPerpetua": false
}
```
El `token` tiene el formato `base64url(payload_json).base64url(firma_rsa)` de
`docs/LICENSE-TOKEN.md`. El cliente lo persiste con `ILicenseStore.GuardarToken`.

Errores: `404` clave no encontrada, `409` licencia suspendida/revocada o
límite de traslados alcanzado.

### `POST /validate` — revalidación / renovación silenciosa

Mismo body que `/activate`. Devuelve un token fresco (nuevo `iat`, y `exp`
actualizado según la suscripción). El HWID debe **coincidir** con el vinculado
(no traslada; para trasladar usar `/activate`). Coherente con el **grace period
de 7 días** del cliente: revalida silenciosamente antes de expirar.

```bash
curl -X POST http://localhost:5080/validate \
  -H "Content-Type: application/json" \
  -d '{"licenseKey":"PAGOYA-S4WN-QGC5-TPYN-NY6S","hwid":"ABC123"}'
```

### `POST /devices` — vincular un dispositivo secundario (asiento / seat)

Vincula un **segundo dispositivo** (típicamente el móvil del mozo) a una licencia
ya vendida. Es la alternativa a `/activate` para todo lo que no sea la caja
principal:

|                          | `/activate` | `/devices` |
|--------------------------|-------------|------------|
| Toca `HwidActual`        | **Sí**      | No |
| Consume `MaxTraslados`   | Sí (traslado) | **No** |
| Consume `MaxDispositivos`| No (el principal siempre entra) | **Sí** |
| Claim `hwid` del token   | HWID de la PC | Id del dispositivo secundario |

> Si el móvil llamara a `/activate`, **desvincularía la PC del cliente y le quemaría
> un cupo de traslado**. Por eso existe este endpoint.

Rate limiting: la misma política estricta que `/activate` (10 req/min por IP).

Request:
```json
{
  "licenseKey": "PAGOYA-S4WN-QGC5-TPYN-NY6S",
  "deviceId": "android-id-9f3a...",
  "nombre": "Celular de Juan",
  "plataforma": "android"
}
```
- `deviceId`: id **estable** del dispositivo (Android ID / `identifierForVendor` /
  HWID). Se firma en el claim `hwid`, así que el cliente debe poder recalcularlo
  idéntico en cada arranque o dejará de validar.
- `plataforma`: `android` | `ios` | `windows`. Decide la familia del prefijo (M/C).

```bash
curl -X POST http://localhost:5080/devices \
  -H "Content-Type: application/json" \
  -d '{"licenseKey":"PAGOYA-S4WN-QGC5-TPYN-NY6S","deviceId":"android-id-9f3a","plataforma":"android","nombre":"Celular de Juan"}'
```

Response `201`:
```json
{
  "token": "eyJsaWNlbnNlX2lkIjoi...QUFB.Rk9PQkFS...",
  "tier": "cloud",
  "features": ["cloud_sync","multi_site"],
  "expUnix": 1790050599,
  "esPerpetua": false,
  "deviceId": "6f1c2f7a-9b21-4a0e-9d6e-9a2b7f0c1d33",
  "devicePrefix": "M01"
}
```
- `deviceId` (respuesta): id del **asiento**, el `{id}` de `DELETE /devices/{id}`.
- `devicePrefix`: prefijo asignado por el server (ver §6.2).

Re-vincular el **mismo** `deviceId` es idempotente: re-emite el token sin consumir
otro cupo (así el móvil puede renovar su token tras un cambio de plan).

Errores: `404` `clave_no_encontrada` · `409` `licencia_suspendida` /
`licencia_revocada` / `cupo_dispositivos_lleno` / `dispositivo_ya_es_principal`
(use `/activate`). Ramifique por el campo `codigo`, no por el texto — ver §10.

### `DELETE /devices/{id}` — revocar un asiento

Libera el cupo del asiento. Lo puede hacer **un admin** (API key o sesión del panel)
**o el dueño de la licencia** presentando su clave en la cabecera `X-License-Key`
(no en la query: las URLs terminan en logs y proxies).

```bash
# como dueño de la licencia
curl -X DELETE http://localhost:5080/devices/6f1c2f7a-9b21-4a0e-9d6e-9a2b7f0c1d33 \
  -H "X-License-Key: PAGOYA-S4WN-QGC5-TPYN-NY6S"

# como admin
curl -X DELETE http://localhost:5080/devices/6f1c2f7a-... \
  -H "X-Admin-ApiKey: dev-admin-key-cambia-esto"
```

Response `200`: `{ "deviceId": "...", "revocado": true, "dispositivosActivos": 1, "maxDispositivos": 3 }`.

Errores: `401` `credenciales_requeridas` · `403` `clave_no_corresponde` ·
`404` `dispositivo_no_encontrado` · `409` `principal_no_revocable` (para eso está el
traslado de `/activate` o la suspensión admin).

> **Alcance real de la revocación.** El cliente valida su token **offline**: un token
> ya emitido sigue siendo criptográficamente válido en el dispositivo hasta su `exp`.
> Lo que la revocación corta de inmediato es (a) la re-emisión de tokens para ese
> asiento y (b) el acceso a `/sync/push` y `/sync/pull`, que responden `403` cuando el
> `device_id` del token ya no está activo. Para una licencia perpetua (Base) el corte
> total requiere suspender la licencia.

### `POST /sync/push` y `GET /sync/pull` — sincronización en la nube

Autenticados con el **token de licencia** (`Authorization: Bearer <token>`); el
tenant sale del claim `license_id` y se exige el flag `cloud_sync`.

```bash
curl "http://localhost:5080/sync/pull?cursor=120&origen=M01" \
  -H "Authorization: Bearer <token>"
```

| Parámetro | Endpoint | Descripción |
|---|---|---|
| `cursor`  | pull | Última `Secuencia` aplicada. Vacío = desde el principio. |
| `origen`  | pull | `origen_caja_id` del dispositivo que consulta: **sus propios eventos no se le devuelven** (filtro de eco, §7). Si se omite, el server usa el claim `device_prefix` del token; si tampoco está, no filtra (compatibilidad). |

Los dos `403` posibles se distinguen por el campo `codigo` de la respuesta —
`sin_flag_cloud_sync` (upsell al tier Cloud) vs `asiento_revocado` (re-vincular
este equipo). **Nunca los distinga por el texto del mensaje**: ver §10.

`POST /sync/push` responde `{ "aceptados": [...], "entidadesDesconocidas": [] }`.
`entidadesDesconocidas` lista los nombres de entidad fuera del catálogo (§7.2):
los eventos **se almacenan igual** —el server nunca descarta datos del cliente—
pero se reportan para detectar desalineación de contrato entre PC, móvil y backend.

### `POST /webhooks/payment` — confirmación de pago (pasarela)

Activa/renueva la suscripción (Cloud/Facturador). **Idempotente** por `eventId`
y con verificación de **firma HMAC** (si `Webhook:HmacSecret` está configurado,
cabecera `X-PagoYa-Signature: sha256=<hex|base64>` sobre el cuerpo crudo).

```bash
curl -X POST http://localhost:5080/webhooks/payment \
  -H "Content-Type: application/json" \
  -H "X-PagoYa-Signature: sha256=<firma_hmac_del_proveedor>" \
  -d '{"eventId":"evt_777","type":"subscription.renewed","licenseKey":"PAGOYA-S4WN-QGC5-TPYN-NY6S","dias":30,"monto":50,"moneda":"PEN"}'
```

Response `200`: resumen de la licencia con el `expUnix` extendido. Reenviar el
mismo `eventId` no vuelve a extender (idempotencia).

### Endpoints admin (requieren `X-Admin-ApiKey`)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET`  | `/admin/licenses?estado=Activa&limite=100` | Listar licencias. |
| `GET`  | `/admin/licenses/{id}` | Detalle de una licencia. |
| `POST` | `/admin/licenses/{id}/suspend?motivo=...` | Suspender (bloquea activación/validación). |
| `POST` | `/admin/licenses/{id}/reactivate` | Reactivar. |

```bash
curl "http://localhost:5080/admin/licenses?limite=50" -H "X-Admin-ApiKey: dev-admin-key-cambia-esto"
curl -X POST "http://localhost:5080/admin/licenses/<ID>/suspend?motivo=impago" -H "X-Admin-ApiKey: dev-admin-key-cambia-esto"
```

---

## 5. Emisión y validación de un token de punta a punta

1. `POST /licenses` crea la `Licencia` (tier, features, `exp`) → `claveLicencia`.
2. El cliente llama `POST /activate` con `claveLicencia` + `hwid`.
3. El server vincula el HWID y **firma** el payload con la privada RSA-2048
   (`EmisorTokens`, `RSASSA-PKCS1-v1_5 + SHA-256` sobre los bytes UTF-8 del JSON),
   produciendo `base64url(payload).base64url(firma)`.
4. El cliente (`PagoYa.Licensing.LicenseTokenValidator`) verifica la firma contra
   la **clave pública embebida**, chequea HWID y expiración con grace period, y
   habilita los `features`. Si algo falla → modo **Base** seguro.

La compatibilidad exacta está verificada: un token emitido por este server valida
en el `LicenseTokenValidator` del cliente (y uno manipulado se rechaza).

---

## 6. Política de HWID y de dispositivos (seats)

### 6.1 Los dos roles de dispositivo

| Rol | Se vincula con | Campo que manda | Límite |
|---|---|---|---|
| **Principal** (la caja) | `POST /activate` | `Licencia.HwidActual` | 1 activo; cambiarlo consume `MaxTraslados` |
| **Secundario** (móvil) | `POST /devices` | fila en `Devices` con `Tipo=Secundario` | cupo de `MaxDispositivos` |

Política del **principal** (sin cambios respecto de antes):

- Una licencia = **un equipo activo** (`HwidActual`). Los HWID previos quedan como
  histórico en `Devices` (`Activo=false`, `DesvinculadoUtc`).
- **Reactivar en el mismo equipo** no consume cupo.
- **Trasladar a otro equipo** consume un cupo hasta `MaxTraslados` (default **2**).
  Superado el límite → `409` que exige **aprobación manual** de soporte
  (subir `MaxTraslados` o reactivar vía admin).
- `/validate` no traslada: si el HWID no coincide, responde `409`.
- Un traslado desvincula **solo la PC anterior**: los asientos móviles siguen vivos.

Política de **asientos** (`MaxDispositivos`):

- Cuenta **todos los dispositivos activos**, principal incluido. Defaults por tier:

  | Tier | `MaxDispositivos` | En la práctica |
  |---|---|---|
  | `base` | **1** | solo la caja; sin móvil |
  | `cloud` | **3** | la caja + 2 móviles |
  | `facturador` | **5** | la caja + 4 móviles |

  Se puede fijar por licencia con `maxDispositivos` en `POST /licenses`.
- **`MaxDispositivos = 0` significa "sin definir"** y se resuelve con el default del
  tier. Es la ruta de compatibilidad: las licencias emitidas antes de los seats
  traen 0 en la columna nueva y siguen funcionando sin migración de datos.
- `/activate` **nunca** falla por `MaxDispositivos`: el equipo principal siempre
  entra (romper la activación del escritorio no es negociable). El cupo solo se
  verifica al vincular secundarios.
- Re-vincular un `deviceId` ya activo es idempotente y no consume otro cupo.
- Revocar libera el cupo; volver a vincular ese mismo dispositivo lo reactiva
  **conservando su prefijo**.
- Todo queda auditado en `ActivationLogs` (`emision`, `activacion`, `traslado`,
  `validacion`, `rechazo`, `pago`, `suspension`, `reactivacion`,
  **`vinculo_dispositivo`**, **`revocacion_dispositivo`**, con IP y detalle).
- `GET /admin/licenses/{id}` devuelve la lista de dispositivos
  (`id`, `hwid`, `tipo`, `nombre`, `plataforma`, `prefijo`, `activo`, fechas) y
  `GET /admin/licenses` el consumo `dispositivosActivos` / `maxDispositivos`.

### 6.2 Prefijo de dispositivo y correlativos `<prefijo>-<correlativo>`

`ventas.numero` es un correlativo **por caja**: con una segunda caja (el móvil)
colisiona. Formato acordado con el equipo móvil:

```
<prefijo-dispositivo>-<correlativo>     C01-000123   (PC)
                                        M01-000123   (móvil)
```

**Quién asigna el prefijo: el SERVER**, al vincular el dispositivo. Es el único que
ve todos los dispositivos de la licencia y puede garantizar unicidad; que lo
eligiera el cliente reabriría exactamente la colisión que el formato viene a cerrar.

- Familia por plataforma: `C01..C99` para escritorio, `M01..M99` para móvil.
- Se asigna el menor número libre **dentro de la licencia**.
- Los prefijos de asientos revocados **no se reutilizan**: sus correlativos ya
  están impresos en los tickets del negocio.
- Viaja en la respuesta (`devicePrefix`) y en el claim `device_prefix` del token.
- El cliente lo usa para dos cosas: el prefijo del correlativo y el valor de
  `origen_caja_id` (§7.1).
- Las instalaciones antiguas que ya tienen su propio `origen_caja_id` lo conservan;
  el prefijo del token es **advisory** hasta que el cliente lo adopte.

---

## 7. Sincronización multi-dispositivo

### 7.1 Filtro de eco en el pull

`GET /sync/pull` devolvía **todos** los eventos con `Secuencia > cursor`, incluidos
los que había subido el propio solicitante. Con una sola caja era inofensivo (LWW
idempotente); con PC + móvil es tráfico duplicado y riesgo de que un snapshot viejo
pise uno más nuevo. Ahora el server excluye los eventos cuyo `OrigenCajaId` sea el
del dispositivo que consulta.

**Cómo identifica el cliente su origen** (en este orden):

1. Parámetro explícito `?origen=<origen_caja_id>` — es la vía recomendada y la
   única disponible para el escritorio, cuyos tokens en campo no traen claims de
   dispositivo.
2. Claim `device_prefix` del token, si el parámetro no viene (móvil).
3. Si no hay ninguno → **no se filtra**, exactamente como antes (compatibilidad).

Contrato: `origen_caja_id` es una cadena **opaca, estable y única por dispositivo**
dentro de la licencia; el server solo la compara (sin distinguir mayúsculas). El
valor recomendado es el prefijo asignado por el server (`C01`, `M01`). **El cliente
debe enviar en `?origen=` exactamente el mismo valor que estampa en los eventos que
sube**, o el filtro no sirve de nada.

El cursor avanza sobre la ventana **sin filtrar**: los eventos propios se saltan
definitivamente en vez de re-escanearse en cada pull. Por eso una página puede
devolver menos de 500 cambios —o ninguno— y aun así mover el cursor hacia adelante.

**Cursor adelantado (auto-reparación).** Si el cliente manda un cursor mayor que la
secuencia máxima de su licencia —BD corrupta, restauración de un backup, cursor de
otro tenant—, el server responde con el **máximo real**, no con el valor recibido.
Antes se devolvía tal cual y ese dispositivo quedaba clavado en un cursor
inalcanzable **para siempre**, sin poder repararse solo. Acotar no es reiniciar: no
se re-entrega el histórico, solo se destraba el futuro. Un cursor no numérico,
vacío o negativo se trata como `0`.

### 7.2 Catálogo de entidades sincronizadas

Nombres canónicos (snake_case, singular) que deben usar **idénticos** el POS de
escritorio (`src/PagoYa.Data/Repositorios/OutboxStore.cs`), el móvil
(`mobile/packages/pagoya_core/lib/datos/`) y este backend
(clase `EntidadesSync` en `server/PagoYa.Api/Servicios/ServicioSync.cs`):

| Entidad | Origen |
|---|---|
| `producto`, `venta`, `caja`, `movimiento_caja`, `inventario` | las cinco originales del escritorio |
| `mesa`, `pedido`, `pedido_linea` | **comandas** — el caso de uso estrella del móvil |
| `habitacion`, `estadia_habitacion` | rubro hotel (el escritorio ya las emitía al outbox) |

El server **no descarta** eventos de entidades fuera del catálogo: perder datos del
cliente sería peor que aceptarlos. Los almacena igual y los reporta en
`SyncPushResponse.entidadesDesconocidas`.

### 7.3 Stock: el kardex manda, `stock_actual` es caché

Con dos cajas vendiendo a la vez, `productos.stock_actual` resuelto por
last-write-wins **pierde ventas**. La regla del sistema es que la verdad es la tabla
`inventario` (kardex append-only) y `stock_actual` es una caché derivada. El server
consolida en consecuencia: los eventos de `inventario` son **inmutables y
acumulativos** (nunca se colapsan por LWW; cada movimiento entra una sola vez por su
id de evento), y quien aplica los cambios recalcula el stock desde el kardex en vez
de sobrescribir el campo. Un evento de `producto` que traiga `stock_actual` es
informativo, no autoritativo.

---

## 8. Persistencia (EF Core + SQLite)

Tablas: `Licenses`, `Devices`, `Subscriptions`, `PaymentEvents`, `ActivationLogs`,
`SyncEvents`, `AdminUsers`, `AdminSessions`.
Se crean con `EnsureCreated` al arrancar (dev). Para prod, migrar a
SQL Server/PostgreSQL y usar migraciones EF (`dotnet ef migrations add Inicial`).

> ⚠ **`EnsureCreated` no altera tablas existentes.** Las columnas del modelo de
> seats (`Licenses.MaxDispositivos`; `Devices.Tipo`, `Nombre`, `Plataforma`,
> `Prefijo`, `UltimoVistoUtc`) no aparecen solas en una BD de dev previa: borre el
> `.db` de desarrollo o aplique una migración. Los defaults elegidos hacen que los
> datos existentes sigan siendo válidos (`MaxDispositivos=0` → default del tier,
> `Tipo=0` → Principal, `Prefijo=''` → se asigna en la siguiente activación).

---

## 9. Seguridad operativa incluida

- **Rate limiting** por IP: global 60 req/min; `/activate`, `/validate`, `/devices`
  y `DELETE /devices/{id}` 10 req/min (anti fuerza bruta de claves).
- **API key admin** en emisión y endpoints admin (comparación en tiempo constante).
- **HMAC** en el webhook + **idempotencia** por `eventId`.
- **Revocación de asientos aplicada online:** `/sync/*` responde `403` si el
  `device_id` del token ya no está activo.
- La clave de licencia de `DELETE /devices/{id}` viaja por cabecera
  (`X-License-Key`), nunca en la query string.
- Validación de entrada en DTOs; dominio en español; nullable habilitado; async.

---

## 10. Códigos de error (contrato machine-readable)

Toda respuesta de error tiene la forma:

```json
{ "error": "Límite de dispositivos alcanzado (3/3). Revoque un asiento en el panel o suba de plan.",
  "codigo": "cupo_dispositivos_lleno" }
```

- **`error`** es texto para el usuario: se reescribe, se acorta y algún día se
  traduce. **Ningún cliente debe ramificar por su contenido.**
- **`codigo`** es el identificador **estable**. Una vez publicado, un código **no
  cambia de significado** ni se recicla para otra condición. Si aparece una
  condición nueva, se agrega un código nuevo.
- El campo es **aditivo**: se omite del JSON cuando el error aún no está
  clasificado, así que los clientes que solo leían `error` no cambian.

Definidos como constantes en la clase `CodigosError`
(`server/PagoYa.Api/Contratos/Dtos.cs`), con un test que fija los valores
publicados (`tests/PagoYa.Api.Tests/CodigosErrorTests.cs`).

### Los dos `403` de `/sync/*` — no confundirlos

| Código | Qué pasó | Qué debe hacer el cliente |
|---|---|---|
| `sin_flag_cloud_sync` | La licencia es válida pero su tier **no incluye la nube**. | Pantalla de **upsell** al tier Cloud. La app sigue operando offline. |
| `asiento_revocado` | La licencia está bien; es **este dispositivo** el que perdió su asiento (`DELETE /devices/{id}`). | "Vuelve a vincular este equipo" → `POST /devices`. Nada de upsell. |

### Catálogo completo

| Código | HTTP | Dónde | Significado |
|---|---|---|---|
| `token_ausente` | 401 | `/sync/*` | No llegó `Authorization: Bearer`. |
| `token_invalido` | 401 | `/sync/*` | Formato, base64url, firma o payload inválidos. |
| `token_expirado` | 401 | `/sync/*` | `exp` vencido → revalidar con `/validate`. |
| `licencia_no_identificada` | 401 | `/sync/*` | El `license_id` del token no es un GUID. |
| `sin_flag_cloud_sync` | 403 | `/sync/*` | El tier no habilita `cloud_sync` (upsell). |
| `asiento_revocado` | 403 | `/sync/*` | El `device_id` del token ya no está activo. |
| `clave_no_encontrada` | 404 | `/activate`, `/validate`, `/devices`, webhook | La clave de licencia no existe. |
| `licencia_suspendida` | 409 | `/activate`, `/validate`, `/devices` | Suspendida por soporte/impago. |
| `licencia_revocada` | 409 | idem + admin | Revocada permanentemente. |
| `licencia_no_encontrada` | 404 | admin, `DELETE /devices/{id}` | Id de licencia inexistente. |
| `limite_traslados` | 409 | `/activate` | `MaxTraslados` agotado; requiere soporte. |
| `hwid_no_coincide` | 409 | `/validate` | El HWID no es el vinculado (usar `/activate`). |
| `cupo_dispositivos_lleno` | 409 | `/devices` | `MaxDispositivos` agotado → revocar un asiento o subir de plan. |
| `dispositivo_ya_es_principal` | 409 | `/devices` | Ese id es el equipo principal: usar `/activate`. |
| `principal_no_revocable` | 409 | `DELETE /devices/{id}` | El principal no se revoca por ahí. |
| `dispositivo_no_encontrado` | 404 | `DELETE /devices/{id}` | Asiento inexistente. |
| `device_id_requerido` | 400 | `/devices` | Falta `deviceId`. |
| `prefijos_agotados` | 409 | `/devices` | Se usaron los 99 prefijos de esa familia. |
| `credenciales_requeridas` | 401 | `DELETE /devices/{id}` | Ni `X-License-Key` ni credenciales admin. |
| `clave_no_corresponde` | 403 | `DELETE /devices/{id}` | La clave es de otra licencia. |
| `tier_invalido` | 400 | `/licenses` | Tier fuera de base\|cloud\|facturador. |
| `feature_invalido` | 400 | `/licenses` | Flag fuera del catálogo canónico. |
| `no_autorizado` | 401 | admin | Sesión/API key admin inválida o ausente. |
| `payload_invalido` | 400 | webhook | JSON inválido o campos requeridos ausentes. |
| `firma_webhook_invalida` | 401 | webhook | HMAC no verifica. |

---

## 11. Qué falta para producción

- **Pasarela de pago real:** adaptar `/webhooks/payment` al formato/firma del
  proveedor (Culqi, Izipay, Mercado Pago, Stripe...) y mapear sus eventos.
- **Rotación de llaves:** generar par en KMS/HSM, exponer 2 claves públicas en el
  cliente durante la transición, y versionar el `kid` en el token si se requiere.
- **Custodia de la privada:** KMS/HSM en vez de PEM en configuración.
- **Base de datos gestionada:** SQL Server/PostgreSQL + migraciones + backups.
- **AuthN/AuthZ admin real:** OAuth/OpenID en lugar de API key estática; panel admin.
- **Revocación / CRL:** lista de `license_id` revocados consultable por el cliente online.
- **Observabilidad:** métricas, tracing, alertas; endurecer rate limiting (Redis).
- **HTTPS/TLS**, CORS y hardening de despliegue.
- **Anti-tamper del cliente** (ofuscación) — fuera del alcance del backend.
- **Panel admin de dispositivos:** la API ya lista y revoca asientos
  (`GET /admin/licenses/{id}`, `DELETE /devices/{id}`); falta la vista en
  `wwwroot/app.js` que los muestre y ofrezca el botón de revocar.
- **Migración EF de las columnas de seats** (hoy `EnsureCreated`, ver §8).
```
