import 'package:flutter/foundation.dart';

/// Contrato entre la pantalla de onboarding (`mobile-ux`) y la capa de datos
/// (`flutter-datos`, `pagoya_core/lib/rubros/`).
///
/// La pantalla **no** siembra la base ni conoce `drift`: recibe una función
/// [PrecargarRubro], la llama con la clave elegida y pinta lo que le devuelve.
/// Así el widget se puede probar con un doble sin base de datos, y `flutter-ui`
/// cablea la implementación real al montar la ruta.

/// Precarga la plantilla del rubro en SQLite y devuelve lo que se sembró, para
/// enseñárselo al usuario **de inmediato**.
///
/// Debe completar rápido (es una siembra local, sin red). Si lanza, la pantalla
/// muestra el error y deja reintentar sin perder la elección.
typedef PrecargarRubro = Future<ResumenCatalogoRubro> Function(String clave);

/// Lo que quedó cargado tras elegir el rubro. Es la **promesa del producto**:
/// el usuario ve su catálogo listo antes de tocar nada más, y por eso no
/// abandona en el primer minuto.
@immutable
class ResumenCatalogoRubro {
  const ResumenCatalogoRubro({
    required this.clave,
    this.categorias = const <String>[],
    this.productos = const <ProductoVistaPrevia>[],
    this.pieTicket = '',
    this.modulosExtra = const <String>[],
  });

  /// Clave del rubro sembrado.
  final String clave;

  /// Categorías sugeridas (`PlantillasRubro.Categorias`).
  final List<String> categorias;

  /// Productos de ejemplo sembrados (`PlantillasRubro.Productos`).
  /// Vacío para el rubro `otro`, que empieza con catálogo vacío.
  final List<ProductoVistaPrevia> productos;

  /// Pie de ticket sugerido (`PlantillasRubro.PieTicket`).
  final String pieTicket;

  /// Nombres de los módulos extra que el rubro habilita, ya legibles:
  /// "Mesas y comandas", "Habitaciones", "Vencimientos DIGEMID",
  /// "Alertas de reposición" (`MOBILE-ARQUITECTURA.md` §7).
  final List<String> modulosExtra;

  /// Cuántos productos se sembraron.
  int get cantidadProductos => productos.length;
}

/// Un producto sembrado, listo para pintar. Los importes llegan **ya
/// formateados** desde la capa de datos: el formato de moneda y el redondeo
/// son suyos, no de la UI (paridad con el escritorio, `Dinero`).
@immutable
class ProductoVistaPrevia {
  const ProductoVistaPrevia({
    required this.nombre,
    required this.categoria,
    required this.precio,
    this.emoji,
  });

  final String nombre;
  final String categoria;

  /// Precio ya formateado, p. ej. `S/ 3.50`.
  final String precio;

  /// Emoji opcional para la vista previa.
  final String? emoji;
}
