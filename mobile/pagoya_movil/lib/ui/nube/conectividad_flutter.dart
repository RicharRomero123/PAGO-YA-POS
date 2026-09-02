/// Adaptador de `connectivity_plus` al puerto [SensorConectividad] de
/// `pagoya_core`.
///
/// Vive en la app y no en el paquete porque `connectivity_plus` depende de
/// Flutter y `pagoya_core` es Dart puro por contrato
/// (`docs/MOBILE-ARQUITECTURA.md` §2).
///
/// AVISO IMPORTANTE: lo que reporta este sensor es la red **declarada por el
/// sistema**, no internet. Un wifi de mercado con portal cautivo reporta
/// `wifi` y no enruta nada. La verificación real la hace
/// [TransporteSync.hayInternet] contra `/health`; este sensor solo sirve para
/// (a) no gastar radio cuando claramente no hay nada y (b) detectar la
/// reconexión para disparar la sync oportunista.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pagoya_core/nube/nube.dart';

class SensorConectividadFlutter implements SensorConectividad {
  SensorConectividadFlutter({Connectivity? conectividad})
      : _conectividad = conectividad ?? Connectivity();

  final Connectivity _conectividad;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final StreamController<TipoRed> _ctrl = StreamController<TipoRed>.broadcast();

  @override
  Future<TipoRed> tipoActual() async {
    try {
      return _traducir(await _conectividad.checkConnectivity());
    } catch (_) {
      // Un plugin que falla no puede dejar la app sin sincronizar nunca: si no
      // sabemos qué red hay, asumimos que la hay y que la sonda decidirá.
      return TipoRed.otra;
    }
  }

  @override
  Stream<TipoRed> get cambios {
    _sub ??= _conectividad.onConnectivityChanged.listen(
      (resultados) => _ctrl.add(_traducir(resultados)),
      onError: (_) {},
    );
    return _ctrl.stream;
  }

  /// `connectivity_plus` >= 6 entrega una LISTA (un teléfono puede tener wifi y
  /// datos a la vez). Nos quedamos con la mejor: wifi > ethernet > móvil.
  static TipoRed _traducir(List<ConnectivityResult> resultados) {
    if (resultados.isEmpty) return TipoRed.ninguna;
    if (resultados.every((r) => r == ConnectivityResult.none)) {
      return TipoRed.ninguna;
    }
    if (resultados.contains(ConnectivityResult.wifi) ||
        resultados.contains(ConnectivityResult.ethernet)) {
      return TipoRed.wifi;
    }
    if (resultados.contains(ConnectivityResult.mobile)) return TipoRed.movil;
    return TipoRed.otra;
  }

  Future<void> liberar() async {
    await _sub?.cancel();
    _sub = null;
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}
