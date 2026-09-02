/// ⚠ ARCHIVO OBSOLETO — **bórralo**.
///
/// `GuardiaReloj` se convirtió en el puerto `RelojAuditado`
/// (`puertos_licencia.dart`) con su implementación `RelojAuditadoMeta`
/// (`reloj_auditado.dart`), que es la forma que quedó tras el arbitraje de
/// contratos de `mobile-lead` (MOBILE-ARQUITECTURA §4.2).
///
/// La lógica es la misma: `ultimo_visto_utc` monotónico en `meta`, tope de
/// avance para no envenenar el piso, y el piso como cota inferior al evaluar la
/// expiración cuando el retroceso es sospechoso.
///
/// Se deja vacío en vez de eliminarlo porque el entorno donde se escribió no
/// tenía shell para borrar archivos. No declara nada: es inerte.
library;
