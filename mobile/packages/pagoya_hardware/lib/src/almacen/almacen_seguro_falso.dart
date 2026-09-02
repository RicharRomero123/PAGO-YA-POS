import 'package:pagoya_core/pagoya_core.dart' show AlmacenSeguro;

/// Implementación **falsa** de [AlmacenSeguro]: un `Map` en memoria.
///
/// Necesaria porque `flutter_secure_storage` requiere canal de plataforma: en
/// `flutter test` no existe, y en el emulador el Keystore a veces no está
/// disponible. Los tests de `flutter-licencia` la usan para ejercitar el
/// guardado del token sin Keychain.
///
/// Los interruptores de fallo no son adorno: replican los dos modos de avería
/// reales del Keystore de Android que hemos visto romper activaciones.
class AlmacenSeguroFalso implements AlmacenSeguro {
  AlmacenSeguroFalso({Map<String, String>? inicial})
      : _datos = <String, String>{...?inicial};

  final Map<String, String> _datos;

  /// Si es `true`, [leer] devuelve `null` siempre (almacén ilegible).
  bool fallarLectura = false;

  /// Si es `true`, [escribir] lanza (disco lleno, Keystore caído). Sirve para
  /// comprobar que la UI de activación avisa en vez de decir "listo" y perder
  /// el token.
  bool fallarEscritura = false;

  /// Contenido actual, para asserts. Copia: nadie muta el almacén por detrás.
  Map<String, String> get contenido => Map<String, String>.unmodifiable(_datos);

  /// Claves leídas, en orden. Útil para verificar que el gate de licencia no
  /// lee el token más veces de las necesarias en cada arranque.
  final List<String> lecturas = <String>[];

  @override
  Future<String?> leer(String clave) async {
    lecturas.add(clave);
    if (fallarLectura) return null;
    return _datos[clave];
  }

  @override
  Future<void> escribir(String clave, String valor) async {
    if (fallarEscritura) {
      throw StateError('almacén seguro no disponible (simulado)');
    }
    _datos[clave] = valor;
  }

  @override
  Future<void> borrar(String clave) async {
    _datos.remove(clave);
  }
}