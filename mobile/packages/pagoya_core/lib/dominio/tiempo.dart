// PagoYa Móvil — dominio/tiempo.dart
//
// Formato de fechas con paridad EXACTA con el escritorio.
//
// POR QUÉ IMPORTA TANTO
// ---------------------
// El escritorio escribe todas las fechas con `DateTime.ToString("o")`
// (round-trip ISO-8601 con 7 dígitos de fracción) y guarda ese TEXTO en
// SQLite. La resolución de conflictos last-write-wins compara esas columnas
// **como texto** dentro del SQL:
//
//     WHERE excluded.updated_utc > productos.updated_utc
//
// Es decir: la comparación es lexicográfica, no temporal. Para que sea
// correcta, todas las cajas deben escribir la MISMA cantidad de dígitos de
// fracción. `DateTime.toIso8601String()` de Dart emite 3 o 6 dígitos según el
// caso, así que `.123456Z` compararía mal contra `.1234560Z` ('Z' > '0').
//
// Por eso aquí se emite siempre `yyyy-MM-ddTHH:mm:ss.fffffffZ` (7 dígitos),
// rellenando con ceros la precisión que Dart no tiene (microsegundos -> se
// añade un dígito 0 final). El resultado es un literal que `DateTime.Parse`
// de C# lee con `DateTimeStyles.RoundtripKind` sin ambigüedad.

library;

/// Formato de fecha/hora compatible con el especificador "o" de .NET.
abstract final class TiempoUtc {
  /// Serializa en UTC con 7 dígitos de fracción y sufijo `Z`.
  ///
  /// Equivale a `fecha.ToUniversalTime().ToString("o")` en C#.
  static String formatoO(DateTime fecha) {
    final u = fecha.toUtc();
    final f = _fraccion7(u.microsecond, u.millisecond);
    return '${_p(u.year, 4)}-${_p(u.month, 2)}-${_p(u.day, 2)}'
        'T${_p(u.hour, 2)}:${_p(u.minute, 2)}:${_p(u.second, 2)}.$f'
        'Z';
  }

  /// Serializa una fecha **local** (hora del negocio) con su desfase horario,
  /// igual que `DateTime.Now.ToString("o")` -> `2026-09-02T10:04:05.1234567-05:00`.
  ///
  /// Se usa para `ventas.fecha_hora`, `caja.fecha_apertura`, etc.: el ticket
  /// del cliente muestra la hora local del negocio, no UTC.
  static String formatoOLocal(DateTime fecha) {
    final l = fecha.isUtc ? fecha.toLocal() : fecha;
    final f = _fraccion7(l.microsecond, l.millisecond);
    final off = l.timeZoneOffset;
    final signo = off.isNegative ? '-' : '+';
    final abs = off.abs();
    final hh = _p(abs.inHours, 2);
    final mm = _p(abs.inMinutes.remainder(60).abs(), 2);
    return '${_p(l.year, 4)}-${_p(l.month, 2)}-${_p(l.day, 2)}'
        'T${_p(l.hour, 2)}:${_p(l.minute, 2)}:${_p(l.second, 2)}.$f'
        '$signo$hh:$mm';
  }

  /// Parsea una fecha escrita por el escritorio o por el móvil.
  ///
  /// Acepta con y sin sufijo `Z`/desfase y con cualquier cantidad de dígitos
  /// de fracción (Dart trunca a microsegundos, el 7.º dígito se pierde: es la
  /// única pérdida de precisión inevitable frente al `DateTime` de .NET, que
  /// tiene resolución de 100 ns).
  static DateTime? parsear(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;
    return DateTime.tryParse(texto.trim());
  }

  /// Igual que [parsear] pero devuelve `epoch` en vez de null. Para columnas
  /// NOT NULL donde un dato corrupto no debe tumbar la sincronización entera.
  static DateTime parsearUtc(String? texto) =>
      (parsear(texto) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          .toUtc();

  /// Solo fecha, `yyyy-MM-dd` — formato de `productos.fecha_vencimiento`.
  static String formatoFecha(DateTime fecha) =>
      '${_p(fecha.year, 4)}-${_p(fecha.month, 2)}-${_p(fecha.day, 2)}';

  static String _p(int v, int ancho) => v.toString().padLeft(ancho, '0');

  /// 7 dígitos de fracción a partir de la precisión de microsegundos de Dart.
  /// El 7.º dígito (100 ns) siempre es 0 porque Dart no lo tiene.
  static String _fraccion7(int microsegundo, int milisegundo) {
    final micros = milisegundo * 1000 + microsegundo;
    return '${_p(micros, 6)}0';
  }
}
