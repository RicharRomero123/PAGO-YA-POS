import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/tema.dart';

/// Input de búsqueda grande — port del estilo `BuscadorGrande` de
/// `PagoYaTheme.xaml` (60 dp de alto, borde de 2 px que se pone naranja al
/// enfocar, esquinas cuadradas).
///
/// **Diferencia móvil deliberada:** lleva pegado a la derecha un botón de
/// **escáner** de 48 dp. En la PC el código de barras entra por el lector USB
/// como si fuera teclado; en el celular la cámara *es* el lector, y es el
/// diferenciador del producto — por eso está a la vista, no escondido en un
/// menú. Si el rubro no usa códigos (restaurante), pasa `onEscanear: null` y
/// el botón desaparece.
///
/// Widget de presentación: no busca ni filtra nada, solo emite [onCambio] y
/// [onEnviar].
class BuscadorGrande extends StatefulWidget {
  const BuscadorGrande({
    super.key,
    this.controlador,
    this.foco,
    this.pista = 'Buscar producto o código',
    this.onCambio,
    this.onEnviar,
    this.onEscanear,
    this.autofoco = false,
    this.soloNumeros = false,
  });

  final TextEditingController? controlador;
  final FocusNode? foco;

  /// Texto de ayuda dentro del campo.
  final String pista;

  final ValueChanged<String>? onCambio;

  /// Se dispara al pulsar "buscar" en el teclado o al leer un código con un
  /// lector físico Bluetooth (que envía Enter al final).
  final ValueChanged<String>? onEnviar;

  /// Abre el escáner de cámara. Si es `null` no se muestra el botón.
  final VoidCallback? onEscanear;

  final bool autofoco;

  /// Teclado numérico (búsqueda por código de barras tecleado a mano).
  final bool soloNumeros;

  @override
  State<BuscadorGrande> createState() => _BuscadorGrandeState();
}

class _BuscadorGrandeState extends State<BuscadorGrande> {
  late final TextEditingController _ctrl =
      widget.controlador ?? TextEditingController();
  late final FocusNode _foco = widget.foco ?? FocusNode();
  bool _propioCtrl = false;
  bool _propioFoco = false;
  bool _enfocado = false;
  bool _conTexto = false;

  @override
  void initState() {
    super.initState();
    _propioCtrl = widget.controlador == null;
    _propioFoco = widget.foco == null;
    _conTexto = _ctrl.text.isNotEmpty;
    _ctrl.addListener(_alEscribir);
    _foco.addListener(_alEnfocar);
  }

  void _alEscribir() {
    final tiene = _ctrl.text.isNotEmpty;
    if (tiene != _conTexto) setState(() => _conTexto = tiene);
  }

  void _alEnfocar() => setState(() => _enfocado = _foco.hasFocus);

  @override
  void dispose() {
    _ctrl.removeListener(_alEscribir);
    _foco.removeListener(_alEnfocar);
    if (_propioCtrl) _ctrl.dispose();
    if (_propioFoco) _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            height: Toques.buscador,
            decoration: BoxDecoration(
              color: t.blanco,
              border: Border.all(
                color: _enfocado ? t.primario : t.borde,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(t.radioInput),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: Espacios.md),
                IconoPos(
                  IconosPos.buscar,
                  tamano: 22,
                  color: _enfocado ? t.primario : t.muted,
                ),
                const SizedBox(width: Espacios.sm),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _foco,
                    autofocus: widget.autofoco,
                    style: tipos.cuerpo.copyWith(fontSize: 19),
                    cursorColor: t.primario,
                    textInputAction: TextInputAction.search,
                    keyboardType: widget.soloNumeros
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: widget.soloNumeros
                        ? <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ]
                        : null,
                    onChanged: widget.onCambio,
                    onSubmitted: widget.onEnviar,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: widget.pista,
                      hintStyle: tipos.cuerpo.copyWith(
                        fontSize: 19,
                        color: t.muted,
                      ),
                    ),
                  ),
                ),
                if (_conTexto)
                  _BotonIcono(
                    icono: IconosPos.cerrar,
                    semantica: 'Limpiar búsqueda',
                    onTap: () {
                      _ctrl.clear();
                      widget.onCambio?.call('');
                    },
                  ),
                const SizedBox(width: Espacios.xs),
              ],
            ),
          ),
        ),
        if (widget.onEscanear != null) ...<Widget>[
          const SizedBox(width: Espacios.sm),
          Semantics(
            button: true,
            label: 'Escanear código con la cámara',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onEscanear,
              child: Container(
                width: Toques.buscador,
                height: Toques.buscador,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primario,
                  borderRadius: BorderRadius.circular(t.radioBoton),
                ),
                child: IconoPos(
                  IconosPos.escaner,
                  tamano: 28,
                  color: t.blanco,
                  respaldoEmoji: '📷',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BotonIcono extends StatelessWidget {
  const _BotonIcono({
    required this.icono,
    required this.onTap,
    this.semantica,
  });

  final String icono;
  final VoidCallback onTap;
  final String? semantica;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantica,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: Toques.minimo,
          height: Toques.minimo,
          child: Center(
            child: IconoPos(icono, tamano: 20, color: context.tokens.muted),
          ),
        ),
      ),
    );
  }
}
