# PagoYa — POS de Escritorio (Perú)

Sistema de **Punto de Venta** de escritorio para el mercado peruano (bodegas, minimarkets,
ferreterías, farmacias, hoteles, restaurantes), con **licenciamiento por niveles** (Base / Cloud /
Facturador Pro) atado al HWID de la máquina, **facturación electrónica SUNAT** (UBL 2.1) y
**sincronización en la nube**.

> Contexto de producto, tiers y reglas de negocio: ver [`CLAUDE.md`](CLAUDE.md).
> Arquitectura y seguridad del licenciamiento: ver [`docs/`](docs/).

---

## 1. Requisitos previos

Instala esto en cualquier PC nueva antes de arrancar:

| Herramienta | Para qué | Notas |
|-------------|----------|-------|
| **.NET SDK 8** (o superior) | Compilar cliente, server y tests | El repo fija `net8.0` con `rollForward: latestMajor` en [`global.json`](global.json). Si solo tienes un SDK preview (net10), usa `DOTNET_ROLL_FORWARD=LatestMajor` (ver §6). |
| **Windows** | El cliente **Desktop** es WPF (`net8.0-windows`) | El server, la facturación y los tests son cross-platform; solo el proyecto Desktop requiere Windows. |
| **Git** | Clonar y sincronizar | — |
| **Node.js 18+** (opcional) | Panel `web-admin` (Next.js) | Solo si vas a trabajar en el panel web de administración. |

---

## 2. Clonar el repositorio

```bash
git clone https://github.com/RicharRomero123/PAGO-YA-POS.git
cd PAGO-YA-POS
```

---

## 3. Estructura del repositorio

```
src/
  PagoYa.Core/            Entidades, enums y contratos (interfaces) del dominio
  PagoYa.Data/            Persistencia local SQLite (EF Core) + repositorios
  PagoYa.Licensing/       Validación OFFLINE del token (clave PÚBLICA embebida)
  PagoYa.Invoicing.Sunat/ Motor de facturación UBL 2.1 + firma XML
  PagoYa.Cloud/           Sincronización nube (outbox push/pull)
  PagoYa.Desktop/         Cliente WPF (MVVM) — la app del POS
server/
  PagoYa.Api/             Backend de licencias (ASP.NET Core) — NUNCA se entrega al cliente
                          Sirve además el panel admin web (wwwroot)
web-admin/                Panel admin en Next.js (alternativa/legacy al wwwroot)
tests/                    Tests (xUnit): Api, Cloud, Invoicing.Sunat
docs/                     ARQUITECTURA.md, SEGURIDAD.md, LICENSE-TOKEN.md
```

---

## 4. ⚠️ Secretos: lo que NO está en el repositorio

Por seguridad, el [`.gitignore`](.gitignore) **excluye** estos archivos. En una PC nueva **no
existirán tras clonar** y tendrás que regenerarlos/restaurarlos:

| Archivo (ignorado) | Qué es | Cómo obtenerlo en la nueva PC |
|--------------------|--------|-------------------------------|
| `server/PagoYa.Api/appsettings.Development.json` | Clave **privada** RSA + API key admin de dev | Crear a mano (plantilla abajo). |
| Claves `.pem` de dev (`pagoya_private_dev.pem`, etc.) | Par RSA-2048 de desarrollo | Generar con `gen-keys` (§5). |
| `*.db` / `pagoya-licencias.db` | Bases de datos locales SQLite | Se crean solas al arrancar. |
| `.pfx` / `.p12` / Clave SOL | Certificado digital SUNAT | Solo para facturación real; nunca versionar. |

> 🔑 **Importante:** la **clave privada** RSA vive **solo** en la PC del server (no en git). La
> **clave pública** sí está en el repo, embebida en `src/PagoYa.Licensing/ClavePublicaEmbebida.cs`.
> Ambas forman un **par de desarrollo**: si generas claves nuevas en la PC nueva, la pública impresa
> debe coincidir con la embebida, o vuelve a embeber la nueva (ver §5).

### Plantilla de `appsettings.Development.json`

Crea `server/PagoYa.Api/appsettings.Development.json` con:

```json
{
  "Firma": {
    "PrivateKeyPath": "./keys/pagoya_private_dev.pem"
  },
  "Admin": {
    "ApiKey": "dev-admin-key-cambia-esto"
  },
  "Webhook": {
    "HmacSecret": ""
  }
}
```

> Alternativa recomendada (no tocar archivos): usar **user-secrets** —
> `cd server/PagoYa.Api && dotnet user-secrets set "Firma:PrivateKeyPath" "C:\ruta\keys\pagoya_private_dev.pem"`.

---

## 5. Generar el par de claves RSA de desarrollo

Si es una PC nueva y no copiaste los `.pem` por USB, genéralos:

```bash
# Genera pagoya_private_dev.pem + pagoya_public_dev.pem e imprime la clave pública
dotnet run --project server/PagoYa.Api -- gen-keys ./server/PagoYa.Api/keys
```

Luego copia la **clave pública** impresa dentro de
`src/PagoYa.Licensing/ClavePublicaEmbebida.cs` (constante `PemPublicKey`) para que el cliente valide
los tokens que emite este server.

> Si quieres seguir usando las claves de tu otra PC (sin re-embeber), copia los `.pem` privados por
> **USB/carpeta segura** a `server/PagoYa.Api/keys/` — nunca por el repo.

---

## 6. Compilar y ejecutar

Desde la raíz del repo:

```bash
# Restaurar y compilar toda la solución
dotnet build PagoYa.sln

# Ejecutar el CLIENTE POS (solo Windows)
dotnet run --project src/PagoYa.Desktop

# Ejecutar el SERVER de licencias (http://localhost:5080, Swagger en /swagger)
dotnet run --project server/PagoYa.Api
```

> **Máquina solo con SDK preview** (net10, sin net8): antepón `DOTNET_ROLL_FORWARD=LatestMajor`, p.ej.
> `DOTNET_ROLL_FORWARD=LatestMajor dotnet run --project server/PagoYa.Api`. El aviso `NETSDK1057` es esperado.

### Panel web-admin (opcional, Next.js)

```bash
cd web-admin
npm install
npm run dev        # http://localhost:3000
```

---

## 7. Tests

```bash
dotnet test PagoYa.sln
```

Cubre el flujo de licencias (Api), la sincronización nube (Cloud) y la facturación SUNAT.

---

## 8. Flujo de licencia de punta a punta (dev)

1. Arranca el server (`dotnet run --project server/PagoYa.Api`).
2. Emite una licencia (admin): `POST /licenses` con `X-Admin-ApiKey` → devuelve `claveLicencia`.
3. En el cliente, activa con esa clave: el POS envía **clave + HWID** a `POST /activate` y recibe el
   **token firmado**, que se persiste localmente.
4. A partir de ahí el cliente valida **offline** contra la clave pública embebida.

Detalle completo de endpoints, política HWID y formato del token: [`server/README.md`](server/README.md)
y [`docs/LICENSE-TOKEN.md`](docs/LICENSE-TOKEN.md).

---

## 9. Trabajar desde varias PCs (flujo git)

**Regla de oro:** `git pull` **antes** de empezar y `git push` **al terminar**, en ambas máquinas.

```bash
git pull                       # traer lo último antes de trabajar
# ...cambios...
git add -A
git commit -m "descripción del cambio"
git push                       # subir al terminar
```

Recuerda: los secretos (§4) **no viajan por git**. Cada PC mantiene su propio
`appsettings.Development.json` y sus `.pem`. Si generas claves nuevas en una PC, sincroniza la clave
pública embebida (§5) por commit normal — esa sí va en el repo.

---

## 10. Documentación adicional

- [`CLAUDE.md`](CLAUDE.md) — visión de producto, tiers y reglas de negocio.
- [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) — arquitectura del sistema.
- [`docs/SEGURIDAD.md`](docs/SEGURIDAD.md) — modelo de seguridad del licenciamiento.
- [`docs/LICENSE-TOKEN.md`](docs/LICENSE-TOKEN.md) — formato y verificación del token de licencia.
- [`server/README.md`](server/README.md) — guía completa del backend de licencias (endpoints, HWID, prod).
