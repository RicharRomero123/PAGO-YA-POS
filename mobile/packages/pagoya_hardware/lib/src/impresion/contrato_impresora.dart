import '../modelo/resultados.dart';
import '../modelo/ticket.dart';
import 'configuracion_impresion.dart';

/// Tipo de transporte Bluetooth de una impresora.
enum TipoConexionImpresora {
  /// Bluetooth **clásico / SPP** (RFCOMM). Es lo que usan casi todas las
  /// térmicas baratas del mercado peruano. Requiere emparejar desde los
  /// ajustes de Android. **No disponible en iOS** para apps de terceros.
  sppClasico('Bluetooth clásico'),

  /// Bluetooth **Low Energy** (GATT). Modelos más nuevos y única opción en iOS.
  ble('Bluetooth LE'),

  /// Impresora simulada (emulador / tests).
  simulada('Simulada');

  const TipoConexionImpresora(this.etiqueta);
  final String etiqueta;
}

/// Una impresora que la app puede usar.
class ImpresoraDisponible {
  const ImpresoraDisponible({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.emparejada = false,
    this.intensidadSenal,
  });

  /// Identificador estable del transporte: dirección MAC en Android SPP,
  /// `remoteId` en BLE (MAC en Android, UUID opaco en iOS).
  final String id;

  /// Nombre visible ("POS-58", "XP-P323B", "MTP-II").
  final String nombre;

  final TipoConexionImpresora tipo;

  /// SPP: ya está emparejada en los ajustes del sistema.
  final bool emparejada;

  /// RSSI en dBm, solo BLE. Sirve para ordenar por cercanía en la lista.
  final int? intensidadSenal;

  /// Clave para persistir la impresora elegida.
  String get clavePersistencia => '${tipo.name}:$id';

  static ({String id, TipoConexionImpresora tipo})? desdeClave(String clave) {
    final i = clave.indexOf(':');
    if (i <= 0) return null;
    final nombreTipo = clave.substring(0, i);
    final tipo = TipoConexionImpresora.values
        .where((t) => t.name == nombreTipo)
        .firstOrNull;
    if (tipo == null) return null;
    return (id: clave.substring(i + 1), tipo: tipo);
  }

  @override
  bool operator ==(Object other) =>
      other is ImpresoraDisponible && other.id == id && other.tipo == tipo;

  @override
  int get hashCode => Object.hash(id, tipo);

  @override
  String toString() => '$nombre (${tipo.etiqueta}, $id)';
}

extension _PrimeroONulo<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Estado de la conexión con la impresora, para que la UI muestre un indicador
/// honesto sin tener que preguntar en un `Timer`.
enum EstadoImpresora {
  /// Ninguna impresora elegida todavía.
  sinConfigurar,

  /// Elegida pero no conectada (lo normal entre venta y venta).
  desconectada,
  conectando,
  conectada,
  imprimiendo,

  /// Último intento falló. La UI ofrece "Reintentar" o "Compartir por WhatsApp".
  error,
}

/// **Interfaz de impresión de tickets.**
///
/// Es el equivalente móvil de `ITicketPrinter` del escritorio
/// (`src/PagoYa.Desktop/Servicios/Impresion/ITicketPrinter.cs`), con lo que el
/// móvil necesita de más: descubrir y elegir impresora, saber si está
/// conectada, y reimprimir el último ticket.
///
/// ## Contrato inviolable
///
/// **Ningún método lanza excepciones.** Todos devuelven [ResultadoImpresion].
/// La venta ya está guardada en SQLite y en el outbox antes de llegar aquí
/// (`docs/MOBILE-ARQUITECTURA.md` §5.3): un fallo de impresión **nunca** puede
/// abortar, revertir ni bloquear la venta. Como mucho, la UI ofrece reintentar
/// o mandar el comprobante por WhatsApp con `CompartirArchivo`.
abstract interface class ImpresoraTickets {
  /// Estado actual, para pintar el indicador de la barra superior.
  Stream<EstadoImpresora> get estado;

  /// Valor actual del estado sin esperar al stream.
  EstadoImpresora get estadoActual;

  /// Impresora elegida por el usuario, si hay.
  ImpresoraDisponible? get impresoraActual;

  /// `true` si hay un canal abierto ahora mismo.
  Future<bool> get estaConectada;

  /// `true` si el Bluetooth del teléfono está encendido.
  Future<bool> get bluetoothEncendido;

  /// Lista de impresoras que se pueden usar.
  ///
  /// - **SPP**: devuelve las ya emparejadas en los ajustes de Android. No hay
  ///   descubrimiento: emparejar es un paso del sistema operativo. La UI debe
  ///   explicarlo y ofrecer un botón que abra los ajustes de Bluetooth.
  /// - **BLE**: escanea durante [timeout] y devuelve las que anuncian un
  ///   servicio de impresión conocido.
  Future<List<ImpresoraDisponible>> buscarImpresoras({
    Duration timeout = const Duration(seconds: 6),
  });

  /// Elige y recuerda una impresora. La conexión física se abre bajo demanda
  /// al imprimir; esto solo persiste la elección.
  Future<ResultadoImpresion> seleccionarImpresora(ImpresoraDisponible impresora);

  /// Restaura la impresora guardada en un arranque previo. Llamar una vez al
  /// iniciar la app. Si no había ninguna, no hace nada.
  Future<void> restaurarImpresoraGuardada();

  /// Abre la conexión explícitamente (botón "Conectar" de Configuración).
  Future<ResultadoImpresion> conectar();

  /// Cierra la conexión. No falla si ya estaba cerrada.
  Future<void> desconectar();

  /// Olvida la impresora elegida.
  Future<void> olvidarImpresora();

  /// **Imprime el ticket de una venta.** Nunca lanza.
  ///
  /// Si la conexión se cayó (lo normal: estas impresoras se desconectan solas),
  /// reconecta y reintenta una vez antes de rendirse.
  Future<ResultadoImpresion> imprimirTicket(
    TicketVenta ticket, {
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  });

  /// Reimprime el último ticket impreso o intentado. Es el botón "Imprimir de
  /// nuevo": el caso más frecuente en una bodega es que se acabó el papel o la
  /// impresora estaba apagada. Marca el ticket como reimpresión.
  Future<ResultadoImpresion> reimprimirUltimo();

  /// Último ticket enviado a imprimir (o intentado). `null` si aún no hubo.
  TicketVenta? get ultimoTicket;

  /// Escribe bytes ESC/POS crudos. Escotilla para casos que el generador aún
  /// no cubre (reportes de cierre de caja, comandas de cocina).
  Future<ResultadoImpresion> imprimirBytes(List<int> bytes);

  /// Pulso al cajón portamonedas (`ESC p`). Botón "Probar cajón".
  Future<ResultadoImpresion> abrirCajon({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
  });

  /// Ticket de prueba con tildes y regla de columnas, para validar el ancho
  /// de papel antes de la primera venta.
  Future<ResultadoImpresion> probarImpresion({
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String nombreNegocio = 'PagoYa',
  });

  /// Libera recursos.
  Future<void> liberar();
}