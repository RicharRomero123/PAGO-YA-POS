/// Transporte HTTP/JSON real contra el backend de sincronización existente.
///
/// Porta `src/PagoYa.Cloud/HttpSyncTransport.cs` a dio, añadiendo lo que el
/// móvil sí necesita: interceptor del Bearer (para que el token se pueda rotar
/// sin recrear el cliente), backoff exponencial con jitter y una taxonomía de
/// fallos que distingue "no hay red" de "el backend rechazó el lote".
///
/// Endpoints (NO se rediseñan, ya existen en `server/PagoYa.Api/Program.cs`):
///   POST /sync/push   { "eventos": [...] }
///        -> 200 { "aceptados": [ids], "entidadesDesconocidas": [...] }
///   GET  /sync/pull?cursor=<n>&origen=<origen_caja_id>
///        -> 200 { "cambios": [...], "cursor": "<n>" }
/// Los errores se ramifican por `ErrorResponse.codigo` (catálogo estable de 25
/// códigos, `server/README.md §10`), **nunca** por el texto de `error`:
///   401 `token_expirado`      -> revalidar con POST /validate
///   401 `token_invalido` / `token_ausente` / `licencia_no_identificada`
///                             -> re-vincular el equipo
///   403 `sin_flag_cloud_sync` -> upsell al tier Cloud
///   403 `asiento_revocado`    -> "vuelve a vincular este equipo"
///
/// Dart PURO: `dio` no depende de Flutter, así que puede vivir en `pagoya_core`.
library;

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import 'contratos_sync.dart';

/// Proveedor del token de licencia. Es una función y no un string para que la
/// rotación del token (renovación silenciosa vía `/validate`) no obligue a
/// reconstruir el transporte.
typedef ProveedorToken = String? Function();

class TransporteHttpSync implements TransporteSync {
  TransporteHttpSync({
    required OpcionesSync opciones,
    ProveedorToken? proveedorToken,
    Dio? dio,
    Random? aleatorio,
  })  : _opciones = opciones,
        _proveedorToken = proveedorToken ?? (() => opciones.tokenLicencia),
        _rnd = aleatorio ?? Random(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _normalizarBase(opciones.urlBase),
              connectTimeout: opciones.timeout,
              receiveTimeout: opciones.timeout,
              sendTimeout: opciones.timeout,
              responseType: ResponseType.json,
              // Nosotros clasificamos los códigos; dio no debe lanzar por 4xx.
              validateStatus: (_) => true,
              headers: const {'Content-Type': 'application/json'},
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _proveedorToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;
  final OpcionesSync _opciones;
  final ProveedorToken _proveedorToken;
  final Random _rnd;

  static String _normalizarBase(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final limpia = url.trim();
    return limpia.endsWith('/') ? limpia : '$limpia/';
  }

  // ===========================================================================
  //  PUSH
  // ===========================================================================

  @override
  Future<ResultadoLote> enviarLote(List<EventoSyncLocal> lote) async {
    if (lote.isEmpty) return ResultadoLote.exito(const []);

    return _conBackoff<ResultadoLote>(
      operacion: () async {
        final resp = await _dio.post<dynamic>(
          'sync/push',
          data: {'eventos': lote.map((e) => e.aJson()).toList()},
        );

        final fallo = _clasificar(resp.statusCode, resp.data);
        if (fallo != null) {
          return ResultadoLote.falla(
              fallo, 'push HTTP ${resp.statusCode}: ${_mensajeError(resp.data)}');
        }

        final datos = resp.data;
        if (datos is! Map) {
          return ResultadoLote.falla(
              TipoFalloSync.respuestaInvalida, 'push: respuesta no es un objeto JSON');
        }
        final crudos = datos['aceptados'];
        if (crudos is! List) {
          // 200 sin `aceptados` legible: no podemos marcar nada como enviado.
          // Reenviaremos; el backend es idempotente por (licencia, id).
          return ResultadoLote.falla(
              TipoFalloSync.respuestaInvalida, 'push: falta el arreglo "aceptados"');
        }

        final desconocidas = datos['entidadesDesconocidas'];
        return ResultadoLote.exito(
          crudos.map((e) => e.toString().toLowerCase()).toList(growable: false),
          entidadesDesconocidas: desconocidas is List
              ? desconocidas.map((e) => e.toString()).toList(growable: false)
              : const [],
        );
      },
      enFalloDeRed: (mensaje) =>
          ResultadoLote.falla(TipoFalloSync.red, 'push: $mensaje'),
      esReintentableResultado: (r) => !r.ok && esReintentable(r.tipoFallo!),
    );
  }

  // ===========================================================================
  //  PULL
  // ===========================================================================

  @override
  Future<PaqueteRemoto> descargarCambios(String? cursor) async {
    final cursorActual = cursor ?? '0';

    return _conBackoff<PaqueteRemoto>(
      operacion: () async {
        // `origen` = nuestro origen_caja_id, IDÉNTICO al que estampamos en el
        // push. Con él, el server no nos devuelve nuestros propios eventos
        // (filtro de eco). Si lo omitiéramos, el backend caería al claim
        // `device_prefix` del token y, sin ese claim, no filtraría nada: por eso
        // se manda siempre explícito.
        final query = <String, dynamic>{};
        if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
        final origen = _opciones.origenCajaId.trim();
        if (origen.isNotEmpty) query['origen'] = origen;

        final resp = await _dio.get<dynamic>(
          'sync/pull',
          queryParameters: query.isEmpty ? null : query,
        );

        final fallo = _clasificar(resp.statusCode, resp.data);
        if (fallo != null) {
          return PaqueteRemoto.falla(fallo,
              'pull HTTP ${resp.statusCode}: ${_mensajeError(resp.data)}', cursorActual);
        }

        final datos = resp.data;
        if (datos is! Map) {
          return PaqueteRemoto.falla(TipoFalloSync.respuestaInvalida,
              'pull: respuesta no es un objeto JSON', cursorActual);
        }

        final crudos = datos['cambios'];
        final cambios = <CambioRemoto>[];
        if (crudos is List) {
          for (final c in crudos) {
            if (c is Map) {
              cambios.add(CambioRemoto.desdeJson(Map<String, dynamic>.from(c)));
            }
          }
        }
        // El backend devuelve el cursor como string; toleramos que venga número.
        final nuevoCursor = datos['cursor']?.toString();
        return PaqueteRemoto(
          cambios,
          (nuevoCursor == null || nuevoCursor.isEmpty) ? cursorActual : nuevoCursor,
        );
      },
      enFalloDeRed: (mensaje) =>
          PaqueteRemoto.falla(TipoFalloSync.red, 'pull: $mensaje', cursorActual),
      esReintentableResultado: (p) => !p.ok && esReintentable(p.tipoFallo!),
    );
  }

  // ===========================================================================
  //  Sonda de internet real
  // ===========================================================================

  /// `connectivity_plus` dice que hay wifi, no que haya internet: el wifi del
  /// mercado con portal cautivo responde ARP y nada más. Aquí pegamos al
  /// `/health` del propio backend, que es el único "internet" que nos importa.
  ///
  /// Falla suave por contrato: devuelve `false`, nunca lanza.
  @override
  Future<bool> hayInternet() async {
    try {
      final resp = await _dio.get<dynamic>(
        'health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
        ),
      );
      final codigo = resp.statusCode ?? 0;
      // Cualquier respuesta HTTP legítima del backend prueba que hay ruta.
      // Un portal cautivo suele devolver 200 con HTML: exigimos que el cuerpo
      // sea el JSON del health.
      if (codigo >= 200 && codigo < 500) {
        final d = resp.data;
        if (d is Map && d.containsKey('estado')) return true;
        return codigo == 401 || codigo == 403; // llegó al backend y nos rechazó
      }
      return false;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void cerrar() => _dio.close(force: true);

  // ===========================================================================
  //  Backoff exponencial con jitter
  // ===========================================================================

  /// Ejecuta [operacion] reintentando los fallos reintentables con
  /// `base * 2^n` más jitter completo (`random(0, espera)`), acotado a
  /// [OpcionesSync.backoffMaximo].
  ///
  /// El jitter no es cosmético: sin él, cuando vuelve la señal en una zona con
  /// varias cajas, todas reintentan en el mismo milisegundo.
  Future<T> _conBackoff<T>({
    required Future<T> Function() operacion,
    required T Function(String mensaje) enFalloDeRed,
    required bool Function(T resultado) esReintentableResultado,
  }) async {
    T ultimo;
    for (var intento = 0;; intento++) {
      try {
        ultimo = await operacion();
      } on DioException catch (ex) {
        ultimo = enFalloDeRed(_mensajeDio(ex));
      } catch (ex) {
        ultimo = enFalloDeRed(ex.toString());
      }

      if (!esReintentableResultado(ultimo)) return ultimo;
      if (intento >= _opciones.maxReintentosHttp) return ultimo;

      await Future<void>.delayed(_esperaBackoff(intento));
    }
  }

  Duration _esperaBackoff(int intento) {
    final baseMs = _opciones.backoffBase.inMilliseconds;
    final topeMs = _opciones.backoffMaximo.inMilliseconds;
    // 2^intento acotado para no desbordar en int en reintentos altos.
    final factor = 1 << (intento > 20 ? 20 : intento);
    final techo = min(baseMs * factor, topeMs);
    // Full jitter: uniforme en [base/2, techo].
    final piso = min(baseMs ~/ 2, techo);
    return Duration(milliseconds: piso + _rnd.nextInt(max(1, techo - piso + 1)));
  }

  // ===========================================================================
  //  Clasificación de errores
  // ===========================================================================

  /// `null` = la respuesta es buena. Si no, el tipo de fallo.
  ///
  /// La rama se decide por `ErrorResponse.codigo` (contrato estable,
  /// `server/README.md §10`), NUNCA por el texto de `error`: ese texto es para
  /// el usuario y puede reescribirse o traducirse sin previo aviso.
  static TipoFalloSync? _clasificar(int? httpStatus, Object? cuerpo) {
    final c = httpStatus ?? 0;
    if (c >= 200 && c < 300) return null;

    final porCodigo = _porCodigoDeError(cuerpo);
    if (porCodigo != null) return porCodigo;

    // Sin `codigo` (server anterior al catálogo, o error aún sin clasificar):
    // se decide por el status, y para los 401/403 se cae a la heurística de
    // texto de más abajo.
    if (c == 401) return _compatibilidad401(cuerpo);
    if (c == 403) return _compatibilidad403(cuerpo);
    if (c == 429) return TipoFalloSync.limite;
    if (c >= 500) return TipoFalloSync.servidor;
    if (c >= 400) return TipoFalloSync.rechazoPermanente;
    return TipoFalloSync.red; // 0 / 1xx / 3xx sin seguir: tratar como red
  }

  /// Mapeo del catálogo de códigos a la taxonomía del cliente. Solo los que
  /// puede devolver `/sync/*`; cualquier otro cae a `null` y decide el status.
  static TipoFalloSync? _porCodigoDeError(Object? cuerpo) {
    final codigo = _codigoError(cuerpo);
    if (codigo == null) return null;
    return switch (codigo) {
      CodigosErrorSync.sinFlagCloudSync => TipoFalloSync.sinPermiso,
      CodigosErrorSync.asientoRevocado => TipoFalloSync.asientoRevocado,
      CodigosErrorSync.tokenExpirado => TipoFalloSync.tokenExpirado,
      CodigosErrorSync.tokenInvalido ||
      CodigosErrorSync.tokenAusente ||
      CodigosErrorSync.licenciaNoIdentificada =>
        TipoFalloSync.autenticacion,
      _ => null,
    };
  }

  // --- Compatibilidad con servers anteriores al campo `codigo` ---------------
  //
  // RUTA DE COMPATIBILIDAD, no el camino normal. `codigo` es aditivo
  // (`WhenWritingNull`), así que una instalación con un backend viejo sigue
  // mandando solo `error`. Estas dos funciones son lo único que queda parseando
  // texto, y solo se alcanzan cuando `codigo` no vino. Se pueden borrar cuando
  // todas las instalaciones desplegadas emitan el catálogo de §10.

  static TipoFalloSync _compatibilidad403(Object? cuerpo) {
    final texto = _mensajeError(cuerpo).toLowerCase();
    if (texto.contains('dispositivo') || texto.contains('revoc')) {
      return TipoFalloSync.asientoRevocado;
    }
    // Ante la duda, el caso del flag: es el frecuente y su salida (upsell) no
    // rompe nada si se muestra de más.
    return TipoFalloSync.sinPermiso;
  }

  static TipoFalloSync _compatibilidad401(Object? cuerpo) {
    final texto = _mensajeError(cuerpo).toLowerCase();
    if (texto.contains('expir') || texto.contains('vencid')) {
      return TipoFalloSync.tokenExpirado;
    }
    return TipoFalloSync.autenticacion;
  }

  // El parseo de `codigo`/`error` es compartido con el cliente de `/devices`
  // (`servicio_dispositivos_http.dart`): vive en `contratos_sync.dart` para que
  // los dos lean el cuerpo de error exactamente igual.
  static String? _codigoError(Object? cuerpo) => leerCodigoErrorRemoto(cuerpo);

  static String _mensajeError(Object? cuerpo) => leerMensajeErrorRemoto(cuerpo);

  static String _mensajeDio(DioException ex) {
    switch (ex.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'tiempo de espera agotado';
      case DioExceptionType.connectionError:
        return 'sin conexión con el servidor';
      case DioExceptionType.badCertificate:
        return 'certificado TLS inválido';
      case DioExceptionType.cancel:
        return 'cancelado';
      case DioExceptionType.badResponse:
        return 'respuesta inesperada (${ex.response?.statusCode})';
      case DioExceptionType.unknown:
        return ex.message ?? 'error de red';
    }
  }
}
