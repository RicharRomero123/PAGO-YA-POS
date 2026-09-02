/// Licenciamiento de PagoYa Móvil — puerto a Dart de `src/PagoYa.Licensing` y
/// `PagoYa.Core/Contratos`. El contrato del token está en
/// `docs/LICENSE-TOKEN.md` y **no se toca**.
///
/// `licencia/contratos.dart` reexporta este barril, así que ambos caminos de
/// import llevan a lo mismo (arbitraje de `mobile-lead`, §4.2). Este archivo
/// **no** importa `contratos.dart`, para no crear un ciclo de exports.
///
/// Uso típico en el arranque (lo hace `main.dart` vía `fabrica.dart`):
///
/// ```dart
/// final servicio = crearServicioLicencia(
///   almacenSeguro: almacenSeguro,   // flutter-hardware
///   identidad: identidad,           // flutter-hardware
///   baseDatos: baseDatos,           // flutter-datos (EjecutorSql)
/// );
/// final estado = await servicio.cargarLicenciaLocal();
/// if (!estado.estaActivada) { /* pantalla de activación, NO entra al POS */ }
/// ```
library;

export 'almacen_licencia.dart';
export 'clave_publica_embebida.dart';
export 'codigos_error_licencia.dart';
export 'estado_licencia.dart';
export 'fabrica.dart';
export 'license_token.dart';
export 'license_token_validator.dart';
export 'meta_licencia.dart';
export 'puertos_licencia.dart';
export 'reloj_auditado.dart';
export 'revalidador_licencia.dart';
export 'servicio_licencia.dart';
export 'vinculador_asiento.dart';
