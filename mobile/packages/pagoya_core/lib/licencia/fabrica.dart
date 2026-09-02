/// Fábricas del subsistema de licenciamiento — la superficie que consume
/// `main.dart` (`mobile-lead`). Contrato declarado en `pagoya_core.dart`.
///
/// Una sola función de fábrica por pieza en vez de exponer nombres de clase:
/// menos acople entre agentes, y el grafo interno (validador RSA, almacén
/// seguro, reloj auditado, `meta`) puede cambiar sin tocar el arranque.
///
/// ---
///
/// ## Tipo de `baseDatos`: RESUELTO (pasada final de reconciliación, §4.3)
///
/// Este archivo tipa el parámetro como [EjecutorSql] —no como
/// `BaseDatosPagoYa`— y dejaba abierto si eso le costaría un adaptador a
/// `main.dart`. **No cuesta ninguno.** Verificado por `mobile-lead` leyendo
/// `datos/base_datos_drift.dart`:
///
/// ```dart
/// class BaseDatosPagoYa extends GeneratedDatabase implements EjecutorSql
/// ```
///
/// Así que `crearServicioLicencia(baseDatos: baseDatos)` compila tal cual, y es
/// exactamente lo que hace `main.dart`. No hace falta `baseDatos.sql` ni ningún
/// getter intermedio.
///
/// Y tipar por [EjecutorSql] es lo correcto además de lo que funciona: el
/// licenciamiento solo necesita leer y escribir la tabla `meta`, así que pedir
/// la clase concreta de drift habría acoplado el módulo a la capa de datos
/// entera para nada.
library;

import '../datos/ejecutor_sql.dart';
import '../nube/contratos.dart';
import 'almacen_licencia.dart';
import 'license_token_validator.dart';
import 'meta_licencia.dart';
import 'puertos_licencia.dart';
import 'reloj_auditado.dart';
import 'revalidador_licencia.dart';
import 'servicio_licencia.dart';
import 'vinculador_asiento.dart';

/// Construye el servicio de licencia completo.
///
/// Arma por dentro el validador RSA (con la clave pública embebida), el almacén
/// del token sobre [AlmacenSeguro] y el [RelojAuditado] sobre la tabla `meta`.
///
/// **No valida nada todavía**: hay que llamar
/// `ServicioLicencia.cargarLicenciaLocal()` justo después, como hace `main.dart`.
ServicioLicencia crearServicioLicencia({
  required AlmacenSeguro almacenSeguro,
  required IdentidadDispositivo identidad,
  required EjecutorSql baseDatos,
}) {
  final MetaLicencia meta = MetaLicencia(baseDatos);
  return ServicioLicencia(
    validador: LicenseTokenValidator(),
    identidad: identidad,
    almacen: AlmacenLicenciaSegura(almacenSeguro),
    reloj: RelojAuditadoMeta(meta),
    meta: meta,
  );
}

/// Almacén del token firmado. `main.dart` lo usa para leer el token crudo que
/// va en los `Authorization: Bearer` de la nube.
///
/// Devuelve el tipo concreto (y no la interfaz) porque el licenciamiento
/// también guarda ahí la **clave de licencia** para la revalidación silenciosa,
/// y eso no está en el contrato [AlmacenLicencia].
AlmacenLicenciaSegura crearAlmacenLicencia(AlmacenSeguro almacenSeguro) =>
    AlmacenLicenciaSegura(almacenSeguro);

/// Revalidación silenciosa contra `POST /devices` (idempotente por `deviceId`).
///
/// [servicio] debe ser el mismo que devolvió [crearServicioLicencia]: el
/// revalidador publica el token renovado a través de él, y así el
/// `NotificadorLicencia` del composition root se entera sin reiniciar la app.
RevalidadorLicencia crearRevalidadorLicencia({
  required ServicioLicencia servicio,
  required ServicioDispositivos dispositivos,
  required IdentidadDispositivo identidad,
  required AlmacenSeguro almacenSeguro,
  required EjecutorSql baseDatos,
}) {
  final MetaLicencia meta = MetaLicencia(baseDatos);
  return RevalidadorLicencia(
    servicio: servicio,
    dispositivos: dispositivos,
    identidad: identidad,
    almacen: AlmacenLicenciaSegura(almacenSeguro),
    meta: meta,
    reloj: RelojAuditadoMeta(meta),
  );
}

/// Vinculación de este teléfono como asiento secundario (pantalla de
/// activación con clave `PAGOYA-…`).
VinculadorAsiento crearVinculadorAsiento({
  required ServicioLicencia servicio,
  required ServicioDispositivos dispositivos,
  required IdentidadDispositivo identidad,
  required AlmacenSeguro almacenSeguro,
  required EjecutorSql baseDatos,
}) =>
    VinculadorAsiento(
      licencia: servicio,
      dispositivos: dispositivos,
      identidad: identidad,
      almacen: AlmacenLicenciaSegura(almacenSeguro),
      // `meta` guarda el GUID del asiento (`device_id`), que es lo que exige
      // `DELETE /devices/{id}` — no la huella del equipo.
      meta: MetaLicencia(baseDatos),
    );

/// Prefijo de dispositivo asignado por el server (`M01`..`M99`), leído del
/// claim firmado `device_prefix` y persistido en `meta`.
///
/// **Lo consumen `flutter-datos`** (correlativos `M01-000123` en
/// `ventas.numero`) **y `flutter-sync`** (`origen_caja_id` del outbox y filtro
/// de eco del pull). Devuelve `null` si el token no traía el claim: en ese caso
/// el consumidor aplica su valor por defecto y **no** debe inventar un prefijo,
/// porque los prefijos son únicos por licencia y los asigna el backend.
Future<String?> leerPrefijoDispositivo(EjecutorSql baseDatos) =>
    MetaLicencia(baseDatos).leer(ClavesMetaLicencia.prefijoDispositivo);

/// Id del **asiento** (`device_id`), el `{id}` de `DELETE /devices/{id}`.
/// Se muestra en Ajustes para que el dueño pueda pedir su revocación.
Future<String?> leerIdAsiento(EjecutorSql baseDatos) =>
    MetaLicencia(baseDatos).leer(ClavesMetaLicencia.idAsiento);
