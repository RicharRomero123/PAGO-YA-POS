import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Botones de PagoYa — port de §5 de `PagoYaTheme.xaml`
/// (BotonPrimario, BotonCobrar, BotonSecundario, BotonMini) con las alturas
/// subidas para el pulgar.
///
/// Los tres primeros ocupan **todo el ancho disponible por defecto**: en móvil
/// un botón angosto alineado a la derecha (como en la barra de acciones del
/// escritorio) es difícil de acertar de pie y con una mano ocupada. Envuélvelos
/// en un `SizedBox`/`Row` si necesitas otra medida.

/// Botón **primario** naranja. Una sola acción primaria por pantalla.
class BotonPrimario extends StatelessWidget {
  const BotonPrimario({
    super.key,
    required this.texto,
    this.onPressed,
    this.icono,
    this.cargando = false,
    this.expandido = true,
    this.alto = Toques.boton,
  });

  final String texto;
  final VoidCallback? onPressed;

  /// Ruta de PNG de [IconosPos] a la izquierda del texto (opcional).
  final String? icono;

  /// Muestra un spinner y deshabilita el botón.
  final bool cargando;

  /// `true` = ocupa todo el ancho (por defecto en móvil).
  final bool expandido;

  final double alto;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;
    final habilitado = onPressed != null && !cargando;

    return _Pulsable(
      onPressed: habilitado ? onPressed : null,
      alto: alto,
      expandido: expandido,
      radio: t.radioBoton,
      colorNormal: t.primario,
      colorPresionado: t.primarioPresionado,
      colorDeshabilitado: t.primario.withValues(alpha: 0.5),
      contenido: _ContenidoBoton(
        texto: texto,
        estilo: tipos.boton.copyWith(color: t.blanco),
        icono: icono,
        colorIcono: t.blanco,
        cargando: cargando,
        colorSpinner: t.blanco,
      ),
    );
  }
}

/// Botón **de cobrar**: la acción más grande y más abajo de la pantalla.
/// 88 dp de alto (el escritorio usa 80) y tipografía de marca a 26.
class BotonCobrar extends StatelessWidget {
  const BotonCobrar({
    super.key,
    required this.texto,
    this.onPressed,
    this.cargando = false,
  });

  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;
    final habilitado = onPressed != null && !cargando;

    return _Pulsable(
      onPressed: habilitado ? onPressed : null,
      alto: Toques.botonCobrar,
      expandido: true,
      radio: t.radioBoton,
      colorNormal: t.primario,
      colorPresionado: t.primarioPresionado,
      colorDeshabilitado: t.primario.withValues(alpha: 0.5),
      contenido: _ContenidoBoton(
        texto: texto,
        estilo: tipos.botonCobrar.copyWith(color: t.blanco),
        cargando: cargando,
        colorSpinner: t.blanco,
      ),
    );
  }
}

/// Botón **secundario**: contorno sobre blanco. Acción alternativa
/// ("Ahora no", "Cancelar", "Guardar borrador").
class BotonSecundario extends StatelessWidget {
  const BotonSecundario({
    super.key,
    required this.texto,
    this.onPressed,
    this.icono,
    this.expandido = true,
    this.alto = Toques.boton,
  });

  final String texto;
  final VoidCallback? onPressed;
  final String? icono;
  final bool expandido;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;
    final habilitado = onPressed != null;

    return _Pulsable(
      onPressed: onPressed,
      alto: alto,
      expandido: expandido,
      radio: t.radioBoton,
      colorNormal: t.blanco,
      colorPresionado: t.fondo,
      colorDeshabilitado: t.blanco,
      borde: BorderSide(
        color: habilitado ? t.borde : t.borde.withValues(alpha: 0.5),
        width: 1.5,
      ),
      bordePresionado: BorderSide(color: t.primario, width: 1.5),
      opacidadDeshabilitado: 0.5,
      contenido: _ContenidoBoton(
        texto: texto,
        estilo: tipos.boton.copyWith(color: t.navy, fontWeight: FontWeight.w600),
        icono: icono,
        colorIcono: t.navy,
      ),
    );
  }
}

/// Botón **fantasma**: sin fondo ni borde. Acciones terciarias y destructivas
/// suaves ("Omitir", "Ver detalle", "Cerrar sesión").
class BotonFantasma extends StatelessWidget {
  const BotonFantasma({
    super.key,
    required this.texto,
    this.onPressed,
    this.icono,
    this.color,
    this.expandido = false,
    this.alto = Toques.minimo,
  });

  final String texto;
  final VoidCallback? onPressed;
  final String? icono;

  /// Color del texto. Por defecto el naranja de marca; pásale `tokens.error`
  /// para acciones destructivas o `tokens.muted` para las de baja jerarquía.
  final Color? color;

  final bool expandido;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;
    final c = color ?? t.primario;

    return _Pulsable(
      onPressed: onPressed,
      alto: alto,
      expandido: expandido,
      radio: t.radioBoton,
      colorNormal: Colors.transparent,
      colorPresionado: t.primarioTinte,
      colorDeshabilitado: Colors.transparent,
      relleno: const EdgeInsets.symmetric(horizontal: Espacios.md),
      contenido: _ContenidoBoton(
        texto: texto,
        estilo: tipos.boton.copyWith(color: c),
        icono: icono,
        colorIcono: c,
      ),
    );
  }
}

/// Botón **mini** cuadrado para cantidad (+ / −) y acciones de fila.
/// 48 dp (el escritorio usa 40): en móvil se toca con el pulgar.
class BotonMini extends StatelessWidget {
  const BotonMini({
    super.key,
    required this.simbolo,
    this.onPressed,
    this.lado = Toques.botonMini,
    this.semantica,
  });

  /// Un carácter: `+`, `−`, `×`.
  final String simbolo;
  final VoidCallback? onPressed;
  final double lado;
  final String? semantica;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: semantica,
      child: _Pulsable(
        onPressed: onPressed,
        alto: lado,
        ancho: lado,
        expandido: false,
        radio: t.radioBoton,
        colorNormal: t.fondo,
        colorPresionado: t.primarioTinte,
        colorDeshabilitado: t.fondo,
        opacidadDeshabilitado: 0.5,
        borde: BorderSide(color: t.borde, width: 1),
        bordePresionado: BorderSide(color: t.primario, width: 1),
        relleno: EdgeInsets.zero,
        contenido: Text(
          simbolo,
          style: context.tipos.cuerpoFuerte.copyWith(fontSize: 22),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interno: la mecánica compartida de pulsado (equivalente al ControlTemplate
// con Triggers del XAML). Sin lógica de negocio, solo estados visuales.
// ---------------------------------------------------------------------------

class _Pulsable extends StatefulWidget {
  const _Pulsable({
    required this.contenido,
    required this.alto,
    required this.radio,
    required this.colorNormal,
    required this.colorPresionado,
    required this.colorDeshabilitado,
    this.onPressed,
    this.ancho,
    this.expandido = true,
    this.borde,
    this.bordePresionado,
    this.relleno = const EdgeInsets.symmetric(horizontal: Espacios.xl),
    this.opacidadDeshabilitado = 1,
  });

  final Widget contenido;
  final VoidCallback? onPressed;
  final double alto;
  final double? ancho;
  final bool expandido;
  final double radio;
  final Color colorNormal;
  final Color colorPresionado;
  final Color colorDeshabilitado;
  final BorderSide? borde;
  final BorderSide? bordePresionado;
  final EdgeInsets relleno;
  final double opacidadDeshabilitado;

  @override
  State<_Pulsable> createState() => _PulsableState();
}

class _PulsableState extends State<_Pulsable> {
  bool _presionado = false;

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.onPressed != null;
    final fondo = !habilitado
        ? widget.colorDeshabilitado
        : (_presionado ? widget.colorPresionado : widget.colorNormal);
    final borde = _presionado && widget.bordePresionado != null
        ? widget.bordePresionado!
        : widget.borde;

    final caja = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      height: widget.alto,
      width: widget.ancho,
      padding: widget.relleno,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(widget.radio),
        border: borde == null ? null : Border.fromBorderSide(borde),
      ),
      child: widget.contenido,
    );

    return Opacity(
      opacity: habilitado ? 1 : widget.opacidadDeshabilitado,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: habilitado ? (_) => setState(() => _presionado = true) : null,
        onTapUp: habilitado ? (_) => setState(() => _presionado = false) : null,
        onTapCancel:
            habilitado ? () => setState(() => _presionado = false) : null,
        onTap: widget.onPressed,
        child: widget.expandido
            ? SizedBox(width: double.infinity, child: caja)
            : caja,
      ),
    );
  }
}

class _ContenidoBoton extends StatelessWidget {
  const _ContenidoBoton({
    required this.texto,
    required this.estilo,
    this.icono,
    this.colorIcono,
    this.cargando = false,
    this.colorSpinner,
  });

  final String texto;
  final TextStyle estilo;
  final String? icono;
  final Color? colorIcono;
  final bool cargando;
  final Color? colorSpinner;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colorSpinner ?? context.tokens.blanco,
        ),
      );
    }

    final etiqueta = Text(
      texto,
      style: estilo,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    if (icono == null) return etiqueta;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconoPos(icono!, tamano: 22, color: colorIcono),
        const SizedBox(width: Espacios.sm),
        Flexible(child: etiqueta),
      ],
    );
  }
}
