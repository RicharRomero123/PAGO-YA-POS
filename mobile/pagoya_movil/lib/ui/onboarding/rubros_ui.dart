import 'package:flutter/foundation.dart';

import '../tema/tema.dart';

/// Metadatos de presentación de un rubro — port de `RubroInfo` de
/// `src/PagoYa.Desktop/Servicios/PlantillasRubro.cs`.
///
/// **Contrato con el escritorio:** [clave], [nombre] y [descripcion] son
/// literalmente los mismos strings que en C#. La clave se persiste en
/// `configuracion.rubro` y viaja en la sync: si diverge, el móvil y la PC
/// cargarían plantillas distintas para el mismo negocio.
///
/// Esto es **solo metadata de UI**. Las categorías, los productos de ejemplo y
/// el pie de ticket viven en `pagoya_core/lib/rubros/` (dueño: `flutter-datos`).
@immutable
class RubroUi {
  const RubroUi({
    required this.clave,
    required this.nombre,
    required this.emoji,
    required this.descripcion,
    this.iconoImagen = '',
  });

  /// Clave persistida: `bodega`, `restaurante`, `cafeteria`, `polleria`,
  /// `farmacia`, `ferreteria`, `licoreria`, `hotel`, `otro`.
  final String clave;

  /// Nombre comercial mostrado en la tarjeta.
  final String nombre;

  /// Emoji de respaldo (el `Icono` de `RubroInfo`), usado cuando el rubro no
  /// tiene PNG propio o cuando el asset no carga.
  final String emoji;

  /// Una línea de qué trae la plantilla.
  final String descripcion;

  /// Ruta del PNG en [IconosPos]; cadena vacía si el rubro usa solo emoji.
  final String iconoImagen;

  /// `true` si hay PNG que mostrar.
  bool get tieneIcono => iconoImagen.isNotEmpty;
}

/// Los **9 rubros** del onboarding, en el mismo orden que
/// `PlantillasRubro.Todos`.
///
/// Diferencia con el escritorio (deliberada, iconografía): en C# `cafeteria` y
/// `polleria` van sin PNG porque el set de la PC no tenía uno adecuado; el set
/// móvil sí trae `cubiertos`, así que los tres rubros de comida comparten el
/// mismo icono, igual que ya hacía `IconosPos.deRubro`. `licoreria` y `otro`
/// siguen cayendo al emoji, como en la PC.
abstract final class RubrosUi {
  static const List<RubroUi> todos = <RubroUi>[
    RubroUi(
      clave: 'bodega',
      nombre: 'Bodega / Minimarket',
      emoji: '🛒',
      descripcion: 'Abarrotes, bebidas, snacks y golosinas.',
      iconoImagen: IconosPos.rubroBodega,
    ),
    RubroUi(
      clave: 'restaurante',
      nombre: 'Restaurante / Menú',
      emoji: '🍽',
      descripcion: 'Entradas, platos de fondo, bebidas y postres.',
      iconoImagen: IconosPos.rubroRestaurante,
    ),
    RubroUi(
      clave: 'cafeteria',
      nombre: 'Cafetería / Juguería',
      emoji: '☕',
      descripcion: 'Cafés, jugos, sándwiches y postres.',
      iconoImagen: IconosPos.rubroRestaurante,
    ),
    RubroUi(
      clave: 'polleria',
      nombre: 'Pollería / Parrilla',
      emoji: '🍗',
      descripcion: 'Pollos a la brasa, parrillas y guarniciones.',
      iconoImagen: IconosPos.rubroRestaurante,
    ),
    RubroUi(
      clave: 'farmacia',
      nombre: 'Farmacia / Botica',
      emoji: '💊',
      descripcion: 'Medicamentos, cuidado personal e higiene.',
      iconoImagen: IconosPos.rubroFarmacia,
    ),
    RubroUi(
      clave: 'ferreteria',
      nombre: 'Ferretería',
      emoji: '🔨',
      descripcion: 'Herramientas, gasfitería, electricidad.',
      iconoImagen: IconosPos.rubroFerreteria,
    ),
    RubroUi(
      clave: 'licoreria',
      nombre: 'Licorería',
      emoji: '🍻',
      descripcion: 'Cervezas, licores, vinos y gaseosas.',
    ),
    RubroUi(
      clave: 'hotel',
      nombre: 'Hotel / Hospedaje',
      emoji: '🏨',
      descripcion: 'Habitaciones, consumos y servicios.',
      iconoImagen: IconosPos.rubroHotel,
    ),
    RubroUi(
      clave: 'otro',
      nombre: 'Otro giro',
      emoji: '🏪',
      descripcion: 'Empieza con el catálogo vacío y agrégalo tú.',
    ),
  ];

  /// Port de `PlantillasRubro.Info`: nunca devuelve nulo, cae a `bodega`.
  static RubroUi info(String? clave) {
    for (final r in todos) {
      if (r.clave == clave) return r;
    }
    return todos.first;
  }

  /// Port de `PlantillasRubro.EsRubroComida`: rubros que atienden en salón y
  /// habilitan **Mesas + comandas** y la personalización de productos.
  static bool esRubroComida(String? clave) {
    final c = (clave ?? '').toLowerCase();
    return c == 'restaurante' || c == 'polleria' || c == 'cafeteria';
  }
}
