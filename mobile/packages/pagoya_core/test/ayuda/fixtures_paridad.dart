// PagoYa Móvil — test/ayuda/fixtures_paridad.dart
//
// Carga los fixtures COMPARTIDOS de `tests/fixtures/paridad/`.
//
// Son los mismos archivos que consume el lado C#: por eso viven en la raíz del
// repo y no dentro del paquete Dart (docs/MOBILE-ARQUITECTURA.md §8). Si un
// test de paridad falla, EL MÓVIL SE ADAPTA AL ESCRITORIO, no al revés: el
// fixture solo se cambia cuando cambia la regla de negocio en ambos lados.

library;

import 'dart:convert';
import 'dart:io';

/// Rutas candidatas a la carpeta de fixtures, según desde dónde se lance
/// `dart test` (raíz del paquete, raíz de `mobile/`, o raíz del repo).
const List<String> _candidatas = [
  '../../../tests/fixtures/paridad',
  '../../tests/fixtures/paridad',
  '../tests/fixtures/paridad',
  'tests/fixtures/paridad',
];

/// Carpeta de fixtures resuelta. Lanza si no la encuentra: es preferible un
/// fallo ruidoso a un test que "pasa" porque no comparó nada.
Directory carpetaFixtures() {
  for (final c in _candidatas) {
    final d = Directory(c);
    if (d.existsSync()) return d;
  }
  throw StateError(
    'No se encontró tests/fixtures/paridad. Ejecuta `dart test` desde '
    'mobile/packages/pagoya_core o desde la raíz del repo. Buscado en: '
    '${_candidatas.join(", ")}',
  );
}

/// Lee y parsea un fixture por nombre de archivo.
Map<String, Object?> leerFixture(String archivo) {
  final f = File('${carpetaFixtures().path}/$archivo');
  if (!f.existsSync()) {
    throw StateError('Falta el fixture de paridad: ${f.path}');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
}

/// Lista de casos de un fixture (`{"casos": [...]}`).
List<Map<String, Object?>> casosDe(Map<String, Object?> fixture,
    [String clave = 'casos']) {
  final lista = fixture[clave];
  if (lista is! List) {
    throw StateError('El fixture no tiene la lista "$clave".');
  }
  return lista.whereType<Map<String, Object?>>().toList();
}

/// Compara dos estructuras JSON ignorando lo que NO es significativo para la
/// paridad con C#:
///
///   * el ORDEN de las claves (ni System.Text.Json ni Dart lo garantizan);
///   * la ESCALA de los números (C# emite `decimal` como 7.00 y Dart emite
///     `double` como 7.0 — es el mismo valor);
///   * la representación de las FECHAS (se comparan como instantes, no como
///     texto, para que el test no dependa de la zona horaria de la máquina).
///
/// Devuelve null si son equivalentes, o la ruta y el motivo de la diferencia.
String? diferenciaJson(Object? esperado, Object? real, [String ruta = r'$']) {
  if (esperado == null && real == null) return null;
  if (esperado == null || real == null) {
    return '$ruta: esperado $esperado, real $real';
  }

  if (esperado is Map && real is Map) {
    final claves = <String>{
      ...esperado.keys.map((k) => k.toString()),
      ...real.keys.map((k) => k.toString()),
    };
    for (final k in claves) {
      if (!esperado.containsKey(k)) return '$ruta.$k: sobra en el real';
      if (!real.containsKey(k)) return '$ruta.$k: falta en el real';
      final d = diferenciaJson(esperado[k], real[k], '$ruta.$k');
      if (d != null) return d;
    }
    return null;
  }

  if (esperado is List && real is List) {
    if (esperado.length != real.length) {
      return '$ruta: esperado ${esperado.length} elementos, real ${real.length}';
    }
    for (var i = 0; i < esperado.length; i++) {
      final d = diferenciaJson(esperado[i], real[i], '$ruta[$i]');
      if (d != null) return d;
    }
    return null;
  }

  if (esperado is num && real is num) {
    // Tolerancia de medio céntimo: cubre la diferencia de representación entre
    // el decimal de C# y el double de Dart sin dejar pasar un error real.
    return (esperado.toDouble() - real.toDouble()).abs() < 0.000001
        ? null
        : '$ruta: esperado $esperado, real $real';
  }

  if (esperado is String && real is String) {
    if (esperado == real) return null;
    final a = DateTime.tryParse(esperado);
    final b = DateTime.tryParse(real);
    if (a != null && b != null) {
      return a.toUtc() == b.toUtc()
          ? null
          : '$ruta: instantes distintos ($esperado vs $real)';
    }
    return '$ruta: esperado "$esperado", real "$real"';
  }

  return esperado == real ? null : '$ruta: esperado $esperado, real $real';
}
