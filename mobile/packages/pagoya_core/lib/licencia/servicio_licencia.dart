/// Puerto en Dart de `src/PagoYa.Licensing/LicenseService.cs`.
///
/// Aplica el **mismo orden** que el escritorio (docs/LICENSE-TOKEN.md §6):
///
///   1. **Firma** RSA contra la clave pública embebida.
///   2. **Dispositivo**: `hwid` del token vs. id local. En un token de asiento
///      móvil ese `hwid` es el id del propio celular, no el HWID de la PC.
///   3. **Expiración** con grace period de 7 días.
///
/// Cualquier fallo devuelve `EstadoLicencia.baseSegura`: nunca habilita una
/// feature premium por defecto (regla clave de CLAUDE.md), y `estaActivada`
/// queda en `false`, que es lo que manda al usuario al gate de activación —
/// también en el plan Base.
///
/// Es una **clase concreta**, no una interfaz (arbitraje de `mobile-lead`,
/// MOBILE-ARQUITECTURA §4.2): una interfaz extra no aportaba nada, porque la
/// única implementación posible es ésta y los tests inyectan sus dobles por los
/// puertos, no por el servicio.
library;

import 'dart:async';

import 'estado_licencia.dart';
import 'license_token.dart';
import 'license_token_validator.dart';
import 'meta_licencia.dart';
import 'puertos_licencia.dart';

/// Servicio de licencia del cliente móvil.
final class ServicioLicencia {
  final LicenseTokenValidator _validador;
  final IdentidadDispositivo _identidad;
  final AlmacenLicencia _almacen;
  final RelojAuditado _reloj;
  final MetaLicencia _meta;

  final StreamController<EstadoLicencia> _cambios =
      StreamController<EstadoLicencia>.broadcast();

  EstadoLicencia _estadoActual = EstadoLicencia.baseSegura(
    motivo: 'Licencia no cargada.',
    motivoDegradacion: MotivoDegradacion.sinToken,
  );

  ServicioLicencia({
    required LicenseTokenValidator validador,
    required IdentidadDispositivo identidad,
    required AlmacenLicencia almacen,
    required RelojAuditado reloj,
    required MetaLicencia meta,
  })  : _validador = validador,
        _identidad = identidad,
        _almacen = almacen,
        _reloj = reloj,
        _meta = meta;

  /// Estado vigente, cacheado tras la última validación. Nunca `null`: si no se
  /// ha cargado nada todavía vale `EstadoLicencia.baseSegura`.
  ///
  /// Es lo que consulta el gate de arranque y el feature-gating de la UI.
  EstadoLicencia get estadoActual => _estadoActual;

  /// Cambios de estado, para que la UI reaccione sin reiniciar: tras activar,
  /// tras renovar, o al detectar el fin del grace period.
  Stream<EstadoLicencia> get cambios => _cambios.stream;

  /// Carga y valida el token persistido. Es el paso 3 del arranque.
  Future<EstadoLicencia> cargarLicenciaLocal() async {
    String? tokenGuardado;
    try {
      tokenGuardado = await _almacen.leerToken();
    } catch (_) {
      // Almacén seguro ilegible (p. ej. cambió la firma del APK en Android):
      // se trata como "sin licencia", que lleva a la pantalla de activación.
      tokenGuardado = null;
    }

    if (tokenGuardado == null || tokenGuardado.trim().isEmpty) {
      return _publicar(
        EstadoLicencia.baseSegura(
          motivo: 'Sin licencia instalada. Activa PagoYa para empezar a vender.',
          motivoDegradacion: MotivoDegradacion.sinToken,
        ),
      );
    }

    return validarToken(tokenGuardado);
  }

  /// Valida un token **sin persistirlo**. Sirve para previsualizar qué
  /// desbloquearía antes de activarlo.
  Future<EstadoLicencia> validarToken(String tokenFirmado) async {
    final (EstadoLicencia, bool) r = await _validarInterno(tokenFirmado);
    return _publicar(r.$1);
  }

  /// Valida y, **solo si el token es auténtico**, lo persiste.
  ///
  /// Igual que en C#: una activación fallida nunca sobrescribe una licencia
  /// buena ya instalada.
  Future<EstadoLicencia> activarLicencia(String tokenFirmado) async {
    final (EstadoLicencia, bool) r = await _validarInterno(tokenFirmado);
    final EstadoLicencia estado = r.$1;

    if (r.$2) {
      await _almacen.guardarToken(tokenFirmado.trim());
      await _persistirDatosDeAsiento(estado);
    }

    return _publicar(estado);
  }

  /// Borra la licencia local (liberar el equipo / cerrar el negocio). Tras esto
  /// el gate de arranque vuelve a la pantalla de activación.
  Future<void> desactivar() async {
    await _almacen.borrarToken();
    await _meta.borrar(ClavesMetaLicencia.prefijoDispositivo);
    await _meta.borrar(ClavesMetaLicencia.idAsiento);
    _publicar(
      EstadoLicencia.baseSegura(
        motivo: 'Licencia desactivada en este dispositivo.',
        motivoDegradacion: MotivoDegradacion.sinToken,
      ),
    );
  }

  /// Atajo de feature-gating sobre el estado vigente.
  bool tieneCaracteristica(CaracteristicaLicencia caracteristica) =>
      _estadoActual.tieneCaracteristica(caracteristica);

  /// Cierra el stream de [cambios]. Lo llama el composition root al salir.
  Future<void> liberar() => _cambios.close();

  EstadoLicencia _publicar(EstadoLicencia estado) {
    _estadoActual = estado;
    if (!_cambios.isClosed) _cambios.add(estado);
    return estado;
  }

  /// Guarda en `meta` los claims aditivos del modelo de asientos.
  ///
  /// `device_prefix` lo necesitan **otros agentes**: `flutter-datos` para los
  /// correlativos `M01-000123` y `flutter-sync` como `origen_caja_id` del
  /// outbox y para el filtro de eco del pull. Se escribe desde aquí porque este
  /// es el único punto donde el valor llega **firmado y verificado**: leerlo de
  /// la respuesta HTTP de `/devices` sería confiar en la red.
  ///
  /// Ambos claims son **opcionales** (docs/LICENSE-TOKEN.md §4.1): si el token
  /// no los trae, no se escribe nada y quien los consuma aplica su valor por
  /// defecto. Nunca se inventa un prefijo: son únicos por licencia y los asigna
  /// el backend.
  Future<void> _persistirDatosDeAsiento(EstadoLicencia estado) async {
    final String? prefijo = estado.prefijoDispositivo;
    if (prefijo != null && prefijo.isNotEmpty) {
      await _meta.escribir(ClavesMetaLicencia.prefijoDispositivo, prefijo);
    }

    final String? asiento = estado.idAsiento;
    if (asiento != null && asiento.isNotEmpty) {
      await _meta.escribir(ClavesMetaLicencia.idAsiento, asiento);
    }
  }

  /// Núcleo de validación. Puro respecto al estado: no muta nada ni persiste.
  /// El `bool` del par es `true` solo si el token superó firma, dispositivo y
  /// ventana de expiración/gracia — es decir, si es persistible.
  Future<(EstadoLicencia, bool)> _validarInterno(String tokenFirmado) async {
    // La marca monotónica se actualiza siempre, valga o no el token: mantener
    // `ultimo_visto_utc` no depende de la licencia.
    await _reloj.registrarVisto();
    final bool relojSospechoso = await _reloj.detectoRetroceso();

    // --- 1) Firma criptográfica ---
    final ResultadoValidacionToken firma = _validador.validar(tokenFirmado);
    final LicenseToken? token = firma.token;
    if (token == null) {
      return (
        EstadoLicencia.baseSegura(
          motivo: 'Token inválido: ${firma.error}',
          motivoDegradacion: MotivoDegradacion.firmaInvalida,
          relojSospechoso: relojSospechoso,
        ),
        false,
      );
    }

    // --- 2) Vinculación al dispositivo (anti-reuso del token en otro equipo) ---
    // `hwid` vacío = licencia no atada, permitido por el contrato §4.
    if (token.hwid.isNotEmpty) {
      String idLocal = '';
      try {
        idLocal = await _identidad.obtenerIdDispositivo();
      } catch (_) {
        idLocal = '';
      }

      if (idLocal.isEmpty ||
          token.hwid.toLowerCase() != idLocal.toLowerCase()) {
        return (
          EstadoLicencia.baseSegura(
            motivo: 'Esta licencia pertenece a otro dispositivo.',
            motivoDegradacion: MotivoDegradacion.otroDispositivo,
            relojSospechoso: relojSospechoso,
          ),
          false,
        );
      }
    }

    // --- 3) Expiración + grace period ---
    final DateTime ahora = await _reloj.ahoraUtc();
    final DateTime? expira = token.expiraUtc;
    bool enGracia = false;

    if (!token.esPerpetua && expira != null && ahora.isAfter(expira)) {
      final DateTime limiteGracia = expira.add(
        const Duration(days: RelojAuditado.diasGracia),
      );
      if (ahora.isAfter(limiteGracia)) {
        return (
          EstadoLicencia.baseSegura(
            motivo: 'La licencia expiró el ${_fechaCorta(expira)} y venció el '
                'periodo de gracia. Renueva para seguir usando tu plan.',
            motivoDegradacion: MotivoDegradacion.expirada,
            relojSospechoso: relojSospechoso,
          ),
          false,
        );
      }
      enGracia = true;
    }

    // --- 4) Token válido → estado con las features firmadas ---
    return (
      EstadoLicencia(
        esValida: true,
        estaActivada: true, // token auténtico instalado (incluye Base activada)
        tier: mapearTier(token.tier),
        featuresHabilitadas: token.features,
        expiraUtc: expira,
        enPeriodoGracia: enGracia,
        relojSospechoso: relojSospechoso,
        licenseId: token.licenseId,
        idDispositivoVinculado: token.hwid.isEmpty ? null : token.hwid,
        prefijoDispositivo: token.devicePrefix,
        idAsiento: token.deviceId,
        motivo: enGracia
            ? 'Licencia en periodo de gracia. Renueva para evitar cortes.'
            : (relojSospechoso
                ? 'La fecha del equipo cambió bruscamente. Conéctate a internet '
                    'para revalidar tu licencia.'
                : null),
      ),
      true,
    );
  }

  /// `dd/MM/yyyy` sin depender de `intl` (`pagoya_core` es Dart puro).
  static String _fechaCorta(DateTime utc) {
    final DateTime l = utc.toLocal();
    final String d = l.day.toString().padLeft(2, '0');
    final String m = l.month.toString().padLeft(2, '0');
    return '$d/$m/${l.year}';
  }
}
