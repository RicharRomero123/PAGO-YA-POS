/// Barril de la UI de licenciamiento. `flutter-ui` y `mobile-lead` deberían
/// importar solo este archivo.
///
/// - `GateLicencia`: envuelve la raíz del POS. Sin token válido no se entra, ni
///   siquiera en el plan Base, y pinta las franjas de aviso (gracia, por
///   vencer, reloj sospechoso) sin bloquear la operación.
/// - `PantallaActivacion`: activar con clave (`POST /devices`), o sin internet
///   pegando / escaneando / importando el token.
/// - `GuardiaCaracteristica`, `BloqueoEnLinea`, `TarjetaModuloBloqueado`:
///   feature gating por flag **firmado**, pintado con los widgets de
///   `mobile-ux` (`ui/comun/funcion_bloqueada.dart`).
/// - `caracteristicaProvider`: el único provider que deben consultar las
///   pantallas para saber si una función está habilitada.
library;

export 'gate_licencia.dart';
export 'gating_licencia.dart';
export 'pantalla_activacion.dart';
export 'proveedores_licencia.dart';
