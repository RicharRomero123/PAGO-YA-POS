import 'dart:async';

// `widgets.dart` re-exporta `foundation.dart` (ValueNotifier/ValueListenable).
import 'package:flutter/widgets.dart';

import '../modelo/resultados.dart';
import 'contrato_escaner.dart';

/// Implementación **falsa** de [EscanerCodigos].
///
/// Resuelve dos problemas reales:
/// 1. **El emulador de Android no tiene cámara usable** para leer códigos de
///    barras. Sin esto, la pantalla de cobro no se puede probar sin un teléfono
///    físico conectado.
/// 2. **Tests de widget**: `mobile_scanner` necesita canal de plataforma; en
///    `flutter test` no existe.
///
/// [construirVista] devuelve un panel con botones que emiten códigos de
/// [catalogoSimulado], así el flujo completo (escanear → buscar producto →
/// agregar al carrito) se puede recorrer en el emulador.
class EscanerFalso implements EscanerCodigos {
  EscanerFalso({
    this.permiso = EstadoPermiso.concedido,
    List<String>? catalogoSimulado,
  }) : catalogoSimulado = catalogoSimulado ??
            // Códigos de la plantilla de bodega de `PlantillasRubro.cs`, para
            // que al escanear en el emulador aparezca un producto de verdad.
            const <String>[
              '7501055', // Inca Kola 500ml
              '7501056', // Coca Cola 500ml
              '7502001', // Arroz Costeño 1kg
              '7503010', // Papas Lay's
              '7503012', // Chocolate Sublime
            ];

  /// Permiso que se simula. Poner [EstadoPermiso.denegadoPermanentemente]
  /// permite probar la pantalla de "abre Ajustes".
  EstadoPermiso permiso;

  final List<String> catalogoSimulado;

  /// Sesiones abiertas por esta instancia, para que un test pueda inyectar
  /// lecturas desde fuera con [SesionEscaneoFalsa.simularLectura].
  final List<SesionEscaneoFalsa> sesiones = <SesionEscaneoFalsa>[];

  @override
  Future<EstadoPermiso> estadoPermiso() async => permiso;

  @override
  Future<EstadoPermiso> solicitarPermiso() async => permiso;

  @override
  Future<SesionEscaneo> abrirSesion({
    ModoEscaneo modo = ModoEscaneo.unico,
    Duration ignorarRepetidoDurante = const Duration(seconds: 2),
    bool conSonido = true,
    bool conVibracion = true,
    bool linternaAlIniciar = false,
    List<FormatoCodigo> formatos = FormatoCodigo.retailPeru,
  }) async {
    final s = SesionEscaneoFalsa(
      modo: modo,
      catalogo: catalogoSimulado,
      linternaEncendidaInicial: linternaAlIniciar,
    );
    sesiones.add(s);
    return s;
  }
}

/// Sesión simulada. Un test llama a [simularLectura] directamente; en el
/// emulador el usuario toca los botones del panel.
class SesionEscaneoFalsa implements SesionEscaneo {
  SesionEscaneoFalsa({
    this.modo = ModoEscaneo.unico,
    this.catalogo = const <String>[],
    bool linternaEncendidaInicial = false,
  }) : _linternaEncendida = ValueNotifier<bool>(linternaEncendidaInicial);

  final ModoEscaneo modo;
  final List<String> catalogo;

  final StreamController<CodigoLeido> _lecturas =
      StreamController<CodigoLeido>.broadcast();
  final ValueNotifier<bool> _linternaDisponible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _linternaEncendida;

  bool _cerrada = false;
  bool _pausada = false;

  /// Cuántas veces se alternó la cámara (para asserts en tests).
  int cambiosDeCamara = 0;

  /// Emite un código como si la cámara lo hubiera leído.
  void simularLectura(String valor, {String formato = 'ean13'}) {
    if (_cerrada || _pausada) return;
    _lecturas.add(CodigoLeido(
      valor: valor,
      formato: formato,
      momento: DateTime.now(),
    ));
    if (modo == ModoEscaneo.unico) _pausada = true;
  }

  @override
  Stream<CodigoLeido> get lecturas => _lecturas.stream;

  @override
  ValueListenable<bool> get linternaDisponible => _linternaDisponible;

  @override
  ValueListenable<bool> get linternaEncendida => _linternaEncendida;

  @override
  Future<void> alternarLinterna() async {
    _linternaEncendida.value = !_linternaEncendida.value;
  }

  @override
  Future<void> alternarCamara() async => cambiosDeCamara++;

  @override
  Future<void> pausar() async => _pausada = true;

  @override
  Future<void> reanudar() async => _pausada = false;

  @override
  Widget construirVista({
    BoxFit ajuste = BoxFit.cover,
    Widget? superposicion,
  }) {
    final panel = _PanelEscanerSimulado(
      catalogo: catalogo,
      alTocar: simularLectura,
    );
    if (superposicion == null) return panel;
    return Stack(fit: StackFit.expand, children: [panel, superposicion]);
  }

  @override
  Future<void> cerrar() async {
    if (_cerrada) return;
    _cerrada = true;
    _linternaDisponible.dispose();
    _linternaEncendida.dispose();
    await _lecturas.close();
  }
}

/// Panel que sustituye a la cámara en el emulador: una lista de códigos del
/// catálogo de ejemplo, tocables.
class _PanelEscanerSimulado extends StatelessWidget {
  const _PanelEscanerSimulado({
    required this.catalogo,
    required this.alTocar,
  });

  final List<String> catalogo;
  final void Function(String valor) alTocar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF20232A),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ESCÁNER SIMULADO\nToca un código para simular una lectura',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFBFC7D5), fontSize: 14),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: catalogo.length,
                itemBuilder: (context, i) {
                  final codigo = catalogo[i];
                  return GestureDetector(
                    onTap: () => alTocar(codigo),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E333D),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        codigo,
                        style: const TextStyle(
                          color: Color(0xFFF2F4F8),
                          fontSize: 18,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}