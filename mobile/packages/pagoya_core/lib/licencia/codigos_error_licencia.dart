/// Códigos estables de `ErrorResponse.codigo` que afectan al licenciamiento.
///
/// Espejo del subconjunto relevante de `PagoYa.Api.Contratos.CodigosError`;
/// tabla completa (25 códigos) en `server/README.md §10`. Es el mismo patrón que
/// `CodigosErrorSync` en `nube/contratos_sync.dart`, para el lado de
/// `/devices`, `/activate` y `/validate`.
///
/// Reglas del contrato publicado:
///   - `codigo` es **estable**: una vez publicado no cambia de significado ni se
///     recicla. Si aparece una condición nueva, se agrega un código nuevo.
///   - `error` es **texto para el usuario**: se reescribe, se acorta y algún día
///     se traduce. **Ningún cliente ramifica por su contenido.**
///   - El campo es **aditivo** (`WhenWritingNull`): un server viejo puede no
///     emitirlo, y por eso existe la ruta de compatibilidad de más abajo.
library;

import '../nube/contratos.dart';

/// Constantes del catálogo, para el lado de licencias y asientos.
class CodigosErrorLicencia {
  const CodigosErrorLicencia._();

  /// 404: la clave de licencia no existe (típicamente, la escribió mal).
  static const String claveNoEncontrada = 'clave_no_encontrada';

  /// 409: suspendida por soporte o impago.
  static const String licenciaSuspendida = 'licencia_suspendida';

  /// 409: revocada permanentemente.
  static const String licenciaRevocada = 'licencia_revocada';

  /// 409: `MaxDispositivos` agotado → revocar un asiento o subir de plan.
  static const String cupoDispositivosLleno = 'cupo_dispositivos_lleno';

  /// 409: ese id ya es el equipo **principal**; se vincula con `/activate`.
  static const String dispositivoYaEsPrincipal = 'dispositivo_ya_es_principal';

  /// 409: se usaron los 99 prefijos (`M01..M99`) de esa familia.
  static const String prefijosAgotados = 'prefijos_agotados';

  /// 400: falta `deviceId` en la petición. Es un bug del cliente.
  static const String deviceIdRequerido = 'device_id_requerido';

  /// 401: `exp` vencido → **renovar**, NO re-vincular.
  ///
  /// Antes de que existiera `codigo` esto era indistinguible de
  /// [tokenInvalido] y mandábamos al dueño a re-activar una licencia que solo
  /// había que renovar.
  static const String tokenExpirado = 'token_expirado';

  /// 401: formato, base64url, firma o payload inválidos → re-vincular.
  static const String tokenInvalido = 'token_invalido';

  /// 403: el `device_id` del token ya no está activo → re-vincular este equipo.
  static const String asientoRevocado = 'asiento_revocado';
}

/// Qué le pasó a la vinculación, ya clasificado. La UI ramifica por esto, nunca
/// por el texto del backend.
enum MotivoFalloVinculacion {
  /// La clave no existe: el dueño la escribió mal o le dieron otra.
  claveNoEncontrada,

  /// Licencia suspendida por impago o por soporte.
  licenciaSuspendida,

  /// Licencia revocada permanentemente.
  licenciaRevocada,

  /// Se acabaron los asientos del plan. **Es una oportunidad de venta**, no un
  /// callejón sin salida: subir de plan o liberar un asiento.
  cupoDispositivosLleno,

  /// El id ya es el equipo principal: hay que usar `/activate`, no `/devices`.
  /// Pasa cuando alguien intenta "añadir" la PC que ya es la caja.
  yaEsDispositivoPrincipal,

  /// No quedan prefijos `M01..M99` libres en esa licencia.
  prefijosAgotados,

  /// El token venció: hay que **renovar**, no volver a activar.
  tokenExpirado,

  /// El token no es válido (firma, formato) o el asiento fue revocado:
  /// hay que **re-vincular** el equipo.
  tokenInvalido,

  /// Fallo de red, timeout o 5xx: se reintenta, no se degrada nada.
  red,

  /// Cualquier otra cosa, incluido un código nuevo que este cliente aún no
  /// conoce. Se muestra el texto del backend tal cual.
  desconocido;

  /// `true` si el dueño no puede resolverlo solo y conviene ofrecerle el botón
  /// de WhatsApp con sus datos ya copiados.
  bool get requiereSoporte => switch (this) {
        MotivoFalloVinculacion.licenciaSuspendida ||
        MotivoFalloVinculacion.licenciaRevocada ||
        MotivoFalloVinculacion.cupoDispositivosLleno ||
        MotivoFalloVinculacion.prefijosAgotados =>
          true,
        _ => false,
      };

  /// `true` si reintentar más tarde tiene sentido (no hace falta molestar al
  /// usuario ni a soporte).
  bool get esTransitorio => this == MotivoFalloVinculacion.red;
}

/// Código estable de error que trae un [ResultadoVinculacion].
///
/// `flutter-sync` lo rellena en su implementación HTTP desde `cuerpo['codigo']`,
/// igual que `transporte_http_sync._codigoError`. Es `null` en éxito y también
/// cuando responde un backend anterior al catálogo de `server/README.md §10`
/// —solo en ese segundo caso se llega a [_compatibilidadPorTexto].
///
/// Existe como función y no como acceso directo para que el punto de lectura
/// sea uno solo: si el contrato cambia de nombre de campo, se toca aquí.
String? codigoDeVinculacion(ResultadoVinculacion respuesta) => respuesta.codigo;

/// Clasifica un fallo de `POST /devices`.
///
/// **Ramifica por [codigo] primero.** [mensaje] solo se mira cuando el server no
/// mandó código, y ese camino es de compatibilidad (ver más abajo).
MotivoFalloVinculacion clasificarFalloVinculacion({
  String? codigo,
  String? mensaje,
}) {
  final String? c = codigo?.trim();
  if (c != null && c.isNotEmpty) {
    return switch (c) {
      CodigosErrorLicencia.claveNoEncontrada =>
        MotivoFalloVinculacion.claveNoEncontrada,
      CodigosErrorLicencia.licenciaSuspendida =>
        MotivoFalloVinculacion.licenciaSuspendida,
      CodigosErrorLicencia.licenciaRevocada =>
        MotivoFalloVinculacion.licenciaRevocada,
      CodigosErrorLicencia.cupoDispositivosLleno =>
        MotivoFalloVinculacion.cupoDispositivosLleno,
      CodigosErrorLicencia.dispositivoYaEsPrincipal =>
        MotivoFalloVinculacion.yaEsDispositivoPrincipal,
      CodigosErrorLicencia.prefijosAgotados =>
        MotivoFalloVinculacion.prefijosAgotados,
      CodigosErrorLicencia.tokenExpirado => MotivoFalloVinculacion.tokenExpirado,
      CodigosErrorLicencia.tokenInvalido ||
      CodigosErrorLicencia.asientoRevocado ||
      CodigosErrorLicencia.deviceIdRequerido =>
        MotivoFalloVinculacion.tokenInvalido,
      // Un código del catálogo que este cliente todavía no conoce: se respeta
      // el texto del backend en vez de adivinar.
      _ => MotivoFalloVinculacion.desconocido,
    };
  }

  return _compatibilidadPorTexto(mensaje);
}

// --- Compatibilidad con servers anteriores al campo `codigo` -----------------
//
// RUTA DE COMPATIBILIDAD, no el camino normal. `codigo` es aditivo
// (`WhenWritingNull`), así que una instalación con un backend viejo sigue
// mandando solo `error`. Esta función es lo único que queda parseando texto, y
// solo se alcanza cuando `codigo` no vino. Se puede borrar cuando todas las
// instalaciones desplegadas emitan el catálogo de `server/README.md §10`.
//
// Es deliberadamente conservadora: ante la duda devuelve `desconocido`, que
// muestra el texto del backend sin inventar una acción.
MotivoFalloVinculacion _compatibilidadPorTexto(String? mensaje) {
  final String texto = (mensaje ?? '').toLowerCase();
  if (texto.isEmpty) return MotivoFalloVinculacion.desconocido;

  if (texto.contains('dispositivo') ||
      texto.contains('cupo') ||
      texto.contains('límite') ||
      texto.contains('limite')) {
    return MotivoFalloVinculacion.cupoDispositivosLleno;
  }
  if (texto.contains('suspend')) return MotivoFalloVinculacion.licenciaSuspendida;
  if (texto.contains('revoc')) return MotivoFalloVinculacion.licenciaRevocada;
  if (texto.contains('expir') || texto.contains('vencid')) {
    return MotivoFalloVinculacion.tokenExpirado;
  }
  if (texto.contains('no encontrad') || texto.contains('no existe')) {
    return MotivoFalloVinculacion.claveNoEncontrada;
  }
  return MotivoFalloVinculacion.desconocido;
}

/// Texto para el usuario según el motivo, cuando el backend no mandó uno útil.
///
/// El del backend gana siempre que exista: es el que soporte puede reescribir
/// sin desplegar la app.
String mensajePorDefectoDe(MotivoFalloVinculacion motivo) => switch (motivo) {
      MotivoFalloVinculacion.claveNoEncontrada =>
        'Esa clave de licencia no existe. Revísala e inténtalo de nuevo.',
      MotivoFalloVinculacion.licenciaSuspendida =>
        'Tu licencia está suspendida. Escríbenos por WhatsApp y la reactivamos.',
      MotivoFalloVinculacion.licenciaRevocada =>
        'Tu licencia fue dada de baja. Escríbenos por WhatsApp.',
      MotivoFalloVinculacion.cupoDispositivosLleno =>
        'Ya usaste todos los dispositivos de tu plan. Libera uno o súbete de '
            'plan y activas este celular al toque.',
      MotivoFalloVinculacion.yaEsDispositivoPrincipal =>
        'Este equipo ya es tu caja principal, así que no hace falta añadirlo '
            'como dispositivo extra.',
      MotivoFalloVinculacion.prefijosAgotados =>
        'Tu licencia llegó al máximo de dispositivos registrados '
            'históricamente. Escríbenos por WhatsApp y lo liberamos.',
      MotivoFalloVinculacion.tokenExpirado =>
        'Tu plan venció. Renuévalo y este celular se reactiva solo.',
      MotivoFalloVinculacion.tokenInvalido =>
        'Hay que volver a vincular este celular. Escribe tu clave de licencia '
            'de nuevo.',
      MotivoFalloVinculacion.red =>
        'No hay conexión con el servidor de licencias. Revisa tu internet, o '
            'activa sin internet pegando el token que te enviamos.',
      MotivoFalloVinculacion.desconocido =>
        'No se pudo vincular este dispositivo.',
    };
