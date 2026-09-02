namespace PagoYa.Core.Contratos;

/// <summary>
/// Servicio de licenciamiento del cliente. Valida el token firmado (RSA-2048)
/// contra la clave pública embebida y expone el <see cref="EstadoLicencia"/>
/// actual para feature-gating.
///
/// SEGURIDAD: la implementación NUNCA debe confiar en un flag local sin
/// validar la firma del token contra la clave pública. Ver PagoYa.Licensing.
///
/// Implementa: licensing-backend (emite) + PagoYa.Licensing (valida en cliente).
/// </summary>
public interface ILicenseService
{
    /// <summary>Estado de licencia vigente (cacheado tras la última validación).</summary>
    EstadoLicencia EstadoActual { get; }

    /// <summary>
    /// Valida el token de licencia (texto firmado) contra la clave pública y
    /// el HWID de esta máquina. Actualiza <see cref="EstadoActual"/>.
    /// </summary>
    /// <param name="tokenFirmado">Token de licencia serializado y firmado.</param>
    /// <returns>El estado resultante de la validación.</returns>
    EstadoLicencia ValidarToken(string tokenFirmado);

    /// <summary>
    /// Carga y valida la licencia persistida localmente (si existe). Se llama
    /// al arranque. Si no hay licencia o es inválida, retorna estado Base.
    /// </summary>
    EstadoLicencia CargarLicenciaLocal();

    /// <summary>
    /// Activa una licencia pegada por el usuario: valida el token (firma + HWID +
    /// expiración) y, <b>solo si es válido</b>, lo PERSISTE localmente para futuros
    /// arranques. Actualiza <see cref="EstadoActual"/>. Si la validación falla, no
    /// persiste nada y devuelve el estado Base con el motivo del rechazo.
    ///
    /// Nota: los módulos premium se componen al arranque, por lo que desbloquearlos
    /// tras una activación en caliente requiere reiniciar la app.
    /// </summary>
    EstadoLicencia ActivarLicencia(string tokenFirmado);

    /// <summary>Atajo de feature-gating: ¿está habilitada esta característica?</summary>
    bool TieneCaracteristica(CaracteristicaLicencia caracteristica);
}
