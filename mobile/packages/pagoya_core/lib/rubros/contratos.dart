/// Contrato del **onboarding por rubro**: qué precarga la app cuando el dueño
/// elige su tipo de negocio.
///
/// Espejo de `src/PagoYa.Desktop/Servicios/PlantillasRubro.cs`. Dueño de ESTE
/// archivo: `mobile-lead`. Lo implementa `flutter-datos` en `lib/rubros/`,
/// portando las plantillas **sin cambiar una sola clave** — el enum
/// `RubroNegocio` y las claves string (`bodega`, `restaurante`, …) son contrato
/// compartido con el escritorio y con la configuración persistida.
///
/// Lo consume `mobile-ux` en la pantalla de elección de rubro.
///
/// ## Arbitraje de `ProductoPlantilla` (pasada final, §4.2)
///
/// Yo declaraba aquí un `ProductoPlantilla` de seis campos y `flutter-datos`
/// declaró otro de once en `plantillas_rubro.dart`, con los campos DIGEMID
/// (principio activo, registro sanitario, receta, lote, `mesesVence`) y con la
/// corrección de `AddMonths` que hace que un lote sembrado el día 31 venza el
/// mismo día en la PC y en el celular.
///
/// **Gana el suyo**: es el que tiene implementación (`SembradorCatalogo`) y
/// tests (`test/rubros/plantillas_rubro_test.dart`), y el mío no tenía ninguna
/// de las dos cosas. Aquí ya no se declara: se **reexporta** el suyo, para que
/// quien importe `rubros/contratos.dart` (o el barril `pagoya_core.dart`)
/// siga encontrando el tipo con un solo import y sin ambigüedad.
library;

import 'package:meta/meta.dart';

import '../dominio/enums.dart';
import 'plantillas_rubro.dart';

/// `ProductoPlantilla` es de `flutter-datos` (`plantillas_rubro.dart`). Ver la
/// nota de arbitraje en la cabecera de este archivo.
export 'plantillas_rubro.dart' show ProductoPlantilla;

/// Catálogo de plantillas por rubro. Es puro dato: no toca la base.
///
/// Implementa: `flutter-datos` (`lib/rubros/plantillas_rubro.dart`).
abstract interface class CatalogoPlantillasRubro {
  /// Rubros ofrecidos en el onboarding, en el orden en que se muestran.
  List<RubroNegocio> get rubrosDisponibles;

  /// Plantilla de un rubro. [RubroNegocio.otro] devuelve una plantilla vacía:
  /// arranca sin catálogo, a propósito.
  PlantillaRubro obtener(RubroNegocio rubro);

  /// `true` para los rubros de comida (`restaurante`, `cafeteria`, `polleria`).
  ///
  /// Portado de `PlantillasRubro.EsRubroComida`. Es lo que decide si aparecen
  /// Mesas, comandas y personalización de productos.
  bool esRubroComida(RubroNegocio rubro);
}

/// Todo lo que un rubro precarga al elegirlo en el onboarding.
@immutable
final class PlantillaRubro {
  /// Crea la plantilla de un rubro.
  const PlantillaRubro({
    required this.rubro,
    required this.nombreVisible,
    required this.descripcion,
    required this.categorias,
    required this.productosEjemplo,
    required this.modulos,
    this.pieTicket = '¡Gracias por su compra!',
  });

  /// Rubro al que pertenece.
  final RubroNegocio rubro;

  /// Nombre para la tarjeta del onboarding (p. ej. `Bodega / Minimarket`).
  final String nombreVisible;

  /// Frase corta que ayuda a elegir (p. ej. `Abarrotes, bebidas, snacks`).
  final String descripcion;

  /// Categorías sugeridas, en orden de aparición.
  final List<String> categorias;

  /// Productos de ejemplo para que la app quede usable de inmediato. El dueño
  /// puede borrarlos; el punto es que nadie vea un catálogo vacío el día 1.
  final List<ProductoPlantilla> productosEjemplo;

  /// Módulos extra que este rubro enciende. Ver [ModuloRubro].
  final Set<ModuloRubro> modulos;

  /// Pie de ticket por defecto.
  final String pieTicket;
}

// `ProductoPlantilla` se declaraba aquí. Retirado en la pasada final de
// reconciliación: el canónico es el de `plantillas_rubro.dart` (flutter-datos),
// reexportado arriba. Ver la nota de arbitraje en la cabecera y §4.2.

/// Módulos que un rubro puede encender. Portado de la tabla de
/// MOBILE-ARQUITECTURA §7.
///
/// Ojo con la diferencia respecto al feature-gating: esto es **preferencia del
/// negocio**, no licencia. Que aparezca "Mesas" depende del rubro; que
/// funcione la nube depende del flag firmado. Nunca mezclar los dos
/// mecanismos.
enum ModuloRubro {
  /// Catálogo simple. Siempre presente.
  catalogo,

  /// Mesas, comandas y personalización de productos (rubros de comida).
  mesas,

  /// Habitaciones, estadías y consumos cargados al cuarto (hotel).
  habitaciones,

  /// Campos DIGEMID: principio activo, registro sanitario, lote, vencimiento,
  /// receta (farmacia).
  digemid,

  /// Stock mínimo y alertas de reposición (ferretería).
  alertasReposicion,
}
