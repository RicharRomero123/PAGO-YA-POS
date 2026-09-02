/// Vinculación de este teléfono como **asiento secundario** de una licencia.
///
/// Es el camino normal de activación en móvil: el dueño escribe su clave
/// (`PAGOYA-XXXX-…`), la app llama `POST /devices` y se queda con el token
/// firmado que el server emite **para este dispositivo**.
///
/// Por qué no `/activate` (`server/README.md` §6.1): `/activate` reasigna
/// `Licencia.HwidActual` y consume un cupo de `MaxTraslados`. Si el celular lo
/// usara, **desvincularía la caja de la PC** y le quemaría uno de sus dos
/// traslados. `POST /devices` no toca `HwidActual` y es idempotente por
/// `deviceId`.
///
/// Los fallos se clasifican por el **código estable** de `ErrorResponse.codigo`
/// (`codigos_error_licencia.dart`, catálogo en `server/README.md §10`), nunca
/// por el texto del mensaje: ese se reescribe, se acorta y algún día se traduce.
library;

import '../nube/contratos.dart';
import 'almacen_licencia.dart';
import 'codigos_error_licencia.dart';
import 'estado_licencia.dart';
import 'meta_licencia.dart';
import 'puertos_licencia.dart';
import 'servicio_licencia.dart';

/// Desenlace de un intento de vinculación, ya traducido a algo que la UI puede
/// mostrar y sobre lo que puede ramificar.
final class ResultadoActivacionAsiento {
  /// Estado de licencia resultante. Si [exito] es `true`, `estaActivada` lo es.
  final EstadoLicencia estado;

  /// `true` si el dispositivo quedó vinculado y con licencia válida.
  final bool exito;

  /// Qué pasó, clasificado por código. `null` si [exito].
  final MotivoFalloVinculacion? motivoFallo;

  /// Mensaje para el usuario. Se prefiere el del backend (soporte lo puede
  /// reescribir sin desplegar la app) y si no hay, el de [mensajePorDefectoDe].
  final String? mensaje;

  const ResultadoActivacionAsiento({
    required this.estado,
    required this.exito,
    this.motivoFallo,
    this.mensaje,
  });

  /// `true` si el dueño no puede resolverlo solo: conviene ofrecerle el botón
  /// de WhatsApp con sus datos ya copiados.
  bool get requiereSoporte => motivoFallo?.requiereSoporte ?? false;

  /// `true` si reintentar más tarde tiene sentido (fallo de red).
  bool get esTransitorio => motivoFallo?.esTransitorio ?? false;

  /// `true` si lo que toca es **renovar el plan**, no volver a vincular. La
  /// distinción existe porque antes del catálogo de códigos mandábamos al dueño
  /// a re-activar una licencia que solo había que renovar.
  bool get requiereRenovacion =>
      motivoFallo == MotivoFalloVinculacion.tokenExpirado;
}

/// Orquesta clave → `POST /devices` → validación local → persistencia.
final class VinculadorAsiento {
  final ServicioLicencia _licencia;
  final ServicioDispositivos _dispositivos;
  final IdentidadDispositivo _identidad;
  final AlmacenLicenciaSegura _almacen;
  final MetaLicencia _meta;

  const VinculadorAsiento({
    required ServicioLicencia licencia,
    required ServicioDispositivos dispositivos,
    required IdentidadDispositivo identidad,
    required AlmacenLicenciaSegura almacen,
    required MetaLicencia meta,
  })  : _licencia = licencia,
        _dispositivos = dispositivos,
        _identidad = identidad,
        _almacen = almacen,
        _meta = meta;

  /// Vincula este dispositivo con [claveLicencia]. No lanza.
  Future<ResultadoActivacionAsiento> vincularConClave(
    String claveLicencia,
  ) async {
    final String clave = claveLicencia.trim();
    if (clave.isEmpty) {
      return ResultadoActivacionAsiento(
        estado: _licencia.estadoActual,
        exito: false,
        motivoFallo: MotivoFalloVinculacion.desconocido,
        mensaje: 'Escribe la clave de licencia que recibiste.',
      );
    }

    final String idDispositivo;
    final String nombre;
    final String plataforma;
    try {
      idDispositivo = await _identidad.obtenerIdDispositivo();
      nombre = await _identidad.obtenerNombreDispositivo();
      plataforma = await _identidad.obtenerPlataforma();
    } catch (_) {
      return ResultadoActivacionAsiento(
        estado: _licencia.estadoActual,
        exito: false,
        motivoFallo: MotivoFalloVinculacion.desconocido,
        mensaje: 'No se pudo identificar este dispositivo. Reinicia la app.',
      );
    }

    final ResultadoVinculacion respuesta;
    try {
      respuesta = await _dispositivos.vincular(
        tokenLicencia: clave, // el body lo manda como `licenseKey`
        // OJO: aquí va la HUELLA del equipo, no un GUID de asiento. El backend
        // la firma en el claim `hwid` y el cliente la recalcula en cada
        // arranque para validar. Ver `revocarEsteDispositivo`, donde el id que
        // se manda es el otro.
        idDispositivo: idDispositivo,
        nombreDispositivo: nombre,
        plataforma: plataforma,
      );
    } catch (_) {
      // `flutter-sync` LANZA en el camino de red (sin señal, timeout, 5xx) y
      // DEVUELVE resultado con código en los 4xx. Esa separación es la que
      // hace que un dueño en un sótano sin señal vea "no hay internet" y no un
      // problema de licencia: si esto no se tradujera a `red`, el clasificador
      // recibiría un mensaje vacío y caería a `desconocido`.
      // El catch es deliberadamente amplio: cualquier throw del transporte
      // significa "no llegamos al backend".
      return _fallo(MotivoFalloVinculacion.red, null);
    }

    final String? token = respuesta.tokenFirmado;
    if (!respuesta.exito || token == null || token.trim().isEmpty) {
      final MotivoFalloVinculacion motivo = clasificarFalloVinculacion(
        codigo: codigoDeVinculacion(respuesta),
        mensaje: respuesta.mensaje,
      );
      return _fallo(motivo, respuesta.mensaje);
    }

    // El token vuelve a validarse localmente antes de persistirse: aunque venga
    // del servidor, no se confía en él sin verificar la firma y que el `hwid`
    // sea el de este dispositivo.
    final EstadoLicencia estado = await _licencia.activarLicencia(token);
    if (!estado.estaActivada) {
      return ResultadoActivacionAsiento(
        estado: estado,
        exito: false,
        motivoFallo: MotivoFalloVinculacion.tokenInvalido,
        mensaje: estado.motivo ??
            'El servidor emitió una licencia que no es válida para este '
                'dispositivo.',
      );
    }

    // Solo se guarda la clave si todo salió bien: así la revalidación
    // silenciosa puede renovar sola más adelante.
    await _almacen.guardarClaveLicencia(clave);

    return ResultadoActivacionAsiento(estado: estado, exito: true);
  }

  /// Libera el asiento de **este** dispositivo en el backend y desactiva la
  /// licencia local. Tras esto el gate de arranque vuelve a la activación.
  ///
  /// ## El id que se manda aquí NO es el de [IdentidadDispositivo]
  ///
  /// Son dos valores distintos y confundirlos da un `404`:
  ///
  /// | Valor | De dónde sale | Dónde se usa |
  /// |---|---|---|
  /// | **Huella del equipo** | `IdentidadDispositivo.obtenerIdDispositivo()` | cuerpo de `POST /devices` y claim `hwid` |
  /// | **GUID del asiento** | claim `device_id` del token que devolvió la vinculación, persistido en `meta` | `DELETE /devices/{id}` |
  ///
  /// El parámetro de `ServicioDispositivos.revocar` se llama `idAsiento`
  /// precisamente por esto: se le pasa [EstadoLicencia.idAsiento], que viene
  /// firmado dentro del token. (Antes se llamaba `idDispositivo` e invitaba a
  /// pasarle la huella, que da 404; el contrato se renombró para que el nombre
  /// impida el error en vez de advertirlo aquí.)
  ///
  /// Si el token no trae `device_id` (licencia anterior al modelo de asientos)
  /// no hay nada que revocar por API: se desactiva en local y se le dice al
  /// dueño que soporte lo libera desde el panel.
  Future<ResultadoActivacionAsiento> revocarEsteDispositivo() async {
    final String? asiento = _licencia.estadoActual.idAsiento ??
        await _meta.leer(ClavesMetaLicencia.idAsiento);

    final String? clave = await _almacen.leerClaveLicencia();

    if (asiento == null || asiento.isEmpty || clave == null || clave.isEmpty) {
      // Sin GUID de asiento o sin clave (`X-License-Key`) no se puede llamar al
      // endpoint. Se limpia lo local igualmente: el dueño quería salir.
      await _licencia.desactivar();
      return ResultadoActivacionAsiento(
        estado: _licencia.estadoActual,
        exito: true,
        mensaje: 'Se cerró la licencia en este celular. Si necesitas liberar '
            'el cupo para otro equipo, escríbenos por WhatsApp.',
      );
    }

    final bool revocado;
    try {
      revocado = await _dispositivos.revocar(
        tokenLicencia: clave,
        idAsiento: asiento,
      );
    } catch (_) {
      // Camino de red: no se toca nada en local. Desactivar aquí dejaría al
      // dueño fuera del POS con el asiento todavía ocupado en el server.
      return _fallo(MotivoFalloVinculacion.red, null);
    }

    if (!revocado) {
      return _fallo(MotivoFalloVinculacion.desconocido, null);
    }

    await _licencia.desactivar();
    return ResultadoActivacionAsiento(
      estado: _licencia.estadoActual,
      exito: true,
      mensaje: 'Listo: este celular quedó desvinculado y su cupo está libre.',
    );
  }

  ResultadoActivacionAsiento _fallo(
    MotivoFalloVinculacion motivo,
    String? mensajeDelBackend,
  ) {
    final String? delBackend = mensajeDelBackend?.trim();
    return ResultadoActivacionAsiento(
      estado: _licencia.estadoActual,
      exito: false,
      motivoFallo: motivo,
      mensaje: (delBackend == null || delBackend.isEmpty)
          ? mensajePorDefectoDe(motivo)
          : delBackend,
    );
  }
}
