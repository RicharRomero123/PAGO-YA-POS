import '../modelo/resultados.dart';
import 'contrato_impresora.dart';

/// Canal físico hacia una impresora. Existe para que
/// `ImpresoraTicketsBluetooth` no sepa nada de `print_bluetooth_thermal` ni de
/// `flutter_blue_plus`: solo pide "busca", "conecta", "escribe".
///
/// Añadir un transporte nuevo (USB OTG, red WiFi/9100, Sunmi integrada) es
/// implementar esta interfaz; no se toca ni el generador ni la UI.
abstract interface class TransporteImpresora {
  TipoConexionImpresora get tipo;

  /// `true` si este transporte se puede usar en la plataforma actual.
  /// El SPP clásico devuelve `false` en iOS.
  Future<bool> get soportado;

  /// `true` si el adaptador Bluetooth está encendido.
  Future<bool> get adaptadorEncendido;

  Future<List<ImpresoraDisponible>> buscar({
    Duration timeout = const Duration(seconds: 6),
  });

  Future<bool> get conectado;

  /// Abre el canal. Devuelve un resultado con mensaje amable si falla.
  Future<ResultadoImpresion> conectar(ImpresoraDisponible impresora);

  /// Escribe el flujo ESC/POS. Debe trocear internamente si el transporte lo
  /// exige (BLE tiene MTU chico).
  Future<ResultadoImpresion> escribir(List<int> bytes);

  Future<void> desconectar();

  Future<void> liberar();
}