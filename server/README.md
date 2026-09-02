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
  "notas": "Venta FB Ads"
}
```
- `tier`: `base` | `cloud` | `facturador`.
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

## 6. Política HWID

- Una licencia = **un equipo activo** (`HwidActual`). Los HWID previos quedan como
  histórico en `Devices` (`Activo=false`, `DesvinculadoUtc`).
- **Reactivar en el mismo equipo** no consume cupo.
- **Trasladar a otro equipo** consume un cupo hasta `MaxTraslados` (default **2**).
  Superado el límite → `409` que exige **aprobación manual** de soporte
  (subir `MaxTraslados` o reactivar vía admin).
- `/validate` no traslada: si el HWID no coincide, responde `409`.
- Todo queda auditado en `ActivationLogs` (`activacion`, `traslado`, `validacion`,
  `rechazo`, `pago`, `suspension`, `reactivacion`, con IP y detalle).

---

## 7. Persistencia (EF Core + SQLite)

Tablas: `Licenses`, `Devices`, `Subscriptions`, `PaymentEvents`, `ActivationLogs`.
Se crean con `EnsureCreated` al arrancar (dev). Para prod, migrar a
SQL Server/PostgreSQL y usar migraciones EF (`dotnet ef migrations add Inicial`).

---

## 8. Seguridad operativa incluida

- **Rate limiting** por IP: global 60 req/min; `/activate` y `/validate` 10 req/min
  (anti fuerza bruta de claves).
- **API key admin** en emisión y endpoints admin (comparación en tiempo constante).
- **HMAC** en el webhook + **idempotencia** por `eventId`.
- Validación de entrada en DTOs; dominio en español; nullable habilitado; async.

---

## 9. Qué falta para producción

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
```
