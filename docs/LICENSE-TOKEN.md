# Contrato del Token de Licencia — PagoYa

> Documento de contrato compartido entre **licensing-backend** (emisor, guarda
> la clave privada) y el **cliente PagoYa** (validador, embebe la clave pública).
> Cualquier cambio a este esquema debe coordinarse en ambos lados.

## 1. Objetivo

El token es la única fuente de verdad para el **feature-gating**. Sin un token
válido, la app opera en modo **Base** sin importar el código presente en el
binario. El cliente **nunca** confía en un flag local sin verificar la firma
RSA contra la clave pública embebida.

## 2. Algoritmo criptográfico

- **Firma:** RSA-2048, esquema `RSASSA-PKCS1-v1_5` sobre `SHA-256`.
- La clave **privada** vive solo en licensing-backend (nunca en el repo/cliente).
- La clave **pública** se embebe en `PagoYa.Licensing/ClavePublicaEmbebida.cs`
  (formato PEM SubjectPublicKeyInfo).

## 3. Formato del token en tránsito

```
<base64url(payload_json)> "." <base64url(firma_rsa)>
```

- `payload_json`: el objeto de claims serializado en UTF-8 (ver §4).
- La firma se calcula sobre los **bytes crudos del payload** (antes de base64url),
  no sobre el string base64url. El validador decodifica ambas partes y verifica
  `VerifyData(payloadBytes, firmaBytes, SHA256, Pkcs1)`.
- `base64url` = base64 estándar con `+`→`-`, `/`→`_`, sin padding `=`.

## 4. Claims del payload

| Claim        | Tipo     | Obligatorio | Descripción |
|--------------|----------|-------------|-------------|
| `license_id` | string   | Sí          | Id único de la licencia (para revocación y soporte). |
| `tier`       | string   | Sí          | Tier comercial: `base` \| `cloud` \| `facturador`. |
| `features`   | string[] | Sí          | Flags habilitados (ver §5). Puede ser `[]`. |
| `hwid`       | string   | Sí\*        | HWID vinculado (hash del hardware). Vacío = no atada a máquina. |
| `iat`        | number   | Sí          | Issued-at, Unix epoch en segundos (UTC). |
| `exp`        | number   | Sí          | Expiración, Unix epoch (UTC). `0` = perpetua (típico de Base). |
| `sub`        | string   | No          | RUC/identificador del negocio (informativo). |

\* `hwid` puede ir vacío si el modelo comercial no ata la licencia a un equipo,
pero para los tiers de suscripción se recomienda vincularlo (anti-reuso).

### Ejemplo de payload (antes de firmar)

```json
{
  "license_id": "a1b2c3d4-0000-4000-8000-000000000001",
  "tier": "facturador",
  "features": ["invoicing", "cloud_sync", "multi_site"],
  "hwid": "9F3A...HASH...",
  "iat": 1755820800,
  "exp": 1758499200,
  "sub": "20512345678"
}
```

## 5. Esquema de feature-gating (flags)

Los nombres de flag son **canónicos y estables**. Están definidos en código en
`PagoYa.Core/Contratos/CaracteristicaLicencia.cs` (clase `Flags`).

| Flag         | Habilita | Interfaz gated |
|--------------|----------|----------------|
| `invoicing`  | Facturación electrónica SUNAT (Boletas/Facturas). | `IInvoiceEngine` |
| `cloud_sync` | Respaldo y sincronización en la nube. | `ISyncService` |
| `multi_site` | Operación multi-caja / multisede. | (lógica en Data/Cloud) |

El gating es **por flag individual**, no por tier: un token podría, por ejemplo,
habilitar `cloud_sync` sin `invoicing`. El `tier` es informativo/comercial.

### Mapeo tier → flags por defecto (referencia comercial)

| Tier          | Flags típicos |
|---------------|---------------|
| `base`        | (ninguno) |
| `cloud`       | `cloud_sync`, `multi_site` |
| `facturador`  | `cloud_sync`, `multi_site`, `invoicing` |

> El backend puede emitir combinaciones distintas si el negocio lo requiere;
> el cliente solo respeta lo que venga firmado en `features`.

## 6. Reglas de validación en el cliente

El cliente (`LicenseTokenValidator` + `LicenseService`) aplica, en orden:

1. **Firma:** verificar RSA contra la clave pública embebida. Si falla → Base.
2. **HWID:** si `hwid` no está vacío, debe coincidir con el HWID local
   (`IHardwareId.ObtenerHwid()`). Si no coincide → Base ("otro equipo").
3. **Expiración + gracia:** si `exp != 0` y ya pasó:
   - dentro de **`DiasGracia` (7 días)** tras `exp` → sigue operando con aviso
     de renovación (`EnPeriodoGracia = true`);
   - pasado el grace period → Base.
4. Si todo pasa → `EstadoLicencia` con `EsValida = true` y los `features`.

Cualquier fallo degrada a un **estado Base seguro** (nunca habilita premium).

## 7. Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Replay del token en otro PC | Vinculación por `hwid`. |
| Manipulación del payload | Firma RSA sobre los bytes del payload. |
| Parcheo del binario (saltar verificación) | Ofuscación/anti-tamper (fuera de este skeleton). |
| Robo de la clave privada | Custodia en backend (KMS/HSM); rotación de clave con doble clave pública embebida durante transición. |
| Token expirado en caliente | Grace period de 7 días para no bloquear al negocio. |
