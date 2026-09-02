// PagoYa Móvil — dominio/uuid.dart
//
// Generador de UUID v4 sin dependencias externas.
//
// POR QUÉ NO USAR UN PAQUETE: `pagoya_core` es Dart puro y su lista de
// dependencias la define `mobile-lead` en el pubspec. Un generador de 20
// líneas evita bloquearse esperando esa decisión y no arrastra transitivos.
//
// FORMATO: minúsculas con guiones ("D" de .NET, `Guid.ToString()`), que es
// exactamente lo que el escritorio escribe en las PK TEXT y en el JSON del
// outbox. Si el formato difiere, las claves primarias no cruzan entre PC y
// móvil y la sincronización duplica filas en vez de fusionarlas.

library;

import 'dart:math';

/// UUID versión 4 (aleatorio) en formato `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
abstract final class Uuid {
  static final Random _rnd = _crearRandom();

  static Random _crearRandom() {
    try {
      return Random.secure();
    } on UnsupportedError {
      // Plataformas sin CSPRNG: se degrada a Random(). Los IDs siguen siendo
      // únicos en la práctica porque llevan la semilla del reloj.
      return Random(DateTime.now().microsecondsSinceEpoch);
    }
  }

  /// Genera un UUID v4 nuevo.
  static String v4() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).toList();
    return '${h[0]}${h[1]}${h[2]}${h[3]}-'
        '${h[4]}${h[5]}-'
        '${h[6]}${h[7]}-'
        '${h[8]}${h[9]}-'
        '${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
  }

  /// UUID de solo ceros — equivale a `Guid.Empty` del escritorio.
  static const String vacio = '00000000-0000-0000-0000-000000000000';

  /// Normaliza un UUID leído de la BD o de un payload remoto: minúsculas y sin
  /// llaves. `Guid.Parse` de C# es tolerante; SQLite compara TEXT byte a byte,
  /// así que aquí sí hay que normalizar antes de comparar o de insertar.
  static String normalizar(String? id) {
    final s = (id ?? '').trim().toLowerCase();
    if (s.isEmpty) return vacio;
    if (s.startsWith('{') && s.endsWith('}')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static bool esVacio(String? id) =>
      id == null || id.isEmpty || normalizar(id) == vacio;
}
