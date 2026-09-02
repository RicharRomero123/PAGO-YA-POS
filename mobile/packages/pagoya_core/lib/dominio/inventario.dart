// PagoYa Móvil — dominio/inventario.dart
//
// PORT de `Inventario.cs`.
//
// EL KARDEX ES LA FUENTE DE VERDAD DEL STOCK.
// `productos.stock_actual` es solo una caché para pintar la grilla del POS
// rápido. Cada venta, compra, merma o ajuste escribe aquí una fila
// APPEND-ONLY con identidad UUID estable, y por eso la sincronización la
// resuelve con "insert-if-absent" (union entre cajas) en vez de
// last-write-wins: sumar dos salidas concurrentes es correcto, pisar una con
// la otra pierde una venta.

library;

import 'entidad_base.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Movimiento de inventario (kardex).
final class Inventario extends EntidadBase {
  String productoId;

  /// Positiva para entradas (compra, ajuste +), negativa para salidas
  /// (venta, merma, ajuste −).
  double cantidad;

  /// Stock resultante tras aplicar el movimiento (snapshot informativo).
  ///
  /// NO se usa para reconstruir el stock: entre dos cajas concurrentes los
  /// snapshots son incoherentes. El stock se reconstruye sumando [cantidad].
  double stockResultante;

  /// Motivo legible (ej. "Venta M01-000123", "Compra", "Ajuste").
  String motivo;

  /// Referencia opcional al documento origen (ej. id de venta).
  String? referenciaId;

  DateTime fechaHora;

  Inventario({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.productoId = Uuid.vacio,
    this.cantidad = 0,
    this.stockResultante = 0,
    this.motivo = '',
    this.referenciaId,
    DateTime? fechaHora,
  }) : fechaHora = fechaHora ?? DateTime.now();

  factory Inventario.desdeFila(Map<String, Object?> f) => Inventario(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        productoId: Uuid.normalizar(Leer.texto(f, 'producto_id')),
        cantidad: (Leer.numero(f, 'cantidad') ?? 0).toDouble(),
        stockResultante: (Leer.numero(f, 'stock_resultante') ?? 0).toDouble(),
        motivo: Leer.texto(f, 'motivo'),
        referenciaId: Leer.textoNulable(f, 'referencia_id'),
        fechaHora:
            TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_hora')) ?? DateTime.now(),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'producto_id': productoId,
        'cantidad': cantidad,
        'stock_resultante': stockResultante,
        'motivo': motivo,
        'referencia_id': referenciaId,
        'fecha_hora': TiempoUtc.formatoO(fechaHora),
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'ProductoId': productoId,
        'Cantidad': cantidad,
        'StockResultante': stockResultante,
        'Motivo': motivo,
        'ReferenciaId': referenciaId,
        'FechaHora': TiempoUtc.formatoO(fechaHora),
      };

  factory Inventario.desdeJson(Map<String, Object?> j) => Inventario(
        id: Uuid.normalizar(j['Id'] as String?),
        productoId: Uuid.normalizar(j['ProductoId'] as String?),
        cantidad: (j['Cantidad'] as num?)?.toDouble() ?? 0,
        stockResultante: (j['StockResultante'] as num?)?.toDouble() ?? 0,
        motivo: (j['Motivo'] as String?) ?? '',
        referenciaId: j['ReferenciaId'] as String?,
        fechaHora: TiempoUtc.parsear(j['FechaHora'] as String?) ?? DateTime.now(),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Motivos canónicos del kardex. Se dejan como constantes porque el motivo
/// "Stock inicial" tiene semántica: es la fila de apertura sin la cual
/// `recalcularStockDesdeKardex` daría 0 para un producto sembrado.
abstract final class MotivosKardex {
  static const String stockInicial = 'Stock inicial';
  static const String ajuste = 'Ajuste';
  static const String compra = 'Compra';
  static const String merma = 'Merma';

  static String venta(String numero) => 'Venta $numero';
  static String anulacion(String numero) => 'Anulación venta $numero';
}
