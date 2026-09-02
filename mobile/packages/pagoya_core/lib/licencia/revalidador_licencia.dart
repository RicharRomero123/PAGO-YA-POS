/// Revalidación **silenciosa** de la licencia contra el backend de asientos.
///
/// `docs/SEGURIDAD.md` §1 es explícito: un APK se decompila mucho más fácil que
/// un WPF, así que el gate offline es una **barrera comercial, no
/// criptográfica**. Lo que sostiene el ingreso recurrente es (a) que Cloud y
/// Facturación vivan en el backend y (b) esta revalidación online periódica.
/// Aquí está (b).
///
/// ## Cómo se renueva un token de asiento
///
/// `POST /devices` es **idempotente por `deviceId`** (`server/README.md` §4):
/// re-vincular el mismo dispositivo re-emite el token con `iat`/`exp` frescos
/// **sin consumir otro cupo de `MaxDispositivos`**. Por eso la renovación usa
/// [ServicioDispositivos.vincular] y no `/validate`: `/validate` es la puerta
/// del equipo **principal** y compara contra `HwidActual`; si el móvil la
/// usara, respondería `409`.
///
/// ## Reglas de oro
///
/// - **Nunca bloquea al negocio en caliente.** Un fallo de red no degrada nada:
///   el token firmado que ya está en el dispositivo manda hasta que caduque su
///   `exp` más los 7 días de gracia.
/// - Corre en segundo plano, sin diálogos ni spinners bloqueantes.
/// - Con throttling en `meta`, para no chocar con el rate limit del server
///   (10 req/min en los endpoints de licencia).
/// - **No inventa un estado de "revocado".** Offline es imposible saberlo: un
///   asiento revocado sigue validando criptográficamente hasta su `exp`, y lo
///   que se corta de inmediato es `/sync/*` (que responde `403`) y la re-emisión
///   de tokens. Ese aviso lo pinta la capa de nube, no esta.
library;

import '../nube/contratos.dart';
import 'almacen_licencia.dart';
import 'codigos_error_licencia.dart';
import 'estado_licencia.dart';
import 'meta_licencia.dart';
import 'puertos_licencia.dart';
import 'servicio_licencia.dart';

/// Qué pasó en un intento de revalidación. La UI puede ignorarlo casi siempre.
enum ResultadoRevalidacion {
  /// No tocaba revalidar todavía (throttling, o token lejos de expirar).
  omitida,

  /// No hay clave de licencia guardada: este dispositivo se activó pegando el
  /// token a mano. Para renovar solo hay que pedirle la clave al usuario una vez.
  sinClaveLicencia,

  /// Token renovado y persistido.
  renovada,

  /// Falló por red, timeout o 5xx. Se reintentará; no se degrada nada.
  falloTransitorio,

  /// El backend rechazó la renovación (clave inexistente, licencia suspendida,
  /// asiento revocado). Ver la nota de diseño de [revalidarSiCorresponde].
  rechazada,
}

/// Decide cuándo revalidar y lo hace.
final class RevalidadorLicencia {
  /// Cuánto antes de `exp` se empieza a intentar la renovación.
  static const Duration anticipacion = Duration(days: 3);

  /// Intervalo mínimo entre intentos en condiciones normales.
  static const Duration intervaloNormal = Duration(hours: 6);

  /// Intervalo mínimo cuando urge: en gracia, o con el reloj sospechoso.
  static const Duration intervaloUrgente = Duration(hours: 1);

  /// Cada cuánto se revalida una licencia **perpetua** (tier Base). No expira
  /// nunca, pero revalidar de vez en cuando es lo que permite enterarse de una
  /// licencia suspendida o de un asiento revocado desde el panel admin.
  static const Duration intervaloPerpetua = Duration(days: 30);

  final ServicioLicencia _servicio;
  final ServicioDispositivos _dispositivos;
  final IdentidadDispositivo _identidad;
  final AlmacenLicenciaSegura _almacen;
  final MetaLicencia _meta;
  final RelojAuditado _reloj;

  const RevalidadorLicencia({
    required ServicioLicencia servicio,
    required ServicioDispositivos dispositivos,
    required IdentidadDispositivo identidad,
    required AlmacenLicenciaSegura almacen,
    required MetaLicencia meta,
    required RelojAuditado reloj,
  })  : _servicio = servicio,
        _dispositivos = dispositivos,
        _identidad = identidad,
        _almacen = almacen,
        _meta = meta,
        _reloj = reloj;

  /// True si toca intentar una revalidación ahora.
  ///
  /// Puro y sin efectos: se testea sin red ni base de datos.
  static bool debeRevalidar({
    required EstadoLicencia estado,
    required DateTime ahoraUtc,
    required DateTime? ultimoIntentoUtc,
  }) {
    // Sin token auténtico no hay nada que revalidar: de eso se encarga el gate
    // de activación.
    if (!estado.estaActivada) return false;

    final DateTime? expira = estado.expiraUtc;
    final bool urgente = estado.enPeriodoGracia || estado.relojSospechoso;

    final Duration intervalo;
    if (urgente) {
      intervalo = intervaloUrgente;
    } else if (expira == null) {
      intervalo = intervaloPerpetua;
    } else if (ahoraUtc.isAfter(expira.subtract(anticipacion))) {
      intervalo = intervaloNormal;
    } else {
      // Suscripción lejos de expirar y nada sospechoso: no se molesta al
      // servidor ni se gasta batería y datos del cliente.
      return false;
    }

    if (ultimoIntentoUtc == null) return true;
    return ahoraUtc.difference(ultimoIntentoUtc) >= intervalo;
  }

  /// Intenta renovar el token si corresponde. **No lanza nunca.**
  ///
  /// NOTA DE DISEÑO: ante un rechazo del backend (`404` clave inexistente,
  /// `409` licencia suspendida o asiento revocado) este método **no degrada**
  /// la licencia local. Motivos:
  ///
  /// 1. El escritorio tampoco lo hace, y la paridad importa.
  /// 2. La app es offline-primero: un rechazo puede venir de un despliegue a
  ///    medias o de un cambio de clave hecho por soporte.
  /// 3. `server/README.md` lo dice explícitamente: un token ya emitido sigue
  ///    siendo válido hasta su `exp`; la revocación corta la **re-emisión** y
  ///    `/sync/*`, no la validación offline.
  ///
  /// Los tokens de suscripción son de corta duración, así que la revocación se
  /// hace efectiva sola en días. Para el corte inmediato de una licencia
  /// perpetua está la suspensión desde el panel admin.
  Future<ResultadoRevalidacion> revalidarSiCorresponde({
    bool forzar = false,
  }) async {
    final DateTime ahora = await _reloj.ahoraUtc();

    if (!forzar) {
      final DateTime? ultimo = await _meta.leerFecha(
        ClavesMetaLicencia.ultimaRevalidacionUtc,
      );
      final bool toca = debeRevalidar(
        estado: _servicio.estadoActual,
        ahoraUtc: ahora,
        ultimoIntentoUtc: ultimo,
      );
      if (!toca) return ResultadoRevalidacion.omitida;
    }

    final String? clave = await _leerClaveSegura();
    if (clave == null || clave.isEmpty) {
      return ResultadoRevalidacion.sinClaveLicencia;
    }

    // El intento se registra ANTES de la llamada: si la app muere a mitad, el
    // throttling sigue valiendo y no se entra en un bucle de reintentos.
    await _meta.escribirFecha(ClavesMetaLicencia.ultimaRevalidacionUtc, ahora);

    final String idDispositivo;
    final String nombre;
    final String plataforma;
    try {
      idDispositivo = await _identidad.obtenerIdDispositivo();
      nombre = await _identidad.obtenerNombreDispositivo();
      plataforma = await _identidad.obtenerPlataforma();
    } catch (_) {
      return ResultadoRevalidacion.falloTransitorio;
    }

    final ResultadoVinculacion resultado;
    try {
      // Idempotente por `deviceId`: re-emite el token sin consumir otro cupo.
      resultado = await _dispositivos.vincular(
        tokenLicencia: clave,
        idDispositivo: idDispositivo,
        nombreDispositivo: nombre,
        plataforma: plataforma,
      );
    } catch (_) {
      // `flutter-sync` LANZA en el camino de red (sin señal, timeout, 5xx) y
      // DEVUELVE resultado con código en los 4xx. Traducir la excepción a
      // `falloTransitorio` aquí es lo que evita tratar una bodega sin señal
      // como una licencia rechazada. El catch es amplio a propósito: cualquier
      // throw del transporte significa "no llegamos al backend".
      return ResultadoRevalidacion.falloTransitorio;
    }

    final String? tokenNuevo = resultado.tokenFirmado;
    if (!resultado.exito || tokenNuevo == null || tokenNuevo.trim().isEmpty) {
      // Se ramifica por el código estable de `ErrorResponse.codigo`
      // (server/README.md §10), no por el texto del mensaje.
      final MotivoFalloVinculacion motivo = clasificarFalloVinculacion(
        codigo: codigoDeVinculacion(resultado),
        mensaje: resultado.mensaje,
      );
      return motivo.esTransitorio
          ? ResultadoRevalidacion.falloTransitorio
          : ResultadoRevalidacion.rechazada;
    }

    // `activarLicencia` vuelve a verificar la firma antes de guardar: nunca se
    // persiste algo solo porque venga del servidor.
    await _servicio.activarLicencia(tokenNuevo);
    return ResultadoRevalidacion.renovada;
  }

  Future<String?> _leerClaveSegura() async {
    try {
      return (await _almacen.leerClaveLicencia())?.trim();
    } catch (_) {
      return null;
    }
  }
}
