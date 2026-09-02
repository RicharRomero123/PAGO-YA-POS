/// Clave pública RSA-2048 embebida en el binario del cliente móvil para
/// verificar la firma de los tokens de licencia. La clave PRIVADA vive solo en
/// `server/PagoYa.Api` y NUNCA se incluye en este repositorio.
///
/// Es **exactamente la misma** constante que
/// `src/PagoYa.Licensing/ClavePublicaEmbebida.cs` (regla de oro de
/// `docs/MOBILE-ARQUITECTURA.md` §1: si el escritorio ya lo resolvió, el móvil
/// usa lo mismo). Si se rota la clave hay que cambiarla en **ambos** lados,
/// embebiendo vieja + nueva durante la transición.
///
/// ⚠ CLAVE DE DESARROLLO (DEV). Producción usará otra clave, generada con
/// `dotnet run -- gen-keys` en el server.
///
/// NOTA DE SEGURIDAD (docs/SEGURIDAD.md §1): embeber la pública es seguro (no
/// permite firmar). Un APK se decompila mucho más fácil que un WPF, así que
/// este gate offline es una **barrera comercial**, no criptográfica: lo que
/// realmente protege el ingreso recurrente es que Cloud y Facturación viven en
/// el backend. No prometas al usuario que es inviolable.
library;

/// PEM `SubjectPublicKeyInfo` de la clave pública RSA-2048 de PagoYa.
const String pemClavePublicaPagoYa = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwuuGPSEmXXb/q2J87t7f
Sbxn1DoL8ZvDzvyVOfdRQOettnr5XR1D9PK9gzADJ03ckRwcgq2d3ELMAQfTbRhb
BVaEk5O9eu51tWnS8AuCY70ZPbrdZkLGDCtsW34vH17BK0N76ihA9wS0dVUCrSzI
/eeapq5dTyW3wWnhuP3BOwlNue/0Up7RhirhHuD7hJrdUUVYc7BnJloHYDHhu7zW
LivfgBBCFnBeAlHaKLenDvnP74pIl5JACNjmzPIvoEkvIAUtEzbKaVUCXsP+wqQo
V7RucZvqrlnwtVecdfOi2Azz0f3Y3UzAuSchq7/24JG8iwz78BS9wuarJaWKxLZw
8QIDAQAB
-----END PUBLIC KEY-----
''';

/// Claves públicas aceptadas por el validador, en orden de preferencia.
///
/// Durante una rotación se embeben **dos**: la nueva primero y la vieja
/// después, para que los tokens ya emitidos sigan validando hasta que caduquen.
const List<String> pemClavesPublicasAceptadas = <String>[
  pemClavePublicaPagoYa,
];
