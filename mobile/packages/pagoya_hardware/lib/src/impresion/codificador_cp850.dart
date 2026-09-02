import 'dart:typed_data';

/// Codificador **CP850 (Multilingual Latin 1)**.
///
/// El escritorio usa `Encoding.GetEncoding(850)` en
/// `TicketPrinterEscPos.ObtenerCodificacion()`. Dart no trae CP850 en su
/// librería estándar (solo ascii/latin1/utf8), así que se implementa la tabla a
/// mano para el rango que nos importa: castellano completo más los símbolos
/// habituales de un ticket.
///
/// Por qué CP850 y no latin1: la mayoría de térmicas ESC/POS baratas exponen
/// las páginas de código del mundo DOS (CP437, CP850, CP858, CP860). Mandarles
/// bytes latin1 con la página CP850 activa imprime basura, y viceversa. Aquí
/// se emiten los bytes CP850 correctos y el generador activa la página 2
/// (`ESC t 2` vía `setGlobalCodeTable('CP850')`).
///
/// Si un modelo no soporta CP850 (algunos clones muy baratos solo traen CP437),
/// el usuario activa `ConfiguracionImpresion.transliterarAcentos` y se imprime
/// sin tildes en vez de con símbolos raros.
class CodificadorCp850 {
  const CodificadorCp850();

  /// Unicode → byte CP850. Solo el rango > 0x7F; ASCII pasa tal cual.
  static const Map<int, int> _tabla = <int, int>{
    0x00C7: 0x80, // Ç
    0x00FC: 0x81, // ü
    0x00E9: 0x82, // é
    0x00E2: 0x83, // â
    0x00E4: 0x84, // ä
    0x00E0: 0x85, // à
    0x00E5: 0x86, // å
    0x00E7: 0x87, // ç
    0x00EA: 0x88, // ê
    0x00EB: 0x89, // ë
    0x00E8: 0x8A, // è
    0x00EF: 0x8B, // ï
    0x00EE: 0x8C, // î
    0x00EC: 0x8D, // ì
    0x00C4: 0x8E, // Ä
    0x00C5: 0x8F, // Å
    0x00C9: 0x90, // É
    0x00E6: 0x91, // æ
    0x00C6: 0x92, // Æ
    0x00F4: 0x93, // ô
    0x00F6: 0x94, // ö
    0x00F2: 0x95, // ò
    0x00FB: 0x96, // û
    0x00F9: 0x97, // ù
    0x00FF: 0x98, // ÿ
    0x00D6: 0x99, // Ö
    0x00DC: 0x9A, // Ü
    0x00F8: 0x9B, // ø
    0x00A3: 0x9C, // £
    0x00D8: 0x9D, // Ø
    0x00D7: 0x9E, // ×
    0x0192: 0x9F, // ƒ
    0x00E1: 0xA0, // á
    0x00ED: 0xA1, // í
    0x00F3: 0xA2, // ó
    0x00FA: 0xA3, // ú
    0x00F1: 0xA4, // ñ
    0x00D1: 0xA5, // Ñ
    0x00AA: 0xA6, // ª
    0x00BA: 0xA7, // º
    0x00BF: 0xA8, // ¿
    0x00AE: 0xA9, // ®
    0x00AC: 0xAA, // ¬
    0x00BD: 0xAB, // ½
    0x00BC: 0xAC, // ¼
    0x00A1: 0xAD, // ¡
    0x00AB: 0xAE, // «
    0x00BB: 0xAF, // »
    0x00C1: 0xB5, // Á
    0x00C2: 0xB6, // Â
    0x00C0: 0xB7, // À
    0x00A9: 0xB8, // ©
    0x00A2: 0xBD, // ¢
    0x00A5: 0xBE, // ¥
    0x00E3: 0xC6, // ã
    0x00C3: 0xC7, // Ã
    0x00A4: 0xCF, // ¤
    0x00F0: 0xD0, // ð
    0x00D0: 0xD1, // Ð
    0x00CA: 0xD2, // Ê
    0x00CB: 0xD3, // Ë
    0x00C8: 0xD4, // È
    0x0131: 0xD5, // ı
    0x00CD: 0xD6, // Í
    0x00CE: 0xD7, // Î
    0x00CF: 0xD8, // Ï
    0x00CC: 0xDE, // Ì
    0x00D3: 0xE0, // Ó
    0x00DF: 0xE1, // ß
    0x00D4: 0xE2, // Ô
    0x00D2: 0xE3, // Ò
    0x00F5: 0xE4, // õ
    0x00D5: 0xE5, // Õ
    0x00B5: 0xE6, // µ
    0x00FE: 0xE7, // þ
    0x00DE: 0xE8, // Þ
    0x00DA: 0xE9, // Ú
    0x00DB: 0xEA, // Û
    0x00D9: 0xEB, // Ù
    0x00FD: 0xEC, // ý
    0x00DD: 0xED, // Ý
    0x00AF: 0xEE, // ¯
    0x00B4: 0xEF, // ´
    0x00B1: 0xF1, // ±
    0x00BE: 0xF3, // ¾
    0x00B6: 0xF4, // ¶
    0x00A7: 0xF5, // §
    0x00F7: 0xF6, // ÷
    0x00B8: 0xF7, // ¸
    0x00B0: 0xF8, // °
    0x00A8: 0xF9, // ¨
    0x00B7: 0xFA, // ·
    0x00B9: 0xFB, // ¹
    0x00B3: 0xFC, // ³
    0x00B2: 0xFD, // ²
    0x00A0: 0x20, // NBSP → espacio normal
  };

  /// Reemplazo ASCII para cuando la impresora no soporta CP850 o el carácter
  /// no está en la tabla. Nunca se imprime un `?` si se puede evitar.
  static const Map<int, String> _transliteracion = <int, String>{
    0x00E1: 'a', 0x00E9: 'e', 0x00ED: 'i', 0x00F3: 'o', 0x00FA: 'u',
    0x00C1: 'A', 0x00C9: 'E', 0x00CD: 'I', 0x00D3: 'O', 0x00DA: 'U',
    0x00E0: 'a', 0x00E8: 'e', 0x00EC: 'i', 0x00F2: 'o', 0x00F9: 'u',
    0x00E2: 'a', 0x00EA: 'e', 0x00EE: 'i', 0x00F4: 'o', 0x00FB: 'u',
    0x00E4: 'a', 0x00EB: 'e', 0x00EF: 'i', 0x00F6: 'o', 0x00FC: 'u',
    0x00C4: 'A', 0x00CB: 'E', 0x00CF: 'I', 0x00D6: 'O', 0x00DC: 'U',
    0x00F1: 'n', 0x00D1: 'N', 0x00E7: 'c', 0x00C7: 'C',
    0x00BF: '?', 0x00A1: '!', 0x00BA: 'o', 0x00AA: 'a',
    0x00B0: ' ', 0x00AB: '"', 0x00BB: '"',
    0x2018: "'", 0x2019: "'", 0x201C: '"', 0x201D: '"',
    0x2013: '-', 0x2014: '-', 0x2026: '...',
    0x20AC: 'EUR', 0x00A9: '(c)', 0x00AE: '(r)',
    0x00BD: '1/2', 0x00BC: '1/4', 0x00BE: '3/4',
  };

  /// Codifica [texto] a bytes CP850.
  ///
  /// Si [transliterar] es `true`, primero se pasa todo a ASCII (modo
  /// compatibilidad para impresoras sin CP850). Los caracteres desconocidos se
  /// reemplazan por `?` como último recurso, nunca se lanza excepción: un
  /// nombre de producto con un emoji no puede tumbar la impresión de un ticket.
  Uint8List codificar(String texto, {bool transliterar = false}) {
    final salida = <int>[];
    for (final rune in texto.runes) {
      if (rune < 0x80) {
        salida.add(rune);
        continue;
      }
      if (transliterar) {
        final ascii = _transliteracion[rune];
        salida.addAll((ascii ?? '?').codeUnits);
        continue;
      }
      final byte = _tabla[rune];
      if (byte != null) {
        salida.add(byte);
        continue;
      }
      // Fuera de tabla: se intenta transliterar antes de rendirse.
      final ascii = _transliteracion[rune];
      salida.addAll((ascii ?? '?').codeUnits);
    }
    return Uint8List.fromList(salida);
  }

  /// Versión solo-ASCII de un texto (sin tildes). Se usa también para el nombre
  /// de archivo al compartir.
  String aAscii(String texto) =>
      String.fromCharCodes(codificar(texto, transliterar: true));
}