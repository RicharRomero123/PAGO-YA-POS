// PagoYa Móvil — dominio/restaurante.dart
//
// PORT de `Mesa.cs`, `Pedido.cs` y `PedidoLinea.cs`.
//
// Es el caso de uso ESTRELLA del móvil: el mozo toma la comanda en el celular
// y la cocina la ve al instante. Por eso `mesa`, `pedido` y `pedido_linea`
// tienen que entrar en la sincronización de ambos lados
// (docs/MOBILE-ARQUITECTURA.md §6.3) — hoy el `OutboxStore` del escritorio aún
// las ignora al aplicar cambios remotos; el móvil ya las EMITE para que el
// día que se amplíe el escritorio no haya que rehacer nada.

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Mesa del salón (rubro restaurante/cafetería/pollería).
final class Mesa extends EntidadBase {
  /// Número/nombre visible ("1", "Terraza 2").
  String numero;

  /// Zona/ambiente para agrupar el mapa.
  String? zona;
  int capacidad;
  EstadoMesa estado;
  String? notas;
  bool activa;

  Mesa({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.numero = '',
    this.zona,
    this.capacidad = 4,
    this.estado = EstadoMesa.libre,
    this.notas,
    this.activa = true,
  });

  /// Zona para agrupar (nunca vacía; "Salón" por defecto).
  /// Espeja `Mesa.ZonaAgrupacion`.
  String get zonaAgrupacion =>
      (zona == null || zona!.trim().isEmpty) ? 'Salón' : zona!;

  factory Mesa.desdeFila(Map<String, Object?> f) => Mesa(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        numero: Leer.texto(f, 'numero'),
        zona: Leer.textoNulable(f, 'zona'),
        capacidad: Leer.entero(f, 'capacidad', 4),
        estado: EstadoMesa.desde(Leer.entero(f, 'estado')),
        notas: Leer.textoNulable(f, 'notas'),
        activa: Leer.booleano(f, 'activa', true),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'numero': numero,
        'zona': zona,
        'capacidad': capacidad,
        'estado': estado.valor,
        'notas': notas,
        'activa': activa ? 1 : 0,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Numero': numero,
        'Zona': zona,
        'Capacidad': capacidad,
        'Estado': estado.valor,
        'Notas': notas,
        'Activa': activa,
      };

  factory Mesa.desdeJson(Map<String, Object?> j) => Mesa(
        id: Uuid.normalizar(j['Id'] as String?),
        numero: (j['Numero'] as String?) ?? '',
        zona: j['Zona'] as String?,
        capacidad: (j['Capacidad'] as num?)?.toInt() ?? 4,
        estado: EstadoMesa.desde((j['Estado'] as num?)?.toInt()),
        notas: j['Notas'] as String?,
        activa: (j['Activa'] as bool?) ?? true,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Línea de una comanda: plato/bebida con su personalización ya aplicada.
final class PedidoLinea extends EntidadBase {
  String pedidoId;

  /// Producto del catálogo (para descontar stock al cobrar). Vacío si es ad-hoc.
  String productoId;

  /// Descripción de venta (nombre + modificadores elegidos), congelada.
  String descripcion;

  /// Nota para la cocina (ej. "sin cebolla").
  String? nota;
  double cantidad;

  /// Precio unitario ya con los modificadores sumados.
  Dinero precioUnitario;
  Dinero importe;

  /// True si esta línea ya se envió/imprimió en comanda a la cocina.
  bool enviadoCocina;

  PedidoLinea({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.pedidoId = Uuid.vacio,
    this.productoId = Uuid.vacio,
    this.descripcion = '',
    this.nota,
    this.cantidad = 1,
    Dinero? precioUnitario,
    Dinero? importe,
    this.enviadoCocina = false,
  })  : precioUnitario = precioUnitario ?? Dinero.cero,
        importe = importe ?? Dinero.cero;

  /// Recalcula [importe] = cantidad × precioUnitario con el redondeo del
  /// dominio. Se llama antes de persistir para que la línea no dependa de que
  /// la UI haya hecho bien la multiplicación.
  void recalcularImporte() {
    importe = precioUnitario.porCantidad(cantidad);
  }

  factory PedidoLinea.desdeFila(Map<String, Object?> f) => PedidoLinea(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        pedidoId: Uuid.normalizar(Leer.texto(f, 'pedido_id')),
        productoId: Uuid.normalizar(Leer.texto(f, 'producto_id')),
        descripcion: Leer.texto(f, 'descripcion'),
        nota: Leer.textoNulable(f, 'nota'),
        cantidad: (Leer.numero(f, 'cantidad') ?? 1).toDouble(),
        precioUnitario: Dinero.desdeDb(Leer.numero(f, 'precio_unitario')),
        importe: Dinero.desdeDb(Leer.numero(f, 'importe')),
        enviadoCocina: Leer.booleano(f, 'enviado_cocina'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'pedido_id': pedidoId,
        'producto_id': Uuid.esVacio(productoId) ? null : productoId,
        'descripcion': descripcion,
        'nota': nota,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario.aDb(),
        'importe': importe.aDb(),
        'enviado_cocina': enviadoCocina ? 1 : 0,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'PedidoId': pedidoId,
        'ProductoId': productoId,
        'Descripcion': descripcion,
        'Nota': nota,
        'Cantidad': cantidad,
        'PrecioUnitario': precioUnitario.aDb(),
        'Importe': importe.aDb(),
        'EnviadoCocina': enviadoCocina,
      };

  factory PedidoLinea.desdeJson(Map<String, Object?> j) => PedidoLinea(
        id: Uuid.normalizar(j['Id'] as String?),
        pedidoId: Uuid.normalizar(j['PedidoId'] as String?),
        productoId: Uuid.normalizar(j['ProductoId'] as String?),
        descripcion: (j['Descripcion'] as String?) ?? '',
        nota: j['Nota'] as String?,
        cantidad: (j['Cantidad'] as num?)?.toDouble() ?? 1,
        precioUnitario: Dinero.desdeDb(j['PrecioUnitario'] as num?),
        importe: Dinero.desdeDb(j['Importe'] as num?),
        enviadoCocina: (j['EnviadoCocina'] as bool?) ?? false,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Comanda / cuenta abierta de una mesa.
final class Pedido extends EntidadBase {
  String mesaId;

  /// Número de mesa congelado (para mostrar e imprimir aunque cambie el maestro).
  String numeroMesa;

  /// Correlativo legible del pedido.
  String numero;
  EstadoPedido estado;
  String mozo;
  int comensales;
  DateTime fechaApertura;
  DateTime? fechaCierre;

  /// Total acumulado (caché desnormalizado; suma de líneas).
  Dinero total;
  String? notas;

  /// Venta generada al cobrar la mesa (null hasta cobrar).
  String? ventaId;

  /// Líneas de la cuenta (las carga el repositorio aparte).
  List<PedidoLinea> lineas;

  Pedido({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.mesaId = Uuid.vacio,
    this.numeroMesa = '',
    this.numero = '',
    this.estado = EstadoPedido.abierta,
    this.mozo = '',
    this.comensales = 1,
    DateTime? fechaApertura,
    this.fechaCierre,
    Dinero? total,
    this.notas,
    this.ventaId,
    List<PedidoLinea>? lineas,
  })  : fechaApertura = fechaApertura ?? DateTime.now(),
        total = total ?? Dinero.cero,
        lineas = lineas ?? <PedidoLinea>[];

  factory Pedido.desdeFila(Map<String, Object?> f) => Pedido(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        mesaId: Uuid.normalizar(Leer.texto(f, 'mesa_id')),
        numeroMesa: Leer.texto(f, 'numero_mesa'),
        numero: Leer.texto(f, 'numero'),
        estado: EstadoPedido.desde(Leer.entero(f, 'estado')),
        mozo: Leer.texto(f, 'mozo'),
        comensales: Leer.entero(f, 'comensales', 1),
        fechaApertura:
            TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_apertura')) ??
                DateTime.now(),
        fechaCierre: TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_cierre')),
        total: Dinero.desdeDb(Leer.numero(f, 'total')),
        notas: Leer.textoNulable(f, 'notas'),
        ventaId: Leer.textoNulable(f, 'venta_id'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'mesa_id': mesaId,
        'numero_mesa': numeroMesa,
        'numero': numero,
        'estado': estado.valor,
        'mozo': mozo,
        'comensales': comensales,
        'fecha_apertura': TiempoUtc.formatoOLocal(fechaApertura),
        'fecha_cierre':
            fechaCierre == null ? null : TiempoUtc.formatoOLocal(fechaCierre!),
        'total': total.aDb(),
        'notas': notas,
        'venta_id': ventaId,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'MesaId': mesaId,
        'NumeroMesa': numeroMesa,
        'Numero': numero,
        'Estado': estado.valor,
        'Mozo': mozo,
        'Comensales': comensales,
        'FechaApertura': TiempoUtc.formatoOLocal(fechaApertura),
        'FechaCierre':
            fechaCierre == null ? null : TiempoUtc.formatoOLocal(fechaCierre!),
        'Total': total.aDb(),
        'Notas': notas,
        'VentaId': ventaId,
        'Lineas': lineas.map((l) => l.aJson()).toList(),
      };

  factory Pedido.desdeJson(Map<String, Object?> j) => Pedido(
        id: Uuid.normalizar(j['Id'] as String?),
        mesaId: Uuid.normalizar(j['MesaId'] as String?),
        numeroMesa: (j['NumeroMesa'] as String?) ?? '',
        numero: (j['Numero'] as String?) ?? '',
        estado: EstadoPedido.desde((j['Estado'] as num?)?.toInt()),
        mozo: (j['Mozo'] as String?) ?? '',
        comensales: (j['Comensales'] as num?)?.toInt() ?? 1,
        fechaApertura:
            TiempoUtc.parsear(j['FechaApertura'] as String?) ?? DateTime.now(),
        fechaCierre: TiempoUtc.parsear(j['FechaCierre'] as String?),
        total: Dinero.desdeDb(j['Total'] as num?),
        notas: j['Notas'] as String?,
        ventaId: j['VentaId'] as String?,
        lineas: ((j['Lineas'] as List<Object?>?) ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .map(PedidoLinea.desdeJson)
            .toList(),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
