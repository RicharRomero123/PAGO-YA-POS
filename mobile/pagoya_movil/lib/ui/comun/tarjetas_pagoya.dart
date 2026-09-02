import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Contenedor genérico — port del estilo `Tarjeta` de `PagoYaTheme.xaml`:
/// blanco, borde de 1 px y **esquinas cuadradas**.
class Tarjeta extends StatelessWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.relleno = const EdgeInsets.all(Espacios.lg),
    this.color,
    this.colorBorde,
    this.anchoBorde = 1,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry relleno;
  final Color? color;
  final Color? colorBorde;
  final double anchoBorde;

  /// Si se pasa, toda la tarjeta es tocable (target grande, ideal en móvil).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final caja = Container(
      padding: relleno,
      decoration: BoxDecoration(
        color: color ?? t.blanco,
        border: Border.all(color: colorBorde ?? t.borde, width: anchoBorde),
        borderRadius: BorderRadius.circular(t.radioTarjeta),
      ),
      child: child,
    );

    if (onTap == null) return caja;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: caja,
    );
  }
}

/// Tarjeta de **producto** de la grilla de cobro — port del estilo
/// `TarjetaProducto` de `PagoYaTheme.xaml`.
///
/// Diferencias móviles respecto de la PC (ergonomía, no marca):
/// - no hay hover: el estado de "recién tocado" se indica con [seleccionada],
///   que el llamador enciende un momento tras agregar al carrito;
/// - alto mínimo de 118 dp (PC: 112) para que quepan nombre de 2 líneas,
///   precio grande y stock sin apretar;
/// - el precio va abajo a la izquierda, en la línea de lectura del pulgar.
///
/// Es un widget **de presentación**: recibe strings ya formateados. El formato
/// de moneda y el cálculo de stock son de la capa de datos.
class TarjetaProducto extends StatelessWidget {
  const TarjetaProducto({
    super.key,
    required this.nombre,
    required this.precio,
    this.onTap,
    this.onLongPress,
    this.categoria,
    this.stock,
    this.sinStock = false,
    this.stockBajo = false,
    this.seleccionada = false,
    this.iconoAsset,
    this.emoji,
  });

  /// Nombre del producto (hasta 2 líneas).
  final String nombre;

  /// Precio ya formateado, p. ej. `S/ 3.50`.
  final String precio;

  final VoidCallback? onTap;

  /// Pulsación larga: el atajo natural en móvil para "cantidad exacta" o
  /// "editar producto" (en la PC eso es el clic derecho).
  final VoidCallback? onLongPress;

  /// Categoría, en pequeño arriba.
  final String? categoria;

  /// Stock ya formateado, p. ej. `12 und`. Se omite en productos preparados.
  final String? stock;

  /// Pinta el stock en rojo y baja la opacidad del icono.
  final bool sinStock;

  /// Pinta el stock en ámbar (por debajo del mínimo de reposición).
  final bool stockBajo;

  /// Resalta la tarjeta (equivalente del hover naranja del escritorio).
  final bool seleccionada;

  /// PNG opcional (rubro/categoría) desde [IconosPos].
  final String? iconoAsset;

  /// Emoji de respaldo cuando no hay PNG.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    final colorStock = sinStock
        ? t.error
        : stockBajo
            ? t.advertencia
            : t.muted;

    return Semantics(
      button: true,
      label: '$nombre, $precio',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: Toques.tarjetaProducto),
          padding: const EdgeInsets.all(Espacios.md),
          decoration: BoxDecoration(
            color: seleccionada ? t.primarioTinte : t.blanco,
            border: Border.all(
              color: seleccionada ? t.primario : t.borde,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(t.radioTarjeta),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (categoria != null)
                    Expanded(
                      child: Text(
                        categoria!.toUpperCase(),
                        style: tipos.etiqueta.copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  if (iconoAsset != null || emoji != null)
                    Opacity(
                      opacity: sinStock ? 0.4 : 1,
                      child: iconoAsset != null
                          ? IconoPos(
                              iconoAsset!,
                              tamano: 22,
                              respaldoEmoji: emoji,
                            )
                          : Text(emoji!, style: const TextStyle(fontSize: 20)),
                    ),
                ],
              ),
              const SizedBox(height: Espacios.xs),
              Text(
                nombre,
                style: tipos.cuerpoFuerte,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Espacios.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      precio,
                      style: tipos.precio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stock != null)
                    Text(
                      stock!,
                      style: tipos.muted.copyWith(
                        fontSize: 13,
                        color: colorStock,
                        fontWeight:
                            sinStock || stockBajo ? FontWeight.w700 : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de lista tocable con icono PNG a la izquierda: el patrón de navegación
/// del móvil (el escritorio usa un sidebar fijo, que en un celular no cabe).
/// Alto mínimo 64 dp.
class FilaAccion extends StatelessWidget {
  const FilaAccion({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.iconoAsset,
    this.emoji,
    this.onTap,
    this.trailing,
    this.destacado = false,
  });

  final String titulo;
  final String? subtitulo;
  final String? iconoAsset;
  final String? emoji;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Resalta la fila con el tinte naranja (módulo activo).
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(
          horizontal: Espacios.lg,
          vertical: Espacios.md,
        ),
        decoration: BoxDecoration(
          color: destacado ? t.primarioTinte : t.blanco,
          border: Border(bottom: BorderSide(color: t.borde)),
        ),
        child: Row(
          children: <Widget>[
            if (iconoAsset != null || emoji != null) ...<Widget>[
              iconoAsset != null
                  ? IconoPos(
                      iconoAsset!,
                      tamano: Toques.iconoLista,
                      respaldoEmoji: emoji,
                    )
                  : Text(emoji!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: Espacios.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(titulo, style: tipos.cuerpoFuerte),
                  if (subtitulo != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitulo!,
                      style: tipos.muted.copyWith(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: Espacios.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
