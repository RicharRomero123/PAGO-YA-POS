import 'package:flutter/material.dart';

import '../comun/comun.dart';
import '../tema/tema.dart';
import 'contrato_onboarding.dart';
import 'pantalla_catalogo_listo.dart';
import 'rubros_ui.dart';

/// **Pantalla clave del producto:** al crear la cuenta el usuario elige su tipo
/// de negocio y la app queda usable en el mismo segundo.
///
/// Dos pasos, uno detrás del otro sin salir de la pantalla:
///
/// 1. **Grilla de rubros** (los 9 de `PlantillasRubro`, mismas claves, nombres
///    y descripciones), en tarjetas grandes de dos columnas.
/// 2. **Catálogo precargado** ([PantallaCatalogoListo]): apenas termina la
///    siembra, el usuario ve sus categorías y sus productos ya cargados. Esa
///    prueba inmediata es lo que evita el abandono en el primer minuto.
///
/// Ergonomía: la grilla se desplaza, pero cada tarjeta mide ~150 dp de alto
/// (muy por encima de los 48 dp mínimos) y el encabezado es corto para que la
/// primera fila entre en la mitad inferior de la pantalla, al alcance del
/// pulgar. No hay botón "Continuar": tocar la tarjeta **es** la acción.
class PantallaElegirRubro extends StatefulWidget {
  const PantallaElegirRubro({
    super.key,
    required this.onPrecargar,
    required this.onListo,
    this.nombreNegocio,
  });

  /// Siembra la plantilla del rubro y devuelve lo que quedó cargado.
  /// La implementación real vive en `pagoya_core/lib/rubros/`.
  final PrecargarRubro onPrecargar;

  /// Se invoca cuando el usuario confirma y entra al POS, con la clave elegida.
  final ValueChanged<String> onListo;

  /// Nombre del negocio recién creado, para personalizar el saludo.
  final String? nombreNegocio;

  @override
  State<PantallaElegirRubro> createState() => _PantallaElegirRubroState();
}

class _PantallaElegirRubroState extends State<PantallaElegirRubro> {
  RubroUi? _elegido;
  bool _sembrando = false;
  String? _error;
  ResumenCatalogoRubro? _resumen;

  Future<void> _elegir(RubroUi rubro) async {
    if (_sembrando) return;
    setState(() {
      _elegido = rubro;
      _sembrando = true;
      _error = null;
    });
    try {
      final resumen = await widget.onPrecargar(rubro.clave);
      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _sembrando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sembrando = false;
        _error = 'No pudimos preparar tu catálogo. Vuelve a intentarlo.';
      });
    }
  }

  void _volverAElegir() {
    setState(() {
      _resumen = null;
      _elegido = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Paso 2: el catálogo ya sembrado.
    final resumen = _resumen;
    if (resumen != null && _elegido != null) {
      return PantallaCatalogoListo(
        rubro: _elegido!,
        resumen: resumen,
        onEmpezar: () => widget.onListo(_elegido!.clave),
        onCambiarRubro: _volverAElegir,
      );
    }

    // Paso 1: la grilla.
    return Scaffold(
      backgroundColor: t.fondo,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Encabezado(nombreNegocio: widget.nombreNegocio),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacios.lg,
                  0,
                  Espacios.lg,
                  Espacios.md,
                ),
                child: _BannerError(
                  mensaje: _error!,
                  onReintentar: () {
                    final r = _elegido;
                    if (r != null) _elegir(r);
                  },
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Espacios.lg,
                  0,
                  Espacios.lg,
                  Espacios.xxl,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: Espacios.md,
                  crossAxisSpacing: Espacios.md,
                  mainAxisExtent: 158,
                ),
                itemCount: RubrosUi.todos.length,
                itemBuilder: (context, i) {
                  final rubro = RubrosUi.todos[i];
                  return _TarjetaRubro(
                    rubro: rubro,
                    seleccionada: _elegido?.clave == rubro.clave,
                    ocupado: _sembrando,
                    onTap: () => _elegir(rubro),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // Barra inferior solo mientras se siembra: el usuario ve que algo pasa
      // sin que le tapemos la grilla con un diálogo modal.
      bottomNavigationBar: _sembrando
          ? BarraAccionInferior(
              accionPrimaria: BotonPrimario(
                texto: 'Preparando tu catálogo…',
                cargando: true,
                onPressed: () {},
              ),
            )
          : null,
    );
  }
}

/// Banner de fallo de la siembra. No usa [AvisoLicencia] a propósito: eso es
/// para el estado de la licencia, no para un error técnico recuperable.
class _BannerError extends StatelessWidget {
  const _BannerError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espacios.lg,
        vertical: Espacios.md,
      ),
      decoration: BoxDecoration(
        color: t.errorTinte,
        border: Border(left: BorderSide(color: t.error, width: 4)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              mensaje,
              style: context.tipos.cuerpo.copyWith(fontSize: 15),
            ),
          ),
          const SizedBox(width: Espacios.sm),
          BotonFantasma(
            texto: 'Reintentar',
            color: t.error,
            onPressed: onReintentar,
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({this.nombreNegocio});

  final String? nombreNegocio;

  @override
  Widget build(BuildContext context) {
    final tipos = context.tipos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Espacios.lg,
        Espacios.xl,
        Espacios.lg,
        Espacios.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            nombreNegocio == null || nombreNegocio!.isEmpty
                ? '¿Qué tipo de negocio tienes?'
                : '${nombreNegocio!}, ¿qué tipo de negocio es?',
            style: tipos.h1,
          ),
          const SizedBox(height: Espacios.sm),
          Text(
            'Elige tu rubro y dejamos el POS con categorías y productos de '
            'ejemplo listos para vender.',
            style: tipos.muted,
          ),
        ],
      ),
    );
  }
}

/// Tarjeta grande de rubro: icono PNG (emoji de respaldo), nombre y
/// descripción. Todo el bloque es el objetivo táctil.
class _TarjetaRubro extends StatelessWidget {
  const _TarjetaRubro({
    required this.rubro,
    required this.seleccionada,
    required this.ocupado,
    required this.onTap,
  });

  final RubroUi rubro;
  final bool seleccionada;
  final bool ocupado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    return Semantics(
      button: true,
      selected: seleccionada,
      label: '${rubro.nombre}. ${rubro.descripcion}',
      child: Opacity(
        opacity: ocupado && !seleccionada ? 0.45 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: ocupado ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(Espacios.lg),
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
              children: <Widget>[
                SizedBox(
                  height: Toques.iconoGrande,
                  child: rubro.tieneIcono
                      ? IconoPos(
                          rubro.iconoImagen,
                          tamano: Toques.iconoGrande,
                          respaldoEmoji: rubro.emoji,
                        )
                      : Text(
                          rubro.emoji,
                          style: const TextStyle(fontSize: 36),
                        ),
                ),
                const SizedBox(height: Espacios.md),
                Text(
                  rubro.nombre,
                  style: tipos.cuerpoFuerte.copyWith(fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    rubro.descripcion,
                    style: tipos.muted.copyWith(fontSize: 13),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
