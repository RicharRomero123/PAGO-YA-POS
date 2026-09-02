/// Contratos de la capa de sincronización en la nube de PagoYa Móvil.
///
/// Es el puerto Dart de `src/PagoYa.Core/Contratos/ISyncService.cs` y de
/// `src/PagoYa.Cloud/ISyncTransport.cs`. Los nombres de campo que viajan por el
/// cable son EXACTAMENTE los del backend existente
/// (`server/PagoYa.Api/Contratos/Dtos.cs`), serializados por ASP.NET Core con
/// `JsonSerializerDefaults.Web` — es decir **camelCase**:
///
///   POST /sync/push   { "eventos": [ EventoSyncDto... ] }
///        -> { "aceptados": [guid...], "entidadesDesconocidas": ["..."] }
///   GET  /sync/pull?cursor=<n>&origen=<origen_caja_id>
///        -> { "cambios": [...], "cursor": "<n>" }
///
/// Dart PURO: este archivo no puede importar `package:flutter/...`.
library;

import 'dart:convert';

// =============================================================================
//  Catálogo canónico de entidades sincronizables
// =============================================================================

/// Espejo Dart de `PagoYa.Api.Servicios.EntidadesSync.Catalogo`.
///
/// Contrato **cerrado**: escritorio (`OutboxStore.cs`), móvil
/// (`pagoya_core/lib/datos/`) y backend usan EXACTAMENTE estos nombres, en
/// snake_case y singular.
///
/// Divergir no rompe el push —el server almacena igual lo que no reconoce, para
/// no perder datos del cliente, y lo reporta en `entidadesDesconocidas`— pero sí
/// rompe la aplicación del cambio en el otro extremo: una `mesa` que la PC llama
/// `mesas` viaja, se guarda y no la aplica nadie.
class EntidadesSync {
  const EntidadesSync._();

  static const String producto = 'producto';
  static const String venta = 'venta';
  static const String caja = 'caja';
  static const String movimientoCaja = 'movimiento_caja';
  static const String inventario = 'inventario';

  /// Comandas: el caso de uso estrella del móvil (mozo tomando pedidos).
  static const String mesa = 'mesa';
  static const String pedido = 'pedido';
  static const String pedidoLinea = 'pedido_linea';

  /// Rubro hotel.
  static const String habitacion = 'habitacion';
  static const String estadiaHabitacion = 'estadia_habitacion';

  static const Set<String> catalogo = {
    producto,
    venta,
    caja,
    movimientoCaja,
    inventario,
    mesa,
    pedido,
    pedidoLinea,
    habitacion,
    estadiaHabitacion,
  };

  static bool esConocida(String? entidad) =>
      entidad != null && catalogo.contains(entidad.trim().toLowerCase());
}

/// Sumidero de diagnóstico del módulo de nube (entidades fuera de catálogo,
/// dispositivo revocado, lotes bisectados). Es una función y no un logger
/// concreto para no atar `pagoya_core` a ningún paquete de logging.
typedef RegistradorSync = void Function(String mensaje);

// =============================================================================
//  Códigos de error del backend
// =============================================================================

/// Códigos estables de `ErrorResponse.codigo` que afectan a `/sync/*`.
///
/// Espejo del subconjunto relevante de `PagoYa.Api.Contratos.CodigosError`;
/// tabla completa (25 códigos) en `server/README.md §10`.
///
/// Reglas del contrato publicado:
///   - `codigo` es **estable**: una vez publicado no cambia de significado ni
///     se recicla para otra condición. Si aparece una condición nueva, se
///     agrega un código nuevo.
///   - `error` es **texto para el usuario**: se reescribe, se acorta y algún
///     día se traduce. **Ningún cliente ramifica por su contenido.**
///   - El campo es **aditivo** (`WhenWritingNull`): un server viejo puede no
///     emitirlo, y por eso existe la ruta de compatibilidad en el transporte.
class CodigosErrorSync {
  const CodigosErrorSync._();

  /// 401: no llegó `Authorization: Bearer`.
  static const String tokenAusente = 'token_ausente';

  /// 401: formato, base64url, firma o payload inválidos → re-vincular.
  static const String tokenInvalido = 'token_invalido';

  /// 401: `exp` vencido → revalidar con `POST /validate`, NO re-vincular.
  /// Antes de que existiera `codigo` esto era indistinguible de `token_invalido`
  /// y mandábamos al dueño a re-activar una licencia que solo había que renovar.
  static const String tokenExpirado = 'token_expirado';

  /// 401: el `license_id` del token no es un GUID.
  static const String licenciaNoIdentificada = 'licencia_no_identificada';

  /// 403: el tier no habilita `cloud_sync` → camino de UPSELL.
  static const String sinFlagCloudSync = 'sin_flag_cloud_sync';

  /// 403: el `device_id` del token ya no está activo → "vuelve a vincular este
  /// equipo". Nada de upsell: esta licencia ya está pagada.
  static const String asientoRevocado = 'asiento_revocado';
}

/// Lee `ErrorResponse.codigo` de un cuerpo de error del backend.
///
/// Devuelve `null` cuando el campo no vino (server anterior al catálogo de §10,
/// o error todavía sin clasificar): ese `null` es la señal de que hay que caer
/// a la ruta de compatibilidad por texto, no un valor válido.
///
/// Vive aquí, y no en cada cliente HTTP, porque `/sync/*` y `/devices` tienen
/// que leerlo **idénticamente**: dos parseos parecidos divergen en cuanto uno
/// de los dos añade un `trim()` y el otro no.
String? leerCodigoErrorRemoto(Object? cuerpo) {
  if (cuerpo is! Map) return null;
  final codigo = cuerpo['codigo'];
  if (codigo == null) return null;
  final texto = codigo.toString().trim();
  return texto.isEmpty ? null : texto;
}

/// Lee `ErrorResponse.error`: el texto **para el usuario**. Se muestra, nunca
/// se parsea para decidir nada (salvo en las rutas de compatibilidad marcadas
/// como tales).
String leerMensajeErrorRemoto(Object? cuerpo) {
  if (cuerpo is Map && cuerpo['error'] != null) return cuerpo['error'].toString();
  return '';
}

// =============================================================================
//  Modelos de datos (espejo de EventoSyncLocal / CambioRemoto de C#)
// =============================================================================

/// Evento pendiente del outbox local listo para subir a la nube.
///
/// Espejo 1:1 de `PagoYa.Core.Contratos.EventoSyncLocal` y de la tabla
/// `outbox_sync` del `esquema.sql` compartido con el escritorio.
class EventoSyncLocal {
  const EventoSyncLocal({
    required this.id,
    required this.entidad,
    required this.entidadId,
    required this.operacion,
    required this.payloadJson,
    required this.intentos,
    required this.origenCajaId,
    required this.creadoUtc,
  });

  /// UUID del evento outbox. Es la clave de idempotencia del backend
  /// (`(licencia, id de evento del cliente)`).
  final String id;

  /// `'producto'` | `'venta'` | `'caja'` | `'movimiento_caja'` | `'inventario'`
  /// (y, cuando `backend-seats` amplíe ambos lados, `'mesa'` | `'pedido'` |
  /// `'pedido_linea'`).
  final String entidad;

  /// UUID de la fila afectada.
  final String entidadId;

  /// `'INSERT'` | `'UPDATE'` | `'DELETE'`.
  final String operacion;

  /// Snapshot serializado de la entidad (mismo formato que escribe el outbox
  /// del escritorio: PascalCase, con `ActualizadoUtc` cuando aplica).
  final String payloadJson;

  /// Intentos de envío ya acumulados (para el dead-letter).
  final int intentos;

  /// Identificador de la caja/dispositivo que originó el evento. Es la clave de
  /// la defensa contra eco: al bajar cambios ignoramos los que llevan el nuestro.
  final String origenCajaId;

  final DateTime creadoUtc;

  /// Serialización para `POST /sync/push`. Las claves son camelCase porque el
  /// backend usa `JsonSerializerDefaults.Web`.
  Map<String, dynamic> aJson() => {
        'id': id,
        'entidad': entidad,
        'entidadId': entidadId,
        'operacion': operacion,
        'payloadJson': payloadJson,
        'intentos': intentos,
        'origenCajaId': origenCajaId,
        'creadoUtc': creadoUtc.toUtc().toIso8601String(),
      };

  @override
  String toString() => 'EventoSyncLocal($entidad/$operacion $id)';
}

/// Cambio descargado de la nube para aplicar localmente.
///
/// [actualizadoUtc] es la marca del **last-write-wins**; [payloadJson] es el
/// snapshot de la entidad. Espejo de `CambioRemotoDto` del backend.
class CambioRemoto {
  const CambioRemoto({
    required this.entidad,
    required this.entidadId,
    required this.operacion,
    required this.payloadJson,
    required this.actualizadoUtc,
    required this.origenCajaId,
  });

  final String entidad;
  final String entidadId;
  final String operacion;
  final String payloadJson;
  final DateTime actualizadoUtc;
  final String origenCajaId;

  factory CambioRemoto.desdeJson(Map<String, dynamic> json) => CambioRemoto(
        entidad: (json['entidad'] ?? '') as String,
        entidadId: (json['entidadId'] ?? json['entidad_id'] ?? '') as String,
        operacion: (json['operacion'] ?? '') as String,
        payloadJson: _leerPayload(json['payloadJson'] ?? json['payload_json']),
        actualizadoUtc: _leerFecha(json['actualizadoUtc'] ?? json['actualizado_utc']),
        origenCajaId:
            (json['origenCajaId'] ?? json['origen_caja_id'] ?? '') as String,
      );

  /// El backend manda `payloadJson` como string. Si algún día lo mandara ya
  /// deserializado, lo re-serializamos para no romper a `flutter-datos`.
  static String _leerPayload(Object? valor) {
    if (valor == null) return '{}';
    if (valor is String) return valor;
    return jsonEncode(valor);
  }

  static DateTime _leerFecha(Object? valor) {
    if (valor is String) {
      final f = DateTime.tryParse(valor);
      if (f != null) return f.toUtc();
    }
    // Sin marca válida no podemos hacer LWW: epoch pierde siempre contra lo
    // local, que es el sesgo seguro (no pisamos datos buenos con basura).
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  String toString() => 'CambioRemoto($entidad/$operacion $entidadId de $origenCajaId)';
}

// =============================================================================
//  Transporte
// =============================================================================

/// Clasificación del fallo de transporte. Decide si se reintenta con backoff,
/// si se corta el ciclo o si el evento es candidato a dead-letter.
enum TipoFalloSync {
  /// Sin red / timeout / DNS. Reintentable.
  red,

  /// 401 `token_invalido` / `token_ausente` / `licencia_no_identificada`.
  /// El token no sirve y renovarlo no lo arregla: hay que re-vincular.
  autenticacion,

  /// 401 `token_expirado`: la licencia venció. Se arregla **renovando** con
  /// `POST /validate` (lo hace `flutter-licencia`), no re-vinculando. Como el
  /// token llega por `ProveedorToken`, en cuanto se renueve el siguiente ciclo
  /// funciona solo: por eso NO bloquea, solo espacia los reintentos.
  tokenExpirado,

  /// 403 con cuerpo "La licencia no habilita la sincronización en la nube":
  /// el token no trae el flag `cloud_sync`. Corta el ciclo y dispara el upsell
  /// del tier Cloud.
  sinPermiso,

  /// 403 con cuerpo "El dispositivo fue revocado para esta licencia": el
  /// asiento se dio de baja con `DELETE /devices/{id}` desde el panel admin.
  /// El token sigue siendo criptográficamente válido hasta `exp`, así que el
  /// cliente NO puede detectarlo solo: solo se sabe por esta respuesta.
  ///
  /// Es un mensaje distinto al anterior — "tu plan no incluye nube" y "este
  /// equipo fue desvinculado" se arreglan de formas distintas — y ninguno de
  /// los dos se reintenta en bucle.
  asientoRevocado,

  /// 4xx distinto de 401/403/429: el lote es inaceptable para el backend.
  /// NO reintentable tal cual — se bisecta para aislar el evento venenoso.
  rechazoPermanente,

  /// 429: rate limit. Reintentable con backoff.
  limite,

  /// 5xx: el servidor falló. Reintentable.
  servidor,

  /// Respuesta ilegible (JSON corrupto). No reintentable.
  respuestaInvalida,
}

/// Reintentable = tiene sentido esperar y volver a intentar el mismo lote.
bool esReintentable(TipoFalloSync tipo) =>
    tipo == TipoFalloSync.red ||
    tipo == TipoFalloSync.limite ||
    tipo == TipoFalloSync.servidor;

/// Resultado de subir un lote: ids aceptados o error de transporte.
///
/// Espejo de `ResultadoLote` de C#, con el tipo de fallo añadido porque en
/// móvil la política de reintento depende de él.
class ResultadoLote {
  const ResultadoLote({
    required this.ok,
    required this.aceptadosIds,
    this.error,
    this.tipoFallo,
    this.entidadesDesconocidas = const [],
  });

  final bool ok;
  final List<String> aceptadosIds;
  final String? error;
  final TipoFalloSync? tipoFallo;

  /// Entidades del lote que el backend no reconoce
  /// (`SyncPushResponse.EntidadesDesconocidas`). El server las almacena igual
  /// —nunca descarta datos del cliente— pero las reporta. Para nosotros es la
  /// **alarma temprana** de que los nombres de entidad divergieron entre la PC,
  /// el móvil y el backend: los eventos viajan, se guardan y no los aplica
  /// nadie. Se registra en el log; no se trata como error.
  final List<String> entidadesDesconocidas;

  factory ResultadoLote.exito(List<String> ids,
          {List<String> entidadesDesconocidas = const []}) =>
      ResultadoLote(
          ok: true,
          aceptadosIds: ids,
          entidadesDesconocidas: entidadesDesconocidas);

  factory ResultadoLote.falla(TipoFalloSync tipo, String error) =>
      ResultadoLote(ok: false, aceptadosIds: const [], error: error, tipoFallo: tipo);
}

/// Cambios remotos descargados + cursor para la siguiente bajada.
class PaqueteRemoto {
  const PaqueteRemoto(this.cambios, this.cursor, {this.error, this.tipoFallo});

  final List<CambioRemoto> cambios;
  final String cursor;
  final String? error;
  final TipoFalloSync? tipoFallo;

  bool get ok => tipoFallo == null;

  factory PaqueteRemoto.falla(TipoFalloSync tipo, String error, String cursorActual) =>
      PaqueteRemoto(const [], cursorActual, error: error, tipoFallo: tipo);
}

/// Canal de transporte hacia el backend de sincronización.
///
/// Se abstrae para poder probar el motor sin red (ver
/// `test/nube/transporte_sync_en_memoria.dart`, espejo del
/// `TransporteSyncEnMemoria.cs` del escritorio) y para poder cambiar el
/// backend sin tocar el ciclo push/pull.
abstract class TransporteSync {
  /// Sube un lote de eventos del outbox. Devuelve qué ids aceptó el backend.
  /// Es **idempotente**: reenviar un id ya aceptado debe volver a aceptarlo.
  Future<ResultadoLote> enviarLote(List<EventoSyncLocal> lote);

  /// Descarga los cambios remotos posteriores a [cursor] (`null` = desde el
  /// inicio) y devuelve el nuevo cursor para la próxima bajada.
  Future<PaqueteRemoto> descargarCambios(String? cursor);

  /// Sonda barata para saber si hay internet REAL (no solo "hay wifi").
  /// Debe fallar suave: `false` en vez de excepción.
  Future<bool> hayInternet();

  /// Libera recursos del cliente HTTP.
  void cerrar() {}
}

// =============================================================================
//  Opciones
// =============================================================================

/// Parámetros del ciclo de sincronización. Espejo de `OpcionesSync` de C# más
/// lo que solo existe en móvil (origen, política de datos móviles, backoff).
class OpcionesSync {
  const OpcionesSync({
    required this.origenCajaId,
    this.urlBase,
    this.tokenLicencia,
    this.tamanoLote = 100,
    this.maxIntentos = 5,
    this.maxPorPull = 500,
    this.maxPaginasPull = 50,
    this.maxReintentosHttp = 3,
    this.backoffBase = const Duration(milliseconds: 500),
    this.backoffMaximo = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 20),
    this.permitirDatosMoviles = true,
    this.maxEventosEnDatosMoviles = 500,
  });

  /// Identificador de esta caja/dispositivo (`M01`..`M99` en móvil, `C01`.. en
  /// escritorio).
  ///
  /// **Lo asigna el SERVER** al vincular el asiento con `POST /devices`: llega
  /// en la respuesta y en el claim `device_prefix` del token. El cliente lo
  /// **persiste**, no lo inventa — dos móviles generando su propio prefijo
  /// colisionan en los correlativos y rompen el filtro de eco.
  ///
  /// Viaja en tres sitios y los tres tienen que coincidir carácter a carácter:
  ///   1. `origen_caja_id` de cada evento del outbox (push),
  ///   2. el parámetro `origen` del `GET /sync/pull` (filtro de eco server-side),
  ///   3. el prefijo del correlativo (`M01-000123`).
  final String origenCajaId;

  /// URL base del backend (p. ej. `https://api.pagoya.pe`).
  final String? urlBase;

  /// Token de licencia firmado. Va como `Authorization: Bearer <token>`.
  final String? tokenLicencia;

  /// Máximo de eventos por lote de subida.
  final int tamanoLote;

  /// Intentos por evento antes de moverlo a dead-letter.
  final int maxIntentos;

  /// Tope que aplica el backend por pull (`ServicioSync.MaxPorPull`).
  final int maxPorPull;

  /// Cota de páginas por ciclo, para que un pull enorme no monopolice la
  /// batería ni el hilo.
  final int maxPaginasPull;

  /// Reintentos HTTP (con backoff) dentro de una sola llamada.
  final int maxReintentosHttp;

  final Duration backoffBase;
  final Duration backoffMaximo;
  final Duration timeout;

  /// Si es `false`, en red móvil solo se sincroniza si el lote pendiente es
  /// pequeño (ver [maxEventosEnDatosMoviles]).
  final bool permitirDatosMoviles;

  /// Umbral de eventos por encima del cual NO se sincroniza en datos móviles
  /// sin permiso explícito del usuario.
  final int maxEventosEnDatosMoviles;

  OpcionesSync copiarCon({
    String? origenCajaId,
    String? urlBase,
    String? tokenLicencia,
    int? tamanoLote,
    int? maxIntentos,
    bool? permitirDatosMoviles,
    int? maxEventosEnDatosMoviles,
  }) =>
      OpcionesSync(
        origenCajaId: origenCajaId ?? this.origenCajaId,
        urlBase: urlBase ?? this.urlBase,
        tokenLicencia: tokenLicencia ?? this.tokenLicencia,
        tamanoLote: tamanoLote ?? this.tamanoLote,
        maxIntentos: maxIntentos ?? this.maxIntentos,
        maxPorPull: maxPorPull,
        maxPaginasPull: maxPaginasPull,
        maxReintentosHttp: maxReintentosHttp,
        backoffBase: backoffBase,
        backoffMaximo: backoffMaximo,
        timeout: timeout,
        permitirDatosMoviles: permitirDatosMoviles ?? this.permitirDatosMoviles,
        maxEventosEnDatosMoviles:
            maxEventosEnDatosMoviles ?? this.maxEventosEnDatosMoviles,
      );
}

// =============================================================================
//  Servicio
// =============================================================================

/// Motivo por el que un ciclo terminó sin éxito. Lo consume la pantalla de
/// estado de nube para decir algo útil en vez de "error".
enum MotivoFalloSync {
  ninguno,
  sinRed,

  /// El token no trae `cloud_sync`. Se arregla comprando el plan.
  sinPermisoCloud,

  /// El asiento de este dispositivo fue revocado desde el panel admin. Se
  /// arregla volviendo a vincular el equipo, NO comprando nada.
  dispositivoRevocado,

  /// El token no es válido (firma, formato, licencia no identificada). Se
  /// arregla re-activando/re-vinculando el equipo.
  tokenInvalido,

  /// La licencia venció. Se arregla **renovando** (`POST /validate`), que es
  /// otra conversación —y otro precio— que re-vincular un equipo.
  tokenExpirado,

  servidor,
  datosMovilesBloqueados,
  eventosRechazados,
  desconocido,
}

/// Motivos que NO mejoran reintentando: hace falta que **una persona** haga
/// algo (comprar el plan, re-vincular el equipo). El planificador deja de
/// programar ciclos mientras uno de estos esté activo.
///
/// `tokenExpirado` NO está aquí a propósito: lo arregla otro módulo
/// (`RevalidadorLicencia`) sin intervención del dueño, y como el token se lee
/// por `ProveedorToken` en cada llamada, el siguiente reintento con backoff lo
/// recoge solo. Bloquear ahí dejaría la nube muerta hasta que alguien entrara
/// a la pantalla a pulsar un botón.
bool esMotivoBloqueante(MotivoFalloSync motivo) =>
    motivo == MotivoFalloSync.sinPermisoCloud ||
    motivo == MotivoFalloSync.dispositivoRevocado ||
    motivo == MotivoFalloSync.tokenInvalido;

/// Resumen del resultado de un ciclo de sincronización.
/// Espejo de `ResultadoSync` de C#.
class ResultadoSync {
  const ResultadoSync({
    required this.exito,
    this.enviados = 0,
    this.recibidos = 0,
    this.ignoradosPorEco = 0,
    this.enviadosADeadLetter = 0,
    this.entidadesDesconocidas = const {},
    this.mensaje,
    this.motivo = MotivoFalloSync.ninguno,
  });

  final bool exito;
  final int enviados;
  final int recibidos;

  /// Entidades que el backend no reconoció en este ciclo. Alarma de
  /// desalineación de contrato entre PC, móvil y backend.
  final Set<String> entidadesDesconocidas;

  /// Cambios que el server devolvió pero que originó este mismo dispositivo.
  /// Debería tender a 0 cuando `backend-seats` active el filtro server-side.
  final int ignoradosPorEco;

  final int enviadosADeadLetter;
  final String? mensaje;
  final MotivoFalloSync motivo;

  /// Resultado que indica que la sync no está habilitada por licencia.
  factory ResultadoSync.noHabilitado() => const ResultadoSync(
        exito: false,
        mensaje: 'El respaldo en la nube requiere el plan PagoYa Cloud.',
        motivo: MotivoFalloSync.sinPermisoCloud,
      );
}

/// Foto del estado de la nube para la UI. Es lo que le permite al dueño
/// responder "¿ya se subió mi venta?" sin llamar a soporte.
class EstadoNube {
  const EstadoNube({
    this.habilitada = false,
    this.sincronizando = false,
    this.ultimaSyncUtc,
    this.ultimaSyncExitosa = false,
    this.pendientes = 0,
    this.enDeadLetter = 0,
    this.entidadesDesconocidas = const {},
    this.mensaje,
    this.motivo = MotivoFalloSync.ninguno,
  });

  /// `false` => Null Object: el token no trae `cloud_sync`. La pantalla muestra
  /// el upsell del tier Cloud.
  final bool habilitada;

  final bool sincronizando;
  final DateTime? ultimaSyncUtc;
  final bool ultimaSyncExitosa;

  /// Eventos en el outbox esperando subir.
  final int pendientes;

  /// Eventos que superaron `maxIntentos` y quedaron apartados para no bloquear
  /// la cola. Requieren mirada de soporte.
  final int enDeadLetter;

  /// Entidades que el backend no reconoció en el último push. Si esto no está
  /// vacío, hay una divergencia de contrato que arreglar entre PC, móvil y
  /// backend; no se le enseña al dueño de la bodega, va al log y a soporte.
  final Set<String> entidadesDesconocidas;

  final String? mensaje;
  final MotivoFalloSync motivo;

  /// `true` si todo lo local ya está en la nube.
  bool get alDia => habilitada && pendientes == 0 && ultimaSyncExitosa;

  /// `true` si hace falta una acción humana (comprar el plan, re-vincular el
  /// equipo). La pantalla lo pinta como aviso grave y el planificador deja de
  /// programar ciclos.
  bool get requiereAccion => esMotivoBloqueante(motivo);

  EstadoNube copiarCon({
    bool? habilitada,
    bool? sincronizando,
    DateTime? ultimaSyncUtc,
    bool? ultimaSyncExitosa,
    int? pendientes,
    int? enDeadLetter,
    Set<String>? entidadesDesconocidas,
    String? mensaje,
    MotivoFalloSync? motivo,
  }) =>
      EstadoNube(
        habilitada: habilitada ?? this.habilitada,
        sincronizando: sincronizando ?? this.sincronizando,
        ultimaSyncUtc: ultimaSyncUtc ?? this.ultimaSyncUtc,
        ultimaSyncExitosa: ultimaSyncExitosa ?? this.ultimaSyncExitosa,
        pendientes: pendientes ?? this.pendientes,
        enDeadLetter: enDeadLetter ?? this.enDeadLetter,
        entidadesDesconocidas:
            entidadesDesconocidas ?? this.entidadesDesconocidas,
        mensaje: mensaje ?? this.mensaje,
        motivo: motivo ?? this.motivo,
      );
}

/// Servicio de sincronización con la nube (outbox pattern).
///
/// FEATURE-GATED por el flag `cloud_sync` del token firmado. Sin él se usa el
/// Null Object [ServicioSyncDeshabilitado].
///
/// REGLA CRÍTICA: ningún método de esta interfaz lanza por fallo de red. La
/// venta ya está en SQLite; la nube es eventual por diseño. Un `catch` olvidado
/// en la UI de cobro no puede convertirse en un cobro perdido.
abstract class ServicioSync {
  /// `true` si la licencia habilita la sincronización.
  bool get sincronizacionHabilitada;

  /// Estado observable para la pantalla de nube.
  Stream<EstadoNube> get estado;

  /// Último estado conocido (sin esperar al stream).
  EstadoNube get estadoActual;

  /// Ejecuta un ciclo completo push + pull. **Nunca lanza** por fallo de red:
  /// devuelve un [ResultadoSync] con `exito: false`.
  Future<ResultadoSync> sincronizar();

  /// Refresca los contadores (pendientes / dead-letter) sin tocar la red.
  Future<void> refrescarContadores();

  Future<void> liberar();
}
