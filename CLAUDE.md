# PagoYa — POS de Escritorio (Perú)

> Sistema de Punto de Venta para el mercado peruano, vendido por Facebook Ads con modelo
> de licenciamiento por niveles. **Todas las tiers —incluida Base— requieren activar una
> licencia criptográfica** (token firmado atado al HWID de la máquina). Tras esa activación
> única, la app **funciona offline de por vida**; las funciones premium (nube, multisede,
> facturación electrónica) se desbloquean con los flags del mismo token.

## Visión del producto

PagoYa es un POS rápido de escritorio pensado para negocios pequeños en Perú (bodegas,
minimarkets, ferreterías, farmacias). El diferenciador es el **precio de entrada bajo** con
venta rápida por Facebook Ads: el usuario compra una licencia de por vida, instala, **activa una
sola vez** (envía su HWID, recibe el token y lo pega/importa) y luego usa el programa sin internet.
La activación es **verificable offline** (firma RSA + HWID + reloj, sin llamar a ningún servidor) y
también puede hacerse **por archivo/USB** en cajas sin conexión. Luego se ofrecen **upsells por
suscripción** (nube, facturación SUNAT).

## Modelo de Tiers (Licenciamiento)

| Nivel | Precio | Características |
|-------|--------|----------------|
| **PagoYa Base** | S/ 20 (pago único) | Activación única por HWID; luego offline de por vida (token perpetuo, `exp=0`), 1 caja, notas de venta / tickets internos, control de inventario local (SQLite). |
| **PagoYa Cloud** | S/ 25 / mes | Todo lo anterior + respaldo en la nube, multi-caja / multisede, reportes móviles. |
| **PagoYa Facturador Pro** | S/ 50–70 / mes | Todo lo anterior + Boletas/Facturas ilimitadas, envío directo a SUNAT/OSE, PDF por WhatsApp. |

**Regla de negocio clave:** el arranque tiene un **gate de activación** — sin un token de licencia
**auténtico** instalado (firma RSA-2048 válida + HWID de la máquina + no vencido) la app **no opera**
(muestra la pantalla de activación y no entra al POS). Esto vale también para Base: el instalador por
sí solo es un cascarón, y como el token está atado al HWID no se reutiliza en otra PC. Cada función
cara (Facturación, Cloud, Multisede) se habilita **solo con su flag criptográfico** dentro del token.
El estado `EstadoLicencia.EstaActivada` (true solo con token auténtico) es lo que consulta el gate.

## Arquitectura (alto nivel)

```
[ Lead Architect ] — define contratos, DB local vs nube, modularización
        │
   ┌────┴─────────────────────────────┐
   ▼                                   ▼
[ Desktop Dev ]                 [ Backend & Licencias ]
 WPF/WinUI, SQLite, HWID         ASP.NET Core, Auth RSA, Webhooks PagoYa
   │                                   │
   └────────────────┬──────────────────┘
                    ▼
          [ Facturación SUNAT ]
           UBL 2.1, CDR, XML, firma X509
```

## Stack técnico

- **Desktop:** C# / .NET 8 (o 9), WPF o WinUI 3, MVVM (CommunityToolkit.Mvvm).
- **Persistencia local:** SQLite (Microsoft.Data.Sqlite / EF Core) o LiteDB.
- **Backend licencias:** ASP.NET Core Minimal API, firma asimétrica RSA-2048.
- **HWID:** fingerprint por CPU ID + BaseBoard serial (WMI).
- **Facturación:** UBL 2.1, firma X509Certificate2 (.pfx), SOAP/REST SUNAT o PSE
  intermedio (Nubefact / ApisPeru / OpenInvoicePeru).
- **Impresión:** tickets térmicos ESC/POS.

## Estrategia del módulo de Facturación

- **Vía Directa (SOAP SUNAT):** sin comisiones por comprobante, pero el cliente necesita su
  propio Certificado Digital (.pfx) y Clave SOL secundaria.
- **Vía PSE intermedio (Nubefact/ApisPeru):** el cliente no lidia con certificados; el backend
  hace de puente por JSON. **Recomendado** para reducir soporte por WhatsApp.

## Agentes especializados

Invócalos con `@nombre` o vía el subagente correspondiente:

### Escritorio y backend

- **lead-architect** — Arquitectura, contratos de API, modularización, seguridad de licencias.
- **desktop-dev** — Cliente WPF/WinUI, SQLite local, HWID, ESC/POS, MVVM.
- **ui-ux-designer** — Diseño de interfaz del POS (pantalla de cobro rápido, teclado, UX).
- **licensing-backend** — API ASP.NET Core, firma RSA, validación HWID, webhooks.
- **sunat-facturacion** — Motor UBL 2.1, firma digital, CDR, integración SUNAT/PSE.

### App móvil (Flutter)

Trabajan en paralelo sobre `mobile/`. Su contrato compartido —estructura,
decisiones cerradas y mapa de propiedad de archivos para que no se pisen— es
[`docs/MOBILE-ARQUITECTURA.md`](docs/MOBILE-ARQUITECTURA.md).

- **mobile-lead** — Arquitectura de la app, contratos Dart, pubspec, arbitraje entre agentes móviles.
- **flutter-datos** — Dominio, `Dinero`/IGV, SQLite (drift) sobre el mismo esquema, repositorios, outbox, plantillas por rubro.
- **flutter-licencia** — Validador RSA en Dart, identidad del dispositivo, gate de activación, feature gating.
- **flutter-sync** — Cliente de `/sync/push` y `/sync/pull`, cursor, LWW, reintentos, estado de nube.
- **mobile-ux** — Sistema de diseño portado del tema WPF, iconografía, onboarding por rubro, estados de upsell.
- **flutter-ui** — Pantallas: cobro rápido, caja, inventario, mesas, habitaciones, reportes.
- **flutter-hardware** — ESC/POS por Bluetooth, escáner con cámara, secure storage, permisos Android/iOS.
- **backend-seats** — Cambios en `server/` que el móvil necesita: seats de dispositivo, filtro de eco, entidades de sync ampliadas.

## Convenciones

- Idioma de código/comentarios: español para dominio de negocio (Boleta, Factura, Caja, Sede),
  inglés para términos técnicos genéricos.
- Nada de credenciales, certificados .pfx ni claves SOL en el repositorio.
- El binario del cliente **nunca** debe confiar en flags locales sin validar la firma del token.
```

