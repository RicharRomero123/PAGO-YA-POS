import 'package:flutter/material.dart';

/// Tokens de marca de PagoYa — **port literal** de
/// `src/PagoYa.Desktop/Themes/PagoYaTheme.xaml` (§1 Paleta, §3 Radios).
///
/// Regla del sistema: **nadie más define colores en la app móvil**. Si una
/// pantalla necesita un color, sale de aquí (`context.tokens`). Si el token no
/// existe, se pide a `mobile-ux`, no se inventa un `Color(0x...)` suelto.
///
/// Se instala como [ThemeExtension] en el [ThemeData] de `TemaPagoYa`, de modo
/// que `Theme.of(context).extension<TokensPagoYa>()` siempre lo resuelve.
@immutable
class TokensPagoYa extends ThemeExtension<TokensPagoYa> {
  const TokensPagoYa({
    required this.primario,
    required this.primarioPresionado,
    required this.primarioTinte,
    required this.navy,
    required this.exito,
    required this.advertencia,
    required this.error,
    required this.exitoTinte,
    required this.advertenciaTinte,
    required this.errorTinte,
    required this.fondo,
    required this.borde,
    required this.muted,
    required this.blanco,
    required this.radioTarjeta,
    required this.radioBoton,
    required this.radioInput,
    required this.radioChip,
  });

  // --- Paleta (Color.* del XAML) ---

  /// `#F26522` — Naranja PagoYa. Acción primaria, foco, selección.
  final Color primario;

  /// `#D14E12` — Naranja presionado (hover/pressed en escritorio).
  final Color primarioPresionado;

  /// `#FDE3D3` — Tinte naranja. Fondo de selección y de badges de tier.
  final Color primarioTinte;

  /// `#14253F` — Navy. Color de texto por defecto y base de la marca.
  final Color navy;

  /// `#16A34A` — Éxito (pagado, sincronizado).
  final Color exito;

  /// `#F59E0B` — Advertencia (pendiente, periodo de gracia).
  final Color advertencia;

  /// `#DC2626` — Error (anulado, licencia vencida, sin stock).
  final Color error;

  /// `#DCFCE7` — Fondo suave de chip de éxito.
  final Color exitoTinte;

  /// `#FEF3C7` — Fondo suave de chip de advertencia.
  final Color advertenciaTinte;

  /// `#FEE2E2` — Fondo suave de chip de error.
  final Color errorTinte;

  /// `#F7F8FA` — Fondo de pantalla.
  final Color fondo;

  /// `#EDEFF3` — Borde de tarjetas, inputs y separadores.
  final Color borde;

  /// `#6B7280` — Texto secundario.
  final Color muted;

  /// `#FFFFFF` — Superficie de tarjetas y hojas.
  final Color blanco;

  // --- Radios (Corner.* del XAML): bordes cuadrados, estética POS ---

  /// 0 — tarjetas cuadradas.
  final double radioTarjeta;

  /// 0 — botones cuadrados.
  final double radioBoton;

  /// 0 — inputs cuadrados.
  final double radioInput;

  /// 3 — único radio no nulo del sistema (chips y badges).
  final double radioChip;

  /// Paleta clara: la única del producto (el POS se usa al sol, siempre claro).
  static const TokensPagoYa claro = TokensPagoYa(
    primario: Color(0xFFF26522),
    primarioPresionado: Color(0xFFD14E12),
    primarioTinte: Color(0xFFFDE3D3),
    navy: Color(0xFF14253F),
    exito: Color(0xFF16A34A),
    advertencia: Color(0xFFF59E0B),
    error: Color(0xFFDC2626),
    exitoTinte: Color(0xFFDCFCE7),
    advertenciaTinte: Color(0xFFFEF3C7),
    errorTinte: Color(0xFFFEE2E2),
    fondo: Color(0xFFF7F8FA),
    borde: Color(0xFFEDEFF3),
    muted: Color(0xFF6B7280),
    blanco: Color(0xFFFFFFFF),
    radioTarjeta: 0,
    radioBoton: 0,
    radioInput: 0,
    radioChip: 3,
  );

  // --- Familias tipográficas (FuenteMarca / FuenteUI del XAML) ---

  /// Fuente de **marca**: Baloo 2 ExtraBold. Títulos, total, botón de cobrar.
  static const String fuenteMarca = 'Baloo2';

  /// Fuente de **interfaz**: Nunito. Todo el resto del texto.
  static const String fuenteUi = 'Nunito';

  /// Respaldo cuando los `.ttf` no están empaquetados (equivalente móvil del
  /// `, Segoe UI` del XAML). Flutter cae a la fuente del sistema sin romper.
  static const List<String> fuentesRespaldo = <String>[
    'Roboto',
    'Noto Sans',
    'sans-serif',
  ];

  @override
  TokensPagoYa copyWith({
    Color? primario,
    Color? primarioPresionado,
    Color? primarioTinte,
    Color? navy,
    Color? exito,
    Color? advertencia,
    Color? error,
    Color? exitoTinte,
    Color? advertenciaTinte,
    Color? errorTinte,
    Color? fondo,
    Color? borde,
    Color? muted,
    Color? blanco,
    double? radioTarjeta,
    double? radioBoton,
    double? radioInput,
    double? radioChip,
  }) {
    return TokensPagoYa(
      primario: primario ?? this.primario,
      primarioPresionado: primarioPresionado ?? this.primarioPresionado,
      primarioTinte: primarioTinte ?? this.primarioTinte,
      navy: navy ?? this.navy,
      exito: exito ?? this.exito,
      advertencia: advertencia ?? this.advertencia,
      error: error ?? this.error,
      exitoTinte: exitoTinte ?? this.exitoTinte,
      advertenciaTinte: advertenciaTinte ?? this.advertenciaTinte,
      errorTinte: errorTinte ?? this.errorTinte,
      fondo: fondo ?? this.fondo,
      borde: borde ?? this.borde,
      muted: muted ?? this.muted,
      blanco: blanco ?? this.blanco,
      radioTarjeta: radioTarjeta ?? this.radioTarjeta,
      radioBoton: radioBoton ?? this.radioBoton,
      radioInput: radioInput ?? this.radioInput,
      radioChip: radioChip ?? this.radioChip,
    );
  }

  @override
  TokensPagoYa lerp(ThemeExtension<TokensPagoYa>? otro, double t) {
    if (otro is! TokensPagoYa) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    double d(double a, double b) => a + (b - a) * t;
    return TokensPagoYa(
      primario: c(primario, otro.primario),
      primarioPresionado: c(primarioPresionado, otro.primarioPresionado),
      primarioTinte: c(primarioTinte, otro.primarioTinte),
      navy: c(navy, otro.navy),
      exito: c(exito, otro.exito),
      advertencia: c(advertencia, otro.advertencia),
      error: c(error, otro.error),
      exitoTinte: c(exitoTinte, otro.exitoTinte),
      advertenciaTinte: c(advertenciaTinte, otro.advertenciaTinte),
      errorTinte: c(errorTinte, otro.errorTinte),
      fondo: c(fondo, otro.fondo),
      borde: c(borde, otro.borde),
      muted: c(muted, otro.muted),
      blanco: c(blanco, otro.blanco),
      radioTarjeta: d(radioTarjeta, otro.radioTarjeta),
      radioBoton: d(radioBoton, otro.radioBoton),
      radioInput: d(radioInput, otro.radioInput),
      radioChip: d(radioChip, otro.radioChip),
    );
  }
}

/// Escala de espaciado (múltiplos de 4). Usa estas constantes en vez de
/// números mágicos: mantiene el ritmo vertical igual en todas las pantallas.
abstract final class Espacios {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Aire que hay que dejar al final de una lista para que la barra de acción
  /// inferior (zona del pulgar) no tape el último elemento.
  static const double colchonBarraInferior = 104;
}

/// Tamaños táctiles. El escritorio se opera con teclado y mouse (targets de
/// 40–52 px); el móvil se opera **con un pulgar, de pie**: nada baja de 48 dp.
abstract final class Toques {
  /// Mínimo absoluto de cualquier elemento tocable (guía Material/WCAG).
  static const double minimo = 48;

  /// Alto del botón primario móvil (escritorio: 52 → móvil: 56).
  static const double boton = 56;

  /// Alto del botón de **cobrar** (escritorio: 80 → móvil: 88, zona del pulgar).
  static const double botonCobrar = 88;

  /// Alto del buscador grande / lector de código.
  static const double buscador = 60;

  /// Botón mini circular de cantidad (+ / −). El escritorio usa 40; en móvil
  /// sube a 48 porque se toca con el pulgar, no se apunta con el mouse.
  static const double botonMini = 48;

  /// Alto mínimo de una tarjeta de producto en la grilla de cobro.
  static const double tarjetaProducto = 118;

  /// Lado del icono PNG dentro de una tarjeta grande (rubro, módulo).
  static const double iconoGrande = 48;

  /// Lado del icono PNG en listas y barras.
  static const double iconoLista = 28;
}
