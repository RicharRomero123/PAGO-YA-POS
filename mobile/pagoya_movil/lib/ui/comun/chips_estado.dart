import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Tono de un chip de estado — port de los estilos `ChipPagado`,
/// `ChipPendiente`, `ChipError` y `BadgeTier` de `PagoYaTheme.xaml`.
enum TonoChip {
  /// Verde `#DCFCE7` — pagado, sincronizado, caja abierta.
  exito,

  /// Ámbar `#FEF3C7` — pendiente, por vencer, periodo de gracia.
  advertencia,

  /// Rojo `#FEE2E2` — anulado, rechazado por SUNAT, licencia vencida.
  error,

  /// Naranja `#FDE3D3` — tier / función premium.
  marca,

  /// Gris — informativo, sin carga emocional.
  neutro,
}

/// Chip de estado. Único elemento del sistema con esquina redondeada (radio 3),
/// igual que en el escritorio.
///
/// Es de presentación pura: recibe el texto ya resuelto ("Pagado", "Anulado",
/// "Por vencer"). Nada de lógica de estado aquí.
class ChipEstado extends StatelessWidget {
  const ChipEstado(
    this.texto, {
    super.key,
    this.tono = TonoChip.neutro,
    this.iconoAsset,
    this.emoji,
  });

  const ChipEstado.exito(this.texto, {super.key, this.iconoAsset, this.emoji})
      : tono = TonoChip.exito;

  const ChipEstado.advertencia(
    this.texto, {
    super.key,
    this.iconoAsset,
    this.emoji,
  }) : tono = TonoChip.advertencia;

  const ChipEstado.error(this.texto, {super.key, this.iconoAsset, this.emoji})
      : tono = TonoChip.error;

  final String texto;
  final TonoChip tono;

  /// PNG opcional de [IconosPos] a la izquierda.
  final String? iconoAsset;

  /// Emoji opcional (o respaldo del PNG).
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (Color fondo, Color texto_) = switch (tono) {
      TonoChip.exito => (t.exitoTinte, t.exito),
      TonoChip.advertencia => (t.advertenciaTinte, t.advertencia),
      TonoChip.error => (t.errorTinte, t.error),
      TonoChip.marca => (t.primarioTinte, t.primarioPresionado),
      TonoChip.neutro => (t.fondo, t.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espacios.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(t.radioChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (iconoAsset != null) ...<Widget>[
            IconoPos(
              iconoAsset!,
              tamano: 14,
              color: texto_,
              respaldoEmoji: emoji,
            ),
            const SizedBox(width: 6),
          ] else if (emoji != null) ...<Widget>[
            Text(emoji!, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ],
          Text(texto, style: context.tipos.chip.copyWith(color: texto_)),
        ],
      ),
    );
  }
}

/// Los tres tiers del producto (`CLAUDE.md` § Modelo de Tiers).
enum TierPagoYa {
  base('PagoYa Base', 'S/ 20 pago único'),
  cloud('PagoYa Cloud', 'S/ 25 / mes'),
  facturadorPro('PagoYa Facturador Pro', 'Desde S/ 50 / mes');

  const TierPagoYa(this.nombre, this.precio);

  /// Nombre comercial, tal como se le vende al cliente.
  final String nombre;

  /// Precio de lista, para el copy del upsell.
  final String precio;
}

/// Badge del tier activo — port del estilo `BadgeTier`.
///
/// En Base va en gris (es el punto de partida, no un logro que celebrar);
/// en Cloud y Facturador Pro va en naranja de marca, porque el usuario está
/// pagando y el badge se lo recuerda.
class BadgeTier extends StatelessWidget {
  const BadgeTier(this.tier, {super.key, this.compacto = false});

  final TierPagoYa tier;

  /// `true` = solo la última palabra del nombre ("Base", "Cloud", "Pro"),
  /// para barras superiores estrechas.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final etiqueta = compacto
        ? tier.nombre.split(' ').last
        : tier.nombre.replaceFirst('PagoYa ', '');
    return ChipEstado(
      etiqueta,
      tono: tier == TierPagoYa.base ? TonoChip.neutro : TonoChip.marca,
    );
  }
}

/// Encabezado de sección: etiqueta en mayúsculas + línea. Reemplaza a los
/// `GroupBox` del escritorio, que en móvil desperdician alto de pantalla.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.accion});

  final String texto;

  /// Acción a la derecha ("Ver todo", "Editar").
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: Espacios.xl,
        bottom: Espacios.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(texto.toUpperCase(), style: context.tipos.etiqueta),
          ),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}
