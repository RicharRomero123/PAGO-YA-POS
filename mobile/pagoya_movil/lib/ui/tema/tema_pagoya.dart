import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tipografia_pagoya.dart';
import 'tokens_pagoya.dart';

/// Tema global de PagoYa Móvil. Es el **único** lugar donde se construye un
/// [ThemeData]: `app.dart` lo instala y ninguna pantalla vuelve a declarar
/// colores, fuentes ni radios.
///
/// Port de `src/PagoYa.Desktop/Themes/PagoYaTheme.xaml`: misma paleta, misma
/// tipografía (Baloo 2 marca / Nunito UI) y **radios en 0** — bordes cuadrados,
/// estética POS profesional. Los chips son la única excepción (radio 3).
abstract final class TemaPagoYa {
  /// Tema claro (el único del producto: el POS se usa al sol y necesita el
  /// máximo contraste; un tema oscuro empeoraría la lectura en exteriores).
  static ThemeData claro() {
    const t = TokensPagoYa.claro;
    final tipos = TiposPagoYa.desdeTokens(t);

    final esquema = ColorScheme.fromSeed(
      seedColor: t.primario,
      brightness: Brightness.light,
    ).copyWith(
      primary: t.primario,
      onPrimary: t.blanco,
      primaryContainer: t.primarioTinte,
      onPrimaryContainer: t.navy,
      secondary: t.navy,
      onSecondary: t.blanco,
      error: t.error,
      onError: t.blanco,
      errorContainer: t.errorTinte,
      onErrorContainer: t.navy,
      surface: t.blanco,
      onSurface: t.navy,
      surfaceContainerLowest: t.blanco,
      surfaceContainerLow: t.fondo,
      surfaceContainer: t.fondo,
      outline: t.borde,
      outlineVariant: t.borde,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: t.fondo,
      canvasColor: t.fondo,
      splashFactory: InkRipple.splashFactory,
      fontFamily: TokensPagoYa.fuenteUi,
      fontFamilyFallback: TokensPagoYa.fuentesRespaldo,
      extensions: <ThemeExtension<dynamic>>[t, tipos],
      visualDensity: VisualDensity.standard,

      // Todo el texto de Material hereda la escala de PagoYa.
      textTheme: TextTheme(
        displayLarge: tipos.total,
        headlineLarge: tipos.h1,
        headlineMedium: tipos.h2,
        titleLarge: tipos.h2,
        titleMedium: tipos.cuerpoFuerte,
        bodyLarge: tipos.cuerpo,
        bodyMedium: tipos.cuerpo,
        bodySmall: tipos.muted,
        labelLarge: tipos.boton.copyWith(color: t.navy),
        labelMedium: tipos.chip.copyWith(color: t.navy),
        labelSmall: tipos.etiqueta,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: t.blanco,
        foregroundColor: t.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: tipos.h2,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        shape: Border(bottom: BorderSide(color: t.borde, width: 1)),
      ),

      dividerTheme: DividerThemeData(color: t.borde, thickness: 1, space: 1),

      cardTheme: CardThemeData(
        color: t.blanco,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: t.borde, width: 1.5),
          borderRadius: BorderRadius.circular(t.radioTarjeta),
        ),
      ),

      // Inputs: borde de 1.5 (2 al enfocar, en naranja) y alto >= 48 dp.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.blanco,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Espacios.lg,
          vertical: Espacios.md,
        ),
        hintStyle: tipos.cuerpo.copyWith(color: t.muted),
        labelStyle: tipos.muted,
        floatingLabelStyle: tipos.muted.copyWith(color: t.primario),
        border: _borde(t, t.borde, 1.5),
        enabledBorder: _borde(t, t.borde, 1.5),
        focusedBorder: _borde(t, t.primario, 2),
        errorBorder: _borde(t, t.error, 1.5),
        focusedErrorBorder: _borde(t, t.error, 2),
        errorStyle: tipos.muted.copyWith(color: t.error),
      ),

      // Los botones concretos viven en `ui/comun/botones_pagoya.dart`; estos
      // temas cubren los `ElevatedButton`/`TextButton` que use Material por su
      // cuenta (diálogos, date pickers) para que no se salgan de la marca.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primario,
          foregroundColor: t.blanco,
          disabledBackgroundColor: t.primario.withValues(alpha: 0.5),
          disabledForegroundColor: t.blanco,
          elevation: 0,
          minimumSize: const Size(0, Toques.boton),
          padding: const EdgeInsets.symmetric(horizontal: Espacios.xl),
          textStyle: tipos.boton,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radioBoton),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: t.blanco,
          foregroundColor: t.navy,
          side: BorderSide(color: t.borde, width: 1.5),
          minimumSize: const Size(0, Toques.boton),
          padding: const EdgeInsets.symmetric(horizontal: Espacios.xl),
          textStyle: tipos.boton,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radioBoton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primario,
          minimumSize: const Size(0, Toques.minimo),
          textStyle: tipos.boton,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radioBoton),
          ),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.blanco,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.blanco,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: t.borde,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: t.blanco,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: tipos.h2,
        contentTextStyle: tipos.cuerpo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.navy,
        contentTextStyle: tipos.cuerpo.copyWith(color: t.blanco),
        actionTextColor: t.primarioTinte,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      listTileTheme: ListTileThemeData(
        tileColor: t.blanco,
        iconColor: t.muted,
        textColor: t.navy,
        titleTextStyle: tipos.cuerpoFuerte,
        subtitleTextStyle: tipos.muted,
        minVerticalPadding: Espacios.md,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.blanco,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.primarioTinte,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected)
              ? tipos.chip.copyWith(color: t.primario)
              : tipos.chip.copyWith(color: t.muted),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primario,
        linearTrackColor: t.borde,
        circularTrackColor: t.borde,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? t.blanco : t.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? t.primario : t.fondo,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? t.primario : t.borde,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? t.primario : t.blanco,
        ),
        checkColor: WidgetStateProperty.all(t.blanco),
        side: BorderSide(color: t.borde, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      // Sin ripple morado de Material por defecto.
      highlightColor: t.primarioTinte,
      splashColor: t.primarioTinte,
    );
  }

  static OutlineInputBorder _borde(TokensPagoYa t, Color color, double ancho) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(t.radioInput),
      borderSide: BorderSide(color: color, width: ancho),
    );
  }
}

/// Acceso corto a los tokens y a la tipografía desde cualquier widget.
///
/// ```dart
/// final t = context.tokens;
/// Text('Total', style: context.tipos.h2);
/// Container(color: t.primarioTinte);
/// ```
extension TemaPagoYaContexto on BuildContext {
  /// Tokens de marca (colores y radios). Nunca escribas un `Color(0x...)`
  /// literal en una pantalla: pide el token.
  TokensPagoYa get tokens =>
      Theme.of(this).extension<TokensPagoYa>() ?? TokensPagoYa.claro;

  /// Escala tipográfica de PagoYa.
  TiposPagoYa get tipos =>
      Theme.of(this).extension<TiposPagoYa>() ?? TiposPagoYa.base;
}
