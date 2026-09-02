/// Cliente HTTP de **seats** (`POST /devices`, `DELETE /devices/{id}`).
///
/// Implementa [ServicioDispositivos] (`nube/contratos.dart`, dueño
/// `mobile-lead`). Es el flujo que evita que el celular desvincule la PC: el
/// móvil NO llama `/activate` —eso movería `HwidActual` y quemaría uno de los
/// dos traslados—, sino que ocupa un cupo de `MaxDispositivos`.
///
/// ## Los errores se ramifican por `codigo`, nunca por texto
///
/// El backend devuelve `ErrorResponse { error, codigo }` (catálogo estable de
/// 25 códigos, `server/README.md §10`). Este cliente **propaga `codigo` intacto**
/// en [ResultadoVinculacion.codigo]; quien clasifica es
/// `codigos_error_licencia.clasificarFalloVinculacion`, que distingue
/// `cupo_dispositivos_lleno` (oportunidad de venta) de `licencia_suspendida`
/// (soporte) de `token_expirado` (renovar, no re-vincular).
///
/// Sin esa propagación, `codigoDeVinculacion()` devolvía siempre `null` y todo
/// el flujo de asientos caía en el parseo de subcadenas. Ese era el bug.
///
/// ## Red vs respuesta de error: la distinción importa
///
/// - **Sin red / timeout / 5xx** → se **lanza**. Es lo que
///   `VinculadorAsiento` y `RevalidadorLicencia` esperan: ambos envuelven la
///   llamada en `try/catch` y lo traducen a "reintenta luego" sin degradar nada.
/// - **Respuesta HTTP de error (4xx)** → se **devuelve** un
///   [ResultadoVinculacion] con `exito: false` y el `codigo` del backend. Eso sí
///   es información que el usuario tiene que ver.
///
/// Devolver un resultado donde debería lanzar convertiría un corte de señal en
/// "tu licencia tiene un problema", que es exactamente el mensaje que no hay
/// que darle a alguien que solo se metió en un sótano.
library;

import 'package:dio/dio.dart';

import 'contratos.dart';
import 'contratos_sync.dart';

/// Crea el cliente HTTP de seats.
///
/// [urlBase] es la raíz del backend de licencias (p. ej. `https://api.pagoya.pe`).
/// [dio] solo se inyecta en tests.
ServicioDispositivos crearServicioDispositivos({
  required String urlBase,
  Dio? dio,
  Duration timeout = const Duration(seconds: 20),
}) =>
    ServicioDispositivosHttp(urlBase: urlBase, dio: dio, timeout: timeout);

class ServicioDispositivosHttp implements ServicioDispositivos {
  ServicioDispositivosHttp({
    required String urlBase,
    Dio? dio,
    Duration timeout = const Duration(seconds: 20),
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _normalizarBase(urlBase),
              connectTimeout: timeout,
              receiveTimeout: timeout,
              sendTimeout: timeout,
              responseType: ResponseType.json,
              // Los 4xx los clasificamos nosotros por `codigo`; dio no debe
              // convertirlos en excepción, que es el canal de "no hay red".
              validateStatus: (_) => true,
              headers: const {'Content-Type': 'application/json'},
            ));

  final Dio _dio;

  static String _normalizarBase(String url) {
    final limpia = url.trim();
    if (limpia.isEmpty) return '';
    return limpia.endsWith('/') ? limpia : '$limpia/';
  }

  // ===========================================================================
  //  POST /devices
  // ===========================================================================

  /// Vincula este dispositivo como asiento secundario.
  ///
  /// **Idempotente por `deviceId`** (`server/README.md §4`): re-vincular el
  /// mismo dispositivo re-emite el token con `iat`/`exp` frescos **sin consumir
  /// otro cupo**. Por eso `RevalidadorLicencia` usa esto y no `/validate`
  /// (`/validate` es la puerta del equipo principal y respondería 409 al móvil).
  ///
  /// OJO con el nombre del parámetro: [tokenLicencia] es la **clave de
  /// licencia** (`PAGOYA-XXXX-...`), no un token firmado — el backend la recibe
  /// como `licenseKey`. El nombre viene de la interfaz de `mobile-lead` y no lo
  /// cambio aquí para no romper a los dos consumidores.
  @override
  Future<ResultadoVinculacion> vincular({
    required String tokenLicencia,
    required String idDispositivo,
    required String nombreDispositivo,
    required String plataforma,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>('devices', data: {
        'licenseKey': tokenLicencia,
        'deviceId': idDispositivo,
        'nombre': nombreDispositivo,
        'plataforma': plataforma,
      });
    } on DioException catch (ex) {
      // Sin red / timeout: se LANZA. Los llamadores lo traducen a "reintenta".
      throw ExcepcionRedDispositivos(_mensajeDio(ex), ex);
    }

    final estado = resp.statusCode ?? 0;
    final cuerpo = resp.data;

    // 5xx: el servidor está caído, no la licencia. Mismo canal que la red.
    if (estado >= 500) {
      throw ExcepcionRedDispositivos(
          'El servidor de licencias respondió $estado.', null);
    }

    if (estado >= 200 && estado < 300) {
      final token = _leerCadena(cuerpo, 'token');
      if (token == null || token.trim().isEmpty) {
        // 2xx sin token: no hay nada que persistir. No es un fallo de red, así
        // que se devuelve como resultado y no como excepción.
        return ResultadoVinculacion(
          exito: false,
          mensaje: 'El servidor no devolvió un token para este dispositivo.',
          codigo: leerCodigoErrorRemoto(cuerpo),
        );
      }
      return ResultadoVinculacion(
        exito: true,
        tokenFirmado: token,
        // El backend no emite `codigo` en el camino feliz, pero se lee igual:
        // es aditivo y no cuesta nada estar preparado si algún día manda uno
        // informativo (p. ej. un aviso de cupo casi lleno).
        codigo: leerCodigoErrorRemoto(cuerpo),
      );
    }

    // 4xx: respuesta de error con contrato. `codigo` intacto, `error` como texto.
    final mensaje = leerMensajeErrorRemoto(cuerpo);
    return ResultadoVinculacion(
      exito: false,
      mensaje: mensaje.isEmpty ? null : mensaje,
      codigo: leerCodigoErrorRemoto(cuerpo),
    );
  }

  // ===========================================================================
  //  DELETE /devices/{id}
  // ===========================================================================

  /// Revoca el asiento y libera el cupo.
  ///
  /// [idAsiento] es el `deviceId` GUID que devolvió la vinculación en
  /// `TokenResponse.deviceId`, **no** la huella del equipo: la ruta es
  /// `DELETE /devices/{id:guid}` y con una huella responde 404. El parámetro se
  /// llamaba `idDispositivo`; renombrado en el contrato para que el nombre
  /// impida el error en vez de solo advertirlo.
  ///
  /// La clave de licencia va en la cabecera `X-License-Key` y **no** en la
  /// query, porque las URLs acaban en logs y proxies.
  @override
  Future<bool> revocar({
    required String tokenLicencia,
    required String idAsiento,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.delete<dynamic>(
        'devices/$idAsiento',
        options: Options(headers: {'X-License-Key': tokenLicencia}),
      );
    } on DioException catch (ex) {
      throw ExcepcionRedDispositivos(_mensajeDio(ex), ex);
    }

    final estado = resp.statusCode ?? 0;
    if (estado >= 500) {
      throw ExcepcionRedDispositivos(
          'El servidor de licencias respondió $estado.', null);
    }
    if (estado < 200 || estado >= 300) return false;

    final revocado = resp.data;
    if (revocado is Map && revocado['revocado'] is bool) {
      return revocado['revocado'] as bool;
    }
    return true;
  }

  static String? _leerCadena(Object? cuerpo, String clave) {
    if (cuerpo is! Map) return null;
    final valor = cuerpo[clave];
    return valor?.toString();
  }

  static String _mensajeDio(DioException ex) => switch (ex.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Tiempo de espera agotado con el servidor de licencias.',
        DioExceptionType.connectionError =>
          'Sin conexión con el servidor de licencias.',
        DioExceptionType.badCertificate => 'Certificado TLS inválido.',
        DioExceptionType.cancel => 'Petición cancelada.',
        DioExceptionType.badResponse =>
          'Respuesta inesperada (${ex.response?.statusCode}).',
        DioExceptionType.unknown => ex.message ?? 'Error de red.',
      };
}

/// Fallo de transporte al hablar con `/devices`.
///
/// Se lanza a propósito: `VinculadorAsiento` y `RevalidadorLicencia` capturan
/// cualquier excepción de `vincular` y la traducen a "reintenta luego" sin
/// degradar la licencia. Un corte de señal no puede parecerse a un problema de
/// licencia.
class ExcepcionRedDispositivos implements Exception {
  const ExcepcionRedDispositivos(this.mensaje, this.causa);

  final String mensaje;
  final Object? causa;

  @override
  String toString() => 'ExcepcionRedDispositivos: $mensaje';
}
