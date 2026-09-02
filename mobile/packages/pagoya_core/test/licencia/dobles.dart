/// Dobles de prueba de los puertos de licenciamiento. Todos en memoria: los
/// tests de `pagoya_core` no tocan plugins, ni disco, ni red.
library;

import 'package:pagoya_core/licencia/licencia.dart';
import 'package:pagoya_core/nube/contratos.dart';

/// Identidad de dispositivo fija.
final class IdentidadFalsa implements IdentidadDispositivo {
  final String id;
  final String nombre;
  final String plataforma;

  /// Si es `true`, [obtenerIdDispositivo] lanza: simula el almacén seguro
  /// inaccesible (Keystore borrado tras cambiar la firma del APK).
  final bool falla;

  const IdentidadFalsa(
    this.id, {
    this.nombre = 'Móvil de pruebas',
    this.plataforma = 'android',
    this.falla = false,
  });

  @override
  Future<String> obtenerIdDispositivo() async {
    if (falla) throw StateError('almacén seguro no disponible');
    return id;
  }

  @override
  Future<String> obtenerNombreDispositivo() async => nombre;

  @override
  Future<String> obtenerPlataforma() async => plataforma;
}

/// [AlmacenSeguro] en memoria (el Keystore/Keychain de mentira).
final class AlmacenSeguroEnMemoria implements AlmacenSeguro {
  final Map<String, String> datos = <String, String>{};

  /// Cuántas escrituras se hicieron: sirve para comprobar que una activación
  /// fallida NO sobrescribe una licencia buena.
  int escrituras = 0;

  AlmacenSeguroEnMemoria([Map<String, String>? inicial]) {
    if (inicial != null) datos.addAll(inicial);
  }

  /// Atajo: siembra un token ya "instalado".
  factory AlmacenSeguroEnMemoria.conToken(String token, {String? clave}) =>
      AlmacenSeguroEnMemoria(<String, String>{
        ClavesSeguras.tokenLicencia: token,
        if (clave != null) ClavesSeguras.claveLicencia: clave,
      });

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> escribir(String clave, String valor) async {
    datos[clave] = valor;
    escrituras++;
  }

  @override
  Future<void> borrar(String clave) async {
    datos.remove(clave);
  }
}

/// [AlmacenSeguro] que siempre falla: verifica que el arranque degrada de forma
/// elegante en vez de reventar.
final class AlmacenSeguroRoto implements AlmacenSeguro {
  const AlmacenSeguroRoto();

  @override
  Future<String?> leer(String clave) async => throw StateError('Keystore roto');

  @override
  Future<void> escribir(String clave, String valor) async =>
      throw StateError('Keystore roto');

  @override
  Future<void> borrar(String clave) async => throw StateError('Keystore roto');
}

/// Cliente de asientos falso: sustituye a `POST /devices`.
final class ServicioDispositivosFalso implements ServicioDispositivos {
  /// Token a devolver en la próxima llamada exitosa.
  String? tokenARetornar;

  /// Si no es null, se devuelve un [ResultadoVinculacion] fallido con este
  /// mensaje (cupo agotado, licencia suspendida…).
  String? mensajeDeFallo;

  /// Código estable de `ErrorResponse.codigo` que acompaña a [mensajeDeFallo].
  /// `null` simula un backend anterior al catálogo de `server/README.md §10`.
  String? codigoDeFallo;

  /// Si es `true`, `vincular`/`revocar` **lanzan**: simula falta de red.
  /// Es la separación que hace `flutter-sync`: la red lanza, los 4xx devuelven.
  bool lanzaError = false;

  /// Qué devuelve `revocar` cuando no lanza.
  bool revocacionExitosa = true;

  int llamadasVincular = 0;
  int llamadasRevocar = 0;
  String? ultimaClaveRecibida;
  String? ultimoIdRecibido;

  /// Id que recibió `revocar`. Debe ser el **GUID del asiento**, no la huella.
  String? ultimoIdRevocado;

  ServicioDispositivosFalso({
    this.tokenARetornar,
    this.mensajeDeFallo,
    this.codigoDeFallo,
    this.lanzaError = false,
  });

  @override
  Future<ResultadoVinculacion> vincular({
    required String tokenLicencia,
    required String idDispositivo,
    required String nombreDispositivo,
    required String plataforma,
  }) async {
    llamadasVincular++;
    ultimaClaveRecibida = tokenLicencia;
    ultimoIdRecibido = idDispositivo;

    if (lanzaError) throw StateError('sin red');

    final String? fallo = mensajeDeFallo;
    if (fallo != null) {
      return ResultadoVinculacion(
        exito: false,
        mensaje: fallo,
        codigo: codigoDeFallo,
      );
    }

    return ResultadoVinculacion(exito: true, tokenFirmado: tokenARetornar);
  }

  @override
  Future<bool> revocar({
    required String tokenLicencia,
    required String idAsiento,
  }) async {
    llamadasRevocar++;
    ultimoIdRevocado = idAsiento;
    if (lanzaError) throw StateError('sin red');
    return revocacionExitosa;
  }
}
