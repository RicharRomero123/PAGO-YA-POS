# Arquitectura — PagoYa (esqueleto)

> POS de escritorio para Perú. App base **100% offline** sobre SQLite; los
> módulos caros (facturación, nube, multisede) son **servicios desacoplados**
> que se activan **solo** con un flag criptográfico dentro del token de licencia
> firmado (RSA-2048). Ver `CLAUDE.md` para el contexto de negocio y tiers.

## 1. Estructura de carpetas

```
PagoYa-POS/
├─ PagoYa.sln                      # Solución que agrupa los 6 proyectos
├─ global.json                     # Fija SDK .NET 8 (rollForward latestMajor)
├─ Directory.Build.props           # net8.0, nullable, ImplicitUsings comunes
├─ docs/
│  ├─ ARQUITECTURA.md              # Este documento
│  └─ LICENSE-TOKEN.md             # Contrato del token de licencia
└─ src/
   ├─ PagoYa.Core/                 # Dominio puro: entidades, enums, CONTRATOS
   │  ├─ Common/EntidadBase.cs     #   PK UUID + timestamps + origen_caja
   │  ├─ Entidades/               #   Producto, Venta, DetalleVenta, Caja,
   │  │                           #   MovimientoCaja, Inventario, Comprobante
   │  ├─ Enums/                    #   TipoComprobante, TierLicencia, MetodoPago, ...
   │  └─ Contratos/               #   ILicenseService, IHardwareId, IInvoiceEngine,
   │                              #   ISyncService, I*Repository, EstadoLicencia, Flags
   ├─ PagoYa.Data/                 # Persistencia SQLite (Dapper)
   │  ├─ Esquema/esquema.sql       #   Script de esquema (embebido) + outbox
   │  ├─ PagoYaDbContext.cs        #   Fábrica de conexión + init de esquema
   │  └─ Repositorios/            #   Implementaciones de los I*Repository (stubs)
   ├─ PagoYa.Licensing/            # Validación del token firmado (SOLO valida)
   │  ├─ LicenseToken.cs           #   Modelo del payload (claims)
   │  ├─ ClavePublicaEmbebida.cs   #   Clave pública RSA embebida (placeholder)
   │  ├─ LicenseTokenValidator.cs  #   Verificación de firma RSA + parseo
   │  └─ LicenseService.cs         #   ILicenseService: HWID, expiración, gracia
   ├─ PagoYa.Invoicing.Sunat/      # PREMIUM: facturación SUNAT (flag "invoicing")
   │  ├─ SunatInvoiceEngine.cs     #   IInvoiceEngine real (stub)
   │  └─ InvoiceEngineDeshabilitado.cs  # Null Object cuando no hay licencia
   ├─ PagoYa.Cloud/                # PREMIUM: sync nube (flag "cloud_sync")
   │  ├─ CloudSyncService.cs       #   ISyncService real (stub)
   │  └─ SyncServiceDeshabilitado.cs    # Null Object cuando no hay licencia
   └─ PagoYa.Desktop/              # Cliente WPF + COMPOSITION ROOT
      ├─ App.xaml(.cs)             #   Arranque MVVM + DI + carga de licencia
      ├─ MainWindow.xaml(.cs)      #   Ventana placeholder
      ├─ ViewModels/               #   MainWindowViewModel (CommunityToolkit.Mvvm)
      └─ Servicios/                #   CompositionRoot (feature-gating), HWID, LicenseStore
```

## 2. Mapa de dependencias (referencias entre proyectos)

```
                 ┌───────────────┐
                 │  PagoYa.Core  │  (dominio + contratos; SIN dependencias premium)
                 └──────▲──▲──▲──┘
        ┌───────────────┘  │  └────────────────┐
        │                  │                   │
 ┌──────┴──────┐   ┌───────┴────────┐   ┌──────┴───────┐
 │ PagoYa.Data │   │PagoYa.Licensing│   │PagoYa.Cloud  │
 └──────▲──────┘   └───────▲────────┘   └──────▲───────┘
        │                  │            ┌──────┴────────────────┐
        │                  │            │ PagoYa.Invoicing.Sunat │
        │                  │            └──────▲────────────────┘
        └──────────┬───────┴───────────────────┘
                   │
          ┌────────┴─────────┐
          │  PagoYa.Desktop  │  (composition root: referencia TODO y hace el gating)
          └──────────────────┘
```

**Regla invariante:** `PagoYa.Core` **no referencia** ningún módulo premium.
Los premium referencian a Core. Solo `PagoYa.Desktop` referencia todo, porque
es donde se compone el grafo y se decide qué implementación se inyecta.

## 3. Flujo de feature-gating por licencia

1. **Arranque** (`App.OnStartup`): se construye el contenedor de DI
   (`CompositionRoot.Registrar`) y se llama `ILicenseService.CargarLicenciaLocal()`.
2. **Validación** (`LicenseService`):
   - `LicenseTokenValidator` verifica la **firma RSA-2048** contra la clave
     pública embebida y parsea el `LicenseToken`.
   - Se comprueba **HWID** (anti-reuso) y **expiración con grace period (7 días)**.
   - Se produce un `EstadoLicencia` inmutable con el conjunto de `features`.
3. **Resolución de módulos premium** (en `CompositionRoot`, patrón *factory*):
   - `IInvoiceEngine` → `SunatInvoiceEngine` si `invoicing`, si no
     `InvoiceEngineDeshabilitado` (**Null Object** que rechaza la emisión).
   - `ISyncService` → `CloudSyncService` si `cloud_sync`, si no
     `SyncServiceDeshabilitado` (no-op).
4. **El resto de la app** depende siempre de la interfaz (`IInvoiceEngine`,
   `ISyncService`), sin `if (tier == ...)` esparcidos: el gating vive en la
   composición. Cambiar de tier = cambiar qué objeto se inyecta.

> Regla de negocio clave: si la firma no valida, la app degrada a **Base seguro**
> (ningún feature premium), sin importar el código presente en el binario.

## 4. Datos: local vs nube

- **Local (siempre):** SQLite vía `PagoYa.Data` (Dapper). PK = **UUID (TEXT)**
  para evitar colisiones entre cajas/sedes offline que luego consolidan.
- **Nube (tier Cloud):** **outbox pattern**. Cada escritura de negocio registra
  un evento en `outbox_sync`; `ISyncService` lo envía al backend y resuelve
  conflictos por **last-write-wins** (`updated_utc` + UUID). En tier Base la
  tabla existe pero permanece inactiva.

## 5. ¿Qué agente trabaja en cada proyecto?

| Proyecto | Agente responsable | Alcance |
|----------|--------------------|---------|
| `PagoYa.Core` | **lead-architect** | Entidades, enums, contratos. Cambios coordinados. |
| `PagoYa.Data` | **desktop-dev** | Implementar repositorios Dapper, transacciones, outbox. |
| `PagoYa.Desktop` | **desktop-dev** + **ui-ux-designer** | UI WPF, MVVM, HWID/WMI, ESC/POS, cobro rápido. |
| `PagoYa.Licensing` | **licensing-backend** (contrato) + **desktop-dev** (integración) | Clave pública real, validación, store cifrado. |
| `PagoYa.Invoicing.Sunat` | **sunat-facturacion** | UBL 2.1, firma X509, envío SUNAT/PSE, CDR. |
| `PagoYa.Cloud` | **licensing-backend** / cloud-dev | Push/pull outbox, resolución de conflictos. |

## 6. Decisiones y trade-offs

| Decisión | Elegido | Alternativa descartada | Motivo |
|----------|---------|------------------------|--------|
| UI framework | **WPF** (`net8.0-windows`) | WinUI 3 | Madurez, tooling, menos incidencias de deployment en PCs de bodega. |
| ORM local | **Dapper + Microsoft.Data.Sqlite** | EF Core | Arranque rápido, SQL explícito, footprint chico; equipo pequeño. |
| Identidad (PK) | **UUID (TEXT)** | INTEGER autoincrement | Evita colisiones multi-caja/multisede offline. |
| Feature-gating | **Null Object + factory en DI** | `if (tier)` disperso | Core desacoplado; el gating vive en un solo lugar. |
| Facturación | **PSE intermedio** (recomendado) | SOAP SUNAT directo | Menos soporte por WhatsApp; el cliente no lidia con certificados. |
| Licencia offline | **Grace period 7 días** | Corte inmediato al expirar | No bloquear al negocio en caliente por un corte de red/pago. |
