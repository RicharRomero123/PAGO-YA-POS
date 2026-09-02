# Seguridad y protección anti-ingeniería-inversa — PagoYa

Este documento describe cómo PagoYa se protege contra copia, pirateo y decompilado,
y por qué la estrategia es **arquitectónica** antes que solo "ofuscar el .exe".

---

## 1. La verdad primero

**Cualquier verificación que corra dentro del cliente se puede crackear.** Un atacante
con dnSpy/ILSpy puede, con tiempo, parchear un `if (licenciaValida)`. Por eso NO
confiamos la protección del negocio a la ofuscación. La ofuscación **sube el costo**
del ataque; la **arquitectura** es la que protege los ingresos.

## 2. Protección real: las funciones que cobran viven en el servidor

| Tier | Precio | ¿Dónde está el valor? | ¿Crackeable? |
|------|--------|------------------------|--------------|
| **Base** | S/ 20 pago único | 100% offline en el cliente | Sí, en teoría — **es barato a propósito** |
| **Cloud** | S/ 25/mes | Sync/respaldo **en el backend** | No sin suscripción válida en servidor |
| **Facturador Pro** | S/ 50–70/mes | Emisión SUNAT **vía backend/PSE** | No sin suscripción válida en servidor |

> 🔑 Aunque alguien piratee el `.exe`, **no puede sincronizar en la nube ni emitir
> comprobantes SUNAT** sin una cuenta con suscripción activa que el backend valida.
> Solo el modo Base offline es teóricamente reproducible, y su precio (S/ 20) hace
> que crackearlo no valga la pena. El ingreso recurrente queda protegido server-side.

## 3. Cadena de licencia (ya implementada)

- **Emisión:** solo el backend (`server/PagoYa.Api`) firma tokens con la **clave privada RSA-2048**. Esa clave **nunca** viaja al cliente ni entra al repo (`.gitignore`).
- **Validación:** el cliente (`src/PagoYa.Licensing`) solo lleva la **clave pública** y verifica firma → HWID → expiración+gracia. Cualquier fallo degrada a **Base seguro**.
- **HWID binding:** cada licencia queda atada al fingerprint del equipo (CPU + BaseBoard). Un token robado no sirve en otra PC. Traslados limitados y auditados.
- **Tokens de corta duración** para suscripciones (con grace period de 7 días) → un token filtrado caduca solo.

Detalle del formato en [`LICENSE-TOKEN.md`](./LICENSE-TOKEN.md).

## 4. Blindaje del binario cliente (capas)

1. **Sin símbolos de depuración en Release.** `PagoYa.Desktop.csproj` fija
   `DebugType=none` + `DebugSymbols=false` en Release: no se generan `.pdb`, que son
   el mapa que usan los decompiladores para reconstruir nombres y líneas.

2. **Ofuscación (Obfuscar, gratis).** Config en [`build/Obfuscar.xml`](../build/Obfuscar.xml),
   automatizada por [`build/publica.ps1`](../build/publica.ps1):
   - **Cifrado de cadenas** (`HideStrings`): oculta la clave pública embebida, las
     URLs del backend y los nombres de los claims. Esto es el mayor beneficio.
   - **Renombrado de miembros privados** (`HidePrivateApi`): ilegibiliza la lógica interna.
   - **Compatible con WPF:** `KeepPublicApi=true` — NO renombra propiedades públicas,
     porque los bindings de XAML se resuelven por nombre en runtime y se romperían.

3. **`SuppressIldasm`**: atributo que desalienta `ildasm.exe`.

## 5. Cómo publicar la versión protegida

```powershell
dotnet tool install -g Obfuscar.GlobalTool   # una sola vez
pwsh build\publica.ps1                        # publica Release + ofusca
# -> artifacts\publish  (carpeta lista para empaquetar con el instalador)
```

## 6. Qué NO está en el repo (secretos)

`.gitignore` excluye: clave privada RSA (`appsettings.Development.json`, `*_private_dev.pem`,
`server/**/keys/`), bases de datos (`*.db`), y certificados de facturación (`.pfx`).
**Nunca** commitees estos archivos.

## 7. Recomendaciones para PRODUCCIÓN (siguiente nivel)

- **Ofuscador WPF-aware comercial** (.NET Reactor / Eazfuscator.NET / Dotfuscator) si
  quieres renombrado público seguro para XAML + **control-flow** + **anti-tamper**
  (detecta binario parcheado) + empaquetado nativo. Obfuscar cubre bien el MVP.
- **Rotación de llaves RSA** con doble clave pública en transición; custodia en KMS/HSM.
- **Revocación online** (CRL) de licencias comprometidas cuando haya conexión.
- **Firma Authenticode** del instalador y del `.exe` (evita advertencias de Windows y
  detecta manipulación).
- **Ofuscar también** los strings sensibles del server no aplica (no se distribuye),
  pero sí endurecer su despliegue (TLS, secrets manager, auth admin real).

---

_Resumen: el binario se ofusca para encarecer el ataque, pero la defensa que sostiene
el modelo de negocio es que **Cloud y Facturación requieren tu backend**. Vende Base
barato, protege el recurrente en el servidor._
