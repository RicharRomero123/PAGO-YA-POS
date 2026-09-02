import 'package:flutter/material.dart';

import 'tokens_pagoya.dart';

/// Estilos de texto de PagoYa — port de §4 de `PagoYaTheme.xaml`
/// (H1, H2, Body, Muted, Precio, Total, ChipTexto) más los que el móvil necesita.
///
/// **Ajuste móvil deliberado** (no es divergencia de marca, es ergonomía):
/// el escritorio se lee sentado a 60 cm; el móvil se lee de pie, al sol y a
/// veces a un brazo de distancia. Los tamaños de cuerpo suben un punto
/// (16 → 17, 14 → 15) y el `Total` baja de 56 a 52 para no desbordar en
/// pantallas de 360 dp de ancho. Familias, pesos y colores son los mismos.
@immutable
class TiposPagoYa extends ThemeExtension<TiposPagoYa> {
  const TiposPagoYa({
    required this.h1,
    required this.h2,
    required this.cuerpo,
    required this.cuerpoFuerte,
    required this.muted,
    required this.precio,
    required this.total,
    required this.boton,
    required this.botonCobrar,
    required this.chip,
    required this.etiqueta,
  });

  /// Título de pantalla / marca (Baloo 2 ExtraBold).
  final TextStyle h1;

  /// Subtítulo de sección (Baloo 2 Bold).
  final TextStyle h2;

  /// Texto de interfaz por defecto.
  final TextStyle cuerpo;

  /// Texto de interfaz destacado (nombre de producto, etiqueta de fila).
  final TextStyle cuerpoFuerte;

  /// Texto secundario / ayuda.
  final TextStyle muted;

  /// Precio en grilla y en el carrito.
  final TextStyle precio;

  /// El número **más grande** de la pantalla de cobro. El cliente lo mira
  /// desde el otro lado del mostrador.
  final TextStyle total;

  /// Texto de botón primario/secundario.
  final TextStyle boton;

  /// Texto del botón de cobrar (marca, ExtraBold).
  final TextStyle botonCobrar;

  /// Texto dentro de chips y badges.
  final TextStyle chip;

  /// Etiqueta pequeña en mayúsculas (encabezado de sección, unidad).
  final TextStyle etiqueta;

  /// Construye la escala a partir de los tokens (los colores salen de ahí).
  factory TiposPagoYa.desdeTokens(TokensPagoYa t) {
    const marca = TokensPagoYa.fuenteMarca;
    const ui = TokensPagoYa.fuenteUi;
    const respaldo = TokensPagoYa.fuentesRespaldo;

    return TiposPagoYa(
      h1: TextStyle(
        fontFamily: marca,
        fontFamilyFallback: respaldo,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: t.navy,
      ),
      h2: TextStyle(
        fontFamily: marca,
        fontFamilyFallback: respaldo,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: t.navy,
      ),
      cuerpo: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: t.navy,
      ),
      cuerpoFuerte: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: t.navy,
      ),
      muted: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: t.muted,
      ),
      precio: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.1,
        color: t.navy,
        // Cifras de ancho fijo: los precios de una columna quedan alineados.
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      total: TextStyle(
        fontFamily: marca,
        fontFamilyFallback: respaldo,
        fontSize: 52,
        fontWeight: FontWeight.w800,
        height: 1.05,
        color: t.navy,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      boton: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
      botonCobrar: TextStyle(
        fontFamily: marca,
        fontFamilyFallback: respaldo,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
      chip: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      etiqueta: TextStyle(
        fontFamily: ui,
        fontFamilyFallback: respaldo,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        height: 1.2,
        color: t.muted,
      ),
    );
  }

  /// Escala por defecto (tokens claros). Respaldo si el tema no está instalado.
  static final TiposPagoYa base = TiposPagoYa.desdeTokens(TokensPagoYa.claro);

  @override
  TiposPagoYa copyWith({
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? cuerpo,
    TextStyle? cuerpoFuerte,
    TextStyle? muted,
    TextStyle? precio,
    TextStyle? total,
    TextStyle? boton,
    TextStyle? botonCobrar,
    TextStyle? chip,
    TextStyle? etiqueta,
  }) {
    return TiposPagoYa(
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      cuerpo: cuerpo ?? this.cuerpo,
      cuerpoFuerte: cuerpoFuerte ?? this.cuerpoFuerte,
      muted: muted ?? this.muted,
      precio: precio ?? this.precio,
      total: total ?? this.total,
      boton: boton ?? this.boton,
      botonCobrar: botonCobrar ?? this.botonCobrar,
      chip: chip ?? this.chip,
      etiqueta: etiqueta ?? this.etiqueta,
    );
  }

  @override
  TiposPagoYa lerp(ThemeExtension<TiposPagoYa>? otro, double t) {
    if (otro is! TiposPagoYa) return this;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t) ?? a;
    return TiposPagoYa(
      h1: s(h1, otro.h1),
      h2: s(h2, otro.h2),
      cuerpo: s(cuerpo, otro.cuerpo),
      cuerpoFuerte: s(cuerpoFuerte, otro.cuerpoFuerte),
      muted: s(muted, otro.muted),
      precio: s(precio, otro.precio),
      total: s(total, otro.total),
      boton: s(boton, otro.boton),
      botonCobrar: s(botonCobrar, otro.botonCobrar),
      chip: s(chip, otro.chip),
      etiqueta: s(etiqueta, otro.etiqueta),
    );
  }
}
