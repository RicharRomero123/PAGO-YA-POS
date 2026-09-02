/// Feature gating visible: los módulos sin flag firmado se muestran **con
/// candado y upsell**, nunca ocultos sin explicación.
///
/// Reparto de responsabilidades (MOBILE-ARQUITECTURA §3):
/// - **`mobile-ux`** pone los visuales (`ContenidoUpsell`,
///   `TarjetaFuncionBloqueada`, `PanelUpsell`, `CandadoSobre`) en
///   `ui/comun/funcion_bloqueada.dart`. Esos widgets no leen el token.
/// - **`flutter-licencia`** (este archivo) decide **si hay flag**, y siempre
///   contra el token firmado — nunca por tier ni por bandera local.
///
/// El upsell es parte del modelo de negocio (CLAUDE.md): Base se vende barato
/// (S/ 20 pago único) y el ingreso está en Cloud y Facturador Pro. Ocultar una
/// función mata la conversión; mostrarla rota mata la confianza.
///
/// ```dart
/// GuardiaCaracteristica(
///   caracteristica: CaracteristicaLicencia.invoicing,
///   child: const PantallaFacturacion(),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import '../comun/funcion_bloqueada.dart';
import 'proveedores_licencia.dart';

/// Copy de upsell que corresponde a cada flag. El texto es de `mobile-ux`; aquí
/// solo se hace el mapeo flag → copy.
ContenidoUpsell upsellDe(CaracteristicaLicencia caracteristica) =>
    switch (caracteristica) {
      CaracteristicaLicencia.invoicing => ContenidoUpsell.facturacion,
      CaracteristicaLicencia.cloudSync => ContenidoUpsell.cloud,
      CaracteristicaLicencia.multiSite => ContenidoUpsell.multisede,
    };

/// Muestra [child] solo si el flag está habilitado por el token **firmado**;
/// si no, la tarjeta de función bloqueada de `mobile-ux`.
class GuardiaCaracteristica extends ConsumerWidget {
  const GuardiaCaracteristica({
    required this.caracteristica,
    required this.child,
    this.onMejorarPlan,
    this.alBloquear,
    super.key,
  });

  /// Flag que exige este módulo.
  final CaracteristicaLicencia caracteristica;

  /// El módulo real.
  final Widget child;

  /// Qué hacer al pulsar "Mejora tu plan". Lo cablea `flutter-ui` (tiene el
  /// router y el número de soporte).
  final VoidCallback? onMejorarPlan;

  /// Alternativa a la tarjeta por defecto, si una pantalla necesita otra cosa.
  final Widget? alBloquear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(caracteristicaProvider(caracteristica))) return child;

    return alBloquear ??
        TarjetaFuncionBloqueada(
          contenido: upsellDe(caracteristica),
          onMejorarPlan: onMejorarPlan,
        );
  }
}

/// Versión en línea: deja el widget visible pero atenuado y con candado; al
/// tocarlo abre el panel de upsell. Para botones y filas de menú, donde sacar
/// el elemento de la pantalla confundiría al usuario.
class BloqueoEnLinea extends ConsumerWidget {
  const BloqueoEnLinea({
    required this.caracteristica,
    required this.child,
    this.onMejorarPlan,
    super.key,
  });

  /// Flag que exige la acción.
  final CaracteristicaLicencia caracteristica;

  /// El control real.
  final Widget child;

  /// Qué hacer al pulsar "Mejora tu plan".
  final VoidCallback? onMejorarPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CandadoSobre(
        bloqueado: !ref.watch(caracteristicaProvider(caracteristica)),
        contenido: upsellDe(caracteristica),
        onMejorarPlan: onMejorarPlan,
        child: child,
      );
}

/// Tarjeta compacta para la grilla de módulos del inicio. No consulta la
/// licencia: quien la pinta ya decidió que el módulo está bloqueado (con
/// `caracteristicaProvider`).
class TarjetaModuloBloqueado extends StatelessWidget {
  const TarjetaModuloBloqueado({
    required this.caracteristica,
    this.onMejorarPlan,
    super.key,
  });

  /// Flag que exige el módulo.
  final CaracteristicaLicencia caracteristica;

  /// Qué hacer al pulsar "Mejora tu plan".
  final VoidCallback? onMejorarPlan;

  @override
  Widget build(BuildContext context) => TarjetaFuncionBloqueada(
        contenido: upsellDe(caracteristica),
        onMejorarPlan: onMejorarPlan,
        compacta: true,
      );
}
