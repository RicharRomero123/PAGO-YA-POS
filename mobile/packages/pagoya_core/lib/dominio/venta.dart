// PagoYa Móvil — dominio/venta.dart
//
// PORT de `Venta.cs` y `DetalleVenta.cs`.
//
// FECHAS: `fechaHora` es hora LOCAL del negocio (el escritorio usa
// `DateTime.Now`), no UTC. Se serializa con desfase horario, igual que
// `DateTime.Now.ToString("o")`. Los reportes por día del escritorio filtran con
// `substr(fecha_hora, 1, 10)`, así que guardar UTC movería las ventas de la
// noche al día siguiente en Perú (UTC-5).

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Línea de detalle de una venta. El nombre y el precio quedan "congelados" al
/// momento de la venta para que los reportes históricos no cambien si luego se
/// edita el catálogo.
final class DetalleVenta extends EntidadBase {
  String ventaId;
  String productoId;
  String descripcionProducto;

  /// Cantidad vendida. `double` porque admite decimales (kg) y porque el
  /// escritorio la guarda en una columna REAL.
  double cantidad;
  Dinero precioUnitario;
  Dinero descuento;

  /// Importe de la línea = cantidad × precioUnitario − descuento.
  Dinero importe;

  DetalleVenta({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.ventaId = Uuid.vacio,
    this.productoId = Uuid.vacio,
    this.descripcionProducto = '',
    this.cantidad = 0,
    Dinero? precioUnitario,
    Dinero? descuento,
    Dinero? importe,
  })  : precioUnitario = precioUnitario ?? Dinero.cero,
        descuento = descuento ?? Dinero.cero,
        importe = importe ?? Dinero.cero;

  factory DetalleVenta.desdeFila(Map<String, Object?> f) => DetalleVenta(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        ventaId: Uuid.normalizar(Leer.texto(f, 'venta_id')),
        productoId: Uuid.normalizar(Leer.texto(f, 'producto_id')),
        descripcionProducto: Leer.texto(f, 'descripcion_producto'),
        cantidad: (Leer.numero(f, 'cantidad') ?? 0).toDouble(),
        precioUnitario: Dinero.desdeDb(Leer.numero(f, 'precio_unitario')),
        descuento: Dinero.desdeDb(Leer.numero(f, 'descuento')),
        importe: Dinero.desdeDb(Leer.numero(f, 'importe')),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'venta_id': ventaId,
        'producto_id': productoId,
        'descripcion_producto': descripcionProducto,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario.aDb(),
        'descuento': descuento.aDb(),
        'importe': importe.aDb(),
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'VentaId': ventaId,
        'ProductoId': productoId,
        'DescripcionProducto': descripcionProducto,
        'Cantidad': cantidad,
        'PrecioUnitario': precioUnitario.aDb(),
        'Descuento': descuento.aDb(),
        'Importe': importe.aDb(),
      };

  factory DetalleVenta.desdeJson(Map<String, Object?> j) => DetalleVenta(
        id: Uuid.normalizar(j['Id'] as String?),
        ventaId: Uuid.normalizar(j['VentaId'] as String?),
        productoId: Uuid.normalizar(j['ProductoId'] as String?),
        descripcionProducto: (j['DescripcionProducto'] as String?) ?? '',
        cantidad: (j['Cantidad'] as num?)?.toDouble() ?? 0,
        precioUnitario: Dinero.desdeDb(j['PrecioUnitario'] as num?),
        descuento: Dinero.desdeDb(j['Descuento'] as num?),
        importe: Dinero.desdeDb(j['Importe'] as num?),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Cabecera de una venta (transacción de cobro).
final class Venta extends EntidadBase {
  /// Correlativo legible por caja. En el móvil lleva prefijo de dispositivo
  /// (`M01-000123`) para no colisionar con la PC (`C01-...`).
  /// Ver `datos/correlativos.dart`.
  String numero;
  String cajaId;

  /// Hora LOCAL de la venta (para el ticket y los reportes por día).
  DateTime fechaHora;

  MetodoPago metodoPago;
  EstadoVenta estado;

  /// Suma de subtotales sin IGV (valor de venta).
  Dinero subTotal;

  /// Monto de IGV (18 %).
  Dinero igv;

  /// Total a pagar.
  Dinero total;

  /// Efectivo recibido (para calcular vuelto). Null si no aplica.
  Dinero? montoRecibido;

  String? comprobanteId;

  /// Líneas de la venta.
  List<DetalleVenta> detalles;

  Venta({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.numero = '',
    this.cajaId = Uuid.vacio,
    DateTime? fechaHora,
    this.metodoPago = MetodoPago.efectivo,
    this.estado = EstadoVenta.completada,
    Dinero? subTotal,
    Dinero? igv,
    Dinero? total,
    this.montoRecibido,
    this.comprobanteId,
    List<DetalleVenta>? detalles,
  })  : fechaHora = fechaHora ?? DateTime.now(),
        subTotal = subTotal ?? Dinero.cero,
        igv = igv ?? Dinero.cero,
        total = total ?? Dinero.cero,
        detalles = detalles ?? <DetalleVenta>[];

  factory Venta.desdeFila(Map<String, Object?> f) => Venta(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        numero: Leer.texto(f, 'numero'),
        cajaId: Uuid.normalizar(Leer.texto(f, 'caja_id')),
        fechaHora:
            TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_hora')) ?? DateTime.now(),
        metodoPago: MetodoPago.desde(Leer.entero(f, 'metodo_pago')),
        estado: EstadoVenta.desde(Leer.entero(f, 'estado')),
        subTotal: Dinero.desdeDb(Leer.numero(f, 'sub_total')),
        igv: Dinero.desdeDb(Leer.numero(f, 'igv')),
        total: Dinero.desdeDb(Leer.numero(f, 'total')),
        montoRecibido: Dinero.desdeDbNulable(Leer.numero(f, 'monto_recibido')),
        comprobanteId: Leer.textoNulable(f, 'comprobante_id'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'numero': numero,
        'caja_id': cajaId,
        'fecha_hora': TiempoUtc.formatoOLocal(fechaHora),
        'metodo_pago': metodoPago.valor,
        'estado': estado.valor,
        'sub_total': subTotal.aDb(),
        'igv': igv.aDb(),
        'total': total.aDb(),
        'monto_recibido': montoRecibido?.aDb(),
        'comprobante_id': comprobanteId,
      };

  /// Snapshot completo (cabecera + detalles) para el outbox, en PascalCase.
  /// `OutboxStore.AplicarVentaAsync` del escritorio recorre `Detalles`, así que
  /// la clave debe llamarse exactamente así.
  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Numero': numero,
        'CajaId': cajaId,
        'FechaHora': TiempoUtc.formatoOLocal(fechaHora),
        'MetodoPago': metodoPago.valor,
        'Estado': estado.valor,
        'SubTotal': subTotal.aDb(),
        'Igv': igv.aDb(),
        'Total': total.aDb(),
        'MontoRecibido': montoRecibido?.aDb(),
        'ComprobanteId': comprobanteId,
        'Detalles': detalles.map((d) => d.aJson()).toList(),
      };

  factory Venta.desdeJson(Map<String, Object?> j) => Venta(
        id: Uuid.normalizar(j['Id'] as String?),
        numero: (j['Numero'] as String?) ?? '',
        cajaId: Uuid.normalizar(j['CajaId'] as String?),
        fechaHora: TiempoUtc.parsear(j['FechaHora'] as String?) ?? DateTime.now(),
        metodoPago: MetodoPago.desde((j['MetodoPago'] as num?)?.toInt()),
        estado: EstadoVenta.desde((j['Estado'] as num?)?.toInt()),
        subTotal: Dinero.desdeDb(j['SubTotal'] as num?),
        igv: Dinero.desdeDb(j['Igv'] as num?),
        total: Dinero.desdeDb(j['Total'] as num?),
        montoRecibido: Dinero.desdeDbNulable(j['MontoRecibido'] as num?),
        comprobanteId: j['ComprobanteId'] as String?,
        detalles: ((j['Detalles'] as List<Object?>?) ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(DetalleVenta.desdeJson)
            .toList(),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
