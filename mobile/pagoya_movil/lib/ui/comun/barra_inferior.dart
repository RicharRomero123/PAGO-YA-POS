import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// **Barra de acción inferior — la pieza ergonómica clave del móvil.**
///
/// En el POS de escritorio las acciones viven arriba a la derecha, donde está
/// el mouse. En un celular grande esa esquina es el punto más lejano del
/// pulgar: el cajero tendría que recolocar la mano en cada venta, de pie y con
/// la otra mano ocupada. Por eso **toda acción primaria de una pantalla va
/// aquí**, fijada abajo, a todo el ancho y sobre el `SafeArea`.
///
/// Úsala como `bottomNavigationBar` del `Scaffold` para que quede fija mientras
/// la lista se desplaza. Recuerda dejar [Espacios.colchonBarraInferior] al
/// final de la lista para que no tape el último elemento.
class BarraAccionInferior extends StatelessWidget {
  const BarraAccionInferior({
    super.key,
    required this.accionPrimaria,
    this.resumen,
    this.accionSecundaria,
  });

  /// Botón principal (normalmente [BotonPrimario] o [BotonCobrar]).
  final Widget accionPrimaria;

  /// Fila de contexto encima del botón: total, cantidad de ítems, vuelto.
  /// El cliente mira esta zona, así que va en grande.
  final Widget? resumen;

  /// Acción alternativa a la izquierda del botón principal (por ejemplo
  /// "Guardar comanda"). Ocupa como máximo un tercio del ancho.
  final Widget? accionSecundaria;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: t.blanco,
        border: Border(top: BorderSide(color: t.borde)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Espacios.lg,
            Espacios.md,
            Espacios.lg,
            Espacios.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (resumen != null) ...<Widget>[
                resumen!,
                const SizedBox(height: Espacios.md),
              ],
              if (accionSecundaria == null)
                accionPrimaria
              else
                Row(
                  children: <Widget>[
                    Flexible(flex: 1, child: accionSecundaria!),
                    const SizedBox(width: Espacios.sm),
                    Expanded(flex: 2, child: accionPrimaria),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen de importe para la [BarraAccionInferior] y para la pantalla de
/// confirmación de cobro.
///
/// El total usa el estilo `total` (52 dp): tiene que leerse **a un brazo de
/// distancia**, porque el cliente mira la pantalla del celular para confirmar
/// cuánto paga y cuánto le devuelven.
class ResumenImporte extends StatelessWidget {
  const ResumenImporte({
    super.key,
    required this.etiqueta,
    required this.monto,
    this.detalle,
    this.tonoMonto,
  });

  /// "Total a pagar", "Su vuelto", "En caja".
  final String etiqueta;

  /// Monto ya formateado, p. ej. `S/ 42.50`.
  final String monto;

  /// Línea secundaria: "3 productos", "Efectivo S/ 50.00".
  final String? detalle;

  /// Color del monto. Por defecto navy; usa `tokens.exito` para el vuelto.
  final Color? tonoMonto;

  @override
  Widget build(BuildContext context) {
    final tipos = context.tipos;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(etiqueta.toUpperCase(), style: tipos.etiqueta),
              if (detalle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(detalle!, style: tipos.muted.copyWith(fontSize: 14)),
              ],
            ],
          ),
        ),
        const SizedBox(width: Espacios.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              monto,
              style: tipos.total.copyWith(
                fontSize: 40,
                color: tonoMonto ?? context.tokens.navy,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado vacío con icono, mensaje y (opcional) acción.
/// Reemplaza a las tablas vacías del escritorio, que en móvil se ven rotas.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.titulo,
    this.detalle,
    this.iconoAsset,
    this.emoji,
    this.accion,
  });

  final String titulo;
  final String? detalle;
  final String? iconoAsset;
  final String? emoji;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tipos = context.tipos;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacios.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (iconoAsset != null)
              Opacity(
                opacity: 0.5,
                child: IconoPos(
                  iconoAsset!,
                  tamano: 56,
                  color: context.tokens.muted,
                  respaldoEmoji: emoji,
                ),
              )
            else if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: Espacios.lg),
            Text(titulo, style: tipos.h2, textAlign: TextAlign.center),
            if (detalle != null) ...<Widget>[
              const SizedBox(height: Espacios.sm),
              Text(detalle!, style: tipos.muted, textAlign: TextAlign.center),
            ],
            if (accion != null) ...<Widget>[
              const SizedBox(height: Espacios.xl),
              accion!,
            ],
          ],
        ),
      ),
    );
  }
}
