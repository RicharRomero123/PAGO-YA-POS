namespace PagoYa.Licensing;

/// <summary>
/// Clave pública RSA-2048 embebida en el binario del cliente para verificar la
/// firma de los tokens de licencia. La clave PRIVADA correspondiente vive solo
/// en el licensing-backend y NUNCA se incluye en este repositorio.
///
/// TODO(licensing-backend): reemplazar el placeholder por la clave pública real
/// en formato PEM (SubjectPublicKeyInfo). Debe ser el par de la clave privada
/// usada para firmar. Rotación: si se rota la clave, embeber ambas (vieja+nueva)
/// durante el periodo de transición.
///
/// NOTA DE SEGURIDAD: embeber la clave pública es seguro (no permite firmar).
/// El riesgo real es que un atacante parchee el binario para saltarse la
/// verificación; se mitiga con ofuscación/anti-tamper (fuera de este skeleton).
/// </summary>
public static class ClavePublicaEmbebida
{
    /// <summary>
    /// Clave pública RSA-2048 en formato PEM (SubjectPublicKeyInfo).
    ///
    /// ⚠ CLAVE DE DESARROLLO (DEV). Es el par de la clave privada de dev que vive
    /// en el licensing-backend (server/PagoYa.Api, en appsettings.Development.json
    /// / user-secrets, fuera de git). PRODUCCIÓN usará OTRA clave: regenerar el par
    /// con `dotnet run -- gen-keys` en el server y reemplazar esta constante por la
    /// nueva pública, custodiando la privada en un KMS/HSM.
    ///
    /// Un token emitido por server/PagoYa.Api con la privada de dev valida contra
    /// esta pública en LicenseTokenValidator (RSA-2048, PKCS#1 v1.5, SHA-256).
    /// </summary>
    public const string PemPublicKey =
        """
        -----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwuuGPSEmXXb/q2J87t7f
        Sbxn1DoL8ZvDzvyVOfdRQOettnr5XR1D9PK9gzADJ03ckRwcgq2d3ELMAQfTbRhb
        BVaEk5O9eu51tWnS8AuCY70ZPbrdZkLGDCtsW34vH17BK0N76ihA9wS0dVUCrSzI
        /eeapq5dTyW3wWnhuP3BOwlNue/0Up7RhirhHuD7hJrdUUVYc7BnJloHYDHhu7zW
        LivfgBBCFnBeAlHaKLenDvnP74pIl5JACNjmzPIvoEkvIAUtEzbKaVUCXsP+wqQo
        V7RucZvqrlnwtVecdfOi2Azz0f3Y3UzAuSchq7/24JG8iwz78BS9wuarJaWKxLZw
        8QIDAQAB
        -----END PUBLIC KEY-----
        """;
}
