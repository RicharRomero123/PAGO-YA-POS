// PagoYa Móvil — dominio/personalizacion.dart
//
// PORT de `src/PagoYa.Core/Entidades/PersonalizacionProducto.cs`.
//
// Modificadores de producto del rubro comida (tamaños, agregados, notas de
// cocina). Se serializa a JSON y se guarda en `productos.personalizacion_json`,
// así que las CLAVES del JSON son las de C# (PascalCase) — este JSON lo lee y
// escribe también el escritorio.

library;

import 'dart:convert';

import 'dinero.dart';

/// Una opción de un grupo. [precioExtra] se SUMA al precio base del producto.
final class OpcionModificador {
  String nombre;
  Dinero precioExtra;

  OpcionModificador({this.nombre = '', Dinero? precioExtra})
      : precioExtra = precioExtra ?? Dinero.cero;

  factory OpcionModificador.desdeJson(Map<String, Object?> j) =>
      OpcionModificador(
        nombre: (j['Nombre'] ?? j['nombre'] ?? '') as String,
        precioExtra: Dinero.desdeDb(
            (j['PrecioExtra'] ?? j['precioExtra']) as num? ?? 0),
      );

  Map<String, Object?> aJson() => {
        'Nombre': nombre,
        'PrecioExtra': precioExtra.aDb(),
      };
}

/// Grupo de modificadores. Si [multiple] es false se elige UNA opción (radio);
/// si es true se eligen VARIAS (checkbox).
final class GrupoModificador {
  String nombre;
  bool multiple;
  bool obligatorio;
  List<OpcionModificador> opciones;

  GrupoModificador({
    this.nombre = '',
    this.multiple = false,
    this.obligatorio = false,
    List<OpcionModificador>? opciones,
  }) : opciones = opciones ?? <OpcionModificador>[];

  factory GrupoModificador.desdeJson(Map<String, Object?> j) =>
      GrupoModificador(
        nombre: (j['Nombre'] ?? j['nombre'] ?? '') as String,
        multiple: (j['Multiple'] ?? j['multiple'] ?? false) as bool,
        obligatorio: (j['Obligatorio'] ?? j['obligatorio'] ?? false) as bool,
        opciones: ((j['Opciones'] ?? j['opciones']) as List<Object?>? ??
                const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(OpcionModificador.desdeJson)
            .toList(),
      );

  Map<String, Object?> aJson() => {
        'Nombre': nombre,
        'Multiple': multiple,
        'Obligatorio': obligatorio,
        'Opciones': opciones.map((o) => o.aJson()).toList(),
      };
}

/// Conjunto de grupos de modificadores de un producto.
final class PersonalizacionProducto {
  List<GrupoModificador> grupos;

  /// Si se permite escribir una nota libre para la cocina al vender.
  bool permiteNota;

  PersonalizacionProducto({
    List<GrupoModificador>? grupos,
    this.permiteNota = true,
  }) : grupos = grupos ?? <GrupoModificador>[];

  /// True si hay algo que personalizar (algún grupo con opciones o nota libre).
  /// Espeja `PersonalizacionProducto.TieneContenido`.
  bool get tieneContenido =>
      permiteNota || grupos.any((g) => g.opciones.isNotEmpty);

  factory PersonalizacionProducto.desdeJson(Map<String, Object?> j) =>
      PersonalizacionProducto(
        permiteNota: (j['PermiteNota'] ?? j['permiteNota'] ?? true) as bool,
        grupos:
            ((j['Grupos'] ?? j['grupos']) as List<Object?>? ?? const <Object?>[])
                .whereType<Map<String, Object?>>()
                .map(GrupoModificador.desdeJson)
                .toList(),
      );

  Map<String, Object?> aJson() => {
        'Grupos': grupos.map((g) => g.aJson()).toList(),
        'PermiteNota': permiteNota,
      };
}

/// (De)serialización tolerante hacia/desde `productos.personalizacion_json`.
///
/// Espeja `PersonalizacionSerializer`: si el JSON está vacío o corrupto
/// devuelve un objeto vacío con `permiteNota = false` (producto simple), nunca
/// lanza. Un JSON malo en un producto no puede impedir que se abra el POS.
abstract final class PersonalizacionSerializer {
  /// Devuelve null si no hay contenido (sin grupos y sin nota), igual que C#.
  static String? serializar(PersonalizacionProducto? p) {
    if (p == null || (p.grupos.isEmpty && !p.permiteNota)) return null;
    return jsonEncode(p.aJson());
  }

  /// Nunca devuelve null; vacío si no aplica.
  static PersonalizacionProducto deserializar(String? json) {
    if (json == null || json.trim().isEmpty) {
      return PersonalizacionProducto(permiteNota: false);
    }
    try {
      final decodificado = jsonDecode(json);
      if (decodificado is! Map<String, Object?>) {
        return PersonalizacionProducto(permiteNota: false);
      }
      return PersonalizacionProducto.desdeJson(decodificado);
    } on FormatException {
      return PersonalizacionProducto(permiteNota: false);
    }
  }
}
