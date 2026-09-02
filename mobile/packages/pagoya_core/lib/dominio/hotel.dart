// PagoYa Móvil — dominio/hotel.dart
//
// PORT de `Habitacion.cs`, `EstadiaHabitacion.cs` y `ConsumoHabitacion.cs`.
//
// Las habitaciones NO son productos: se administran aparte y se "venden" como
// una línea del carrito al cobrar (ver `PlantillasRubro.Productos("hotel")`,
// que solo siembra minibar/servicios).

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Habitación del hotel/hostal. Soporta tarifa por noche y por hora
/// (el clásico "hostal del paso" peruano).
final class Habitacion extends EntidadBase {
  String numero;
  int piso;
  TipoHabitacion tipo;
  Dinero precioNoche;

  /// Tarifa por hora. 0 = no ofrece esa modalidad.
  Dinero precioHora;
  int capacidad;
  EstadoHabitacion estado;
  String? notas;
  String? imagenRuta;

  /// Comodidades unidas por '|' (formato exacto del escritorio).
  String? comodidades;
  bool activa;

  Habitacion({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.numero = '',
    this.piso = 0,
    this.tipo = TipoHabitacion.simple,
    Dinero? precioNoche,
    Dinero? precioHora,
    this.capacidad = 1,
    this.estado = EstadoHabitacion.disponible,
    this.notas,
    this.imagenRuta,
    this.comodidades,
    this.activa = true,
  })  : precioNoche = precioNoche ?? Dinero.cero,
        precioHora = precioHora ?? Dinero.cero;

  /// Lista de comodidades. Espeja `Habitacion.ComodidadesLista`
  /// (`Split('|', RemoveEmptyEntries | TrimEntries)`).
  List<String> get comodidadesLista {
    final c = comodidades;
    if (c == null || c.trim().isEmpty) return const <String>[];
    return c
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  /// True si ofrece tarifa por hora.
  bool get ofreceHora => precioHora.esPositivo;

  factory Habitacion.desdeFila(Map<String, Object?> f) => Habitacion(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        numero: Leer.texto(f, 'numero'),
        piso: Leer.entero(f, 'piso'),
        tipo: TipoHabitacion.desde(Leer.entero(f, 'tipo')),
        precioNoche: Dinero.desdeDb(Leer.numero(f, 'precio_noche')),
        precioHora: Dinero.desdeDb(Leer.numero(f, 'precio_hora')),
        capacidad: Leer.entero(f, 'capacidad', 1),
        estado: EstadoHabitacion.desde(Leer.entero(f, 'estado')),
        notas: Leer.textoNulable(f, 'notas'),
        imagenRuta: Leer.textoNulable(f, 'imagen_ruta'),
        comodidades: Leer.textoNulable(f, 'comodidades'),
        activa: Leer.booleano(f, 'activa', true),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'numero': numero,
        'piso': piso,
        'tipo': tipo.valor,
        'precio_noche': precioNoche.aDb(),
        'precio_hora': precioHora.aDb(),
        'capacidad': capacidad,
        'estado': estado.valor,
        'notas': notas,
        'imagen_ruta': imagenRuta,
        'comodidades': comodidades,
        'activa': activa ? 1 : 0,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Numero': numero,
        'Piso': piso,
        'Tipo': tipo.valor,
        'PrecioNoche': precioNoche.aDb(),
        'PrecioHora': precioHora.aDb(),
        'Capacidad': capacidad,
        'Estado': estado.valor,
        'Notas': notas,
        'ImagenRuta': imagenRuta,
        'Comodidades': comodidades,
        'Activa': activa,
      };

  factory Habitacion.desdeJson(Map<String, Object?> j) => Habitacion(
        id: Uuid.normalizar(j['Id'] as String?),
        numero: (j['Numero'] as String?) ?? '',
        piso: (j['Piso'] as num?)?.toInt() ?? 0,
        tipo: TipoHabitacion.desde((j['Tipo'] as num?)?.toInt()),
        precioNoche: Dinero.desdeDb(j['PrecioNoche'] as num?),
        precioHora: Dinero.desdeDb(j['PrecioHora'] as num?),
        capacidad: (j['Capacidad'] as num?)?.toInt() ?? 1,
        estado: EstadoHabitacion.desde((j['Estado'] as num?)?.toInt()),
        notas: j['Notas'] as String?,
        imagenRuta: j['ImagenRuta'] as String?,
        comodidades: j['Comodidades'] as String?,
        activa: (j['Activa'] as bool?) ?? true,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Estadía (hospedaje) de una habitación: del check-in al check-out.
final class EstadiaHabitacion extends EntidadBase {
  String habitacionId;

  /// Número de habitación congelado (historial estable).
  String numeroHabitacion;
  String huespedNombre;

  /// DNI/CE/Pasaporte. Requerido por recepción.
  String huespedDocumento;
  String? huespedTelefono;
  int personas;
  TipoCobroHospedaje tipoCobro;

  /// Tarifa unitaria pactada al momento del check-in.
  Dinero precioUnitario;
  DateTime checkInUtc;
  DateTime? checkOutUtc;

  /// Unidades cobradas (noches u horas).
  double unidades;
  Dinero montoHospedaje;
  Dinero montoConsumos;
  Dinero total;

  /// OJO: en C# es un `int` crudo, no el enum `MetodoPago` (ver
  /// `EstadiaHabitacion.MetodoPago`). Aquí se tipa como enum pero se serializa
  /// como número, así que el valor en la columna es idéntico.
  MetodoPago metodoPago;

  EstadoEstadia estado;
  String? notas;

  EstadiaHabitacion({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.habitacionId = Uuid.vacio,
    this.numeroHabitacion = '',
    this.huespedNombre = '',
    this.huespedDocumento = '',
    this.huespedTelefono,
    this.personas = 1,
    this.tipoCobro = TipoCobroHospedaje.noche,
    Dinero? precioUnitario,
    DateTime? checkInUtc,
    this.checkOutUtc,
    this.unidades = 1,
    Dinero? montoHospedaje,
    Dinero? montoConsumos,
    Dinero? total,
    this.metodoPago = MetodoPago.efectivo,
    this.estado = EstadoEstadia.activa,
    this.notas,
  })  : precioUnitario = precioUnitario ?? Dinero.cero,
        checkInUtc = checkInUtc ?? DateTime.now().toUtc(),
        montoHospedaje = montoHospedaje ?? Dinero.cero,
        montoConsumos = montoConsumos ?? Dinero.cero,
        total = total ?? Dinero.cero;

  factory EstadiaHabitacion.desdeFila(Map<String, Object?> f) =>
      EstadiaHabitacion(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        habitacionId: Uuid.normalizar(Leer.texto(f, 'habitacion_id')),
        numeroHabitacion: Leer.texto(f, 'numero_habitacion'),
        huespedNombre: Leer.texto(f, 'huesped_nombre'),
        huespedDocumento: Leer.texto(f, 'huesped_documento'),
        huespedTelefono: Leer.textoNulable(f, 'huesped_telefono'),
        personas: Leer.entero(f, 'personas', 1),
        tipoCobro: TipoCobroHospedaje.desde(Leer.entero(f, 'tipo_cobro')),
        precioUnitario: Dinero.desdeDb(Leer.numero(f, 'precio_unitario')),
        checkInUtc: Leer.fecha(f, 'check_in_utc'),
        checkOutUtc: Leer.fechaNulable(f, 'check_out_utc'),
        unidades: (Leer.numero(f, 'unidades') ?? 1).toDouble(),
        montoHospedaje: Dinero.desdeDb(Leer.numero(f, 'monto_hospedaje')),
        montoConsumos: Dinero.desdeDb(Leer.numero(f, 'monto_consumos')),
        total: Dinero.desdeDb(Leer.numero(f, 'total')),
        metodoPago: MetodoPago.desde(Leer.entero(f, 'metodo_pago')),
        estado: EstadoEstadia.desde(Leer.entero(f, 'estado')),
        notas: Leer.textoNulable(f, 'notas'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'habitacion_id': habitacionId,
        'numero_habitacion': numeroHabitacion,
        'huesped_nombre': huespedNombre,
        'huesped_documento': huespedDocumento,
        'huesped_telefono': huespedTelefono,
        'personas': personas,
        'tipo_cobro': tipoCobro.valor,
        'precio_unitario': precioUnitario.aDb(),
        'check_in_utc': TiempoUtc.formatoO(checkInUtc),
        'check_out_utc':
            checkOutUtc == null ? null : TiempoUtc.formatoO(checkOutUtc!),
        'unidades': unidades,
        'monto_hospedaje': montoHospedaje.aDb(),
        'monto_consumos': montoConsumos.aDb(),
        'total': total.aDb(),
        'metodo_pago': metodoPago.valor,
        'estado': estado.valor,
        'notas': notas,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'HabitacionId': habitacionId,
        'NumeroHabitacion': numeroHabitacion,
        'HuespedNombre': huespedNombre,
        'HuespedDocumento': huespedDocumento,
        'HuespedTelefono': huespedTelefono,
        'Personas': personas,
        'TipoCobro': tipoCobro.valor,
        'PrecioUnitario': precioUnitario.aDb(),
        'CheckInUtc': TiempoUtc.formatoO(checkInUtc),
        'CheckOutUtc':
            checkOutUtc == null ? null : TiempoUtc.formatoO(checkOutUtc!),
        'Unidades': unidades,
        'MontoHospedaje': montoHospedaje.aDb(),
        'MontoConsumos': montoConsumos.aDb(),
        'Total': total.aDb(),
        'MetodoPago': metodoPago.valor,
        'Estado': estado.valor,
        'Notas': notas,
      };

  factory EstadiaHabitacion.desdeJson(Map<String, Object?> j) =>
      EstadiaHabitacion(
        id: Uuid.normalizar(j['Id'] as String?),
        habitacionId: Uuid.normalizar(j['HabitacionId'] as String?),
        numeroHabitacion: (j['NumeroHabitacion'] as String?) ?? '',
        huespedNombre: (j['HuespedNombre'] as String?) ?? '',
        huespedDocumento: (j['HuespedDocumento'] as String?) ?? '',
        huespedTelefono: j['HuespedTelefono'] as String?,
        personas: (j['Personas'] as num?)?.toInt() ?? 1,
        tipoCobro: TipoCobroHospedaje.desde((j['TipoCobro'] as num?)?.toInt()),
        precioUnitario: Dinero.desdeDb(j['PrecioUnitario'] as num?),
        checkInUtc: TiempoUtc.parsearUtc(j['CheckInUtc'] as String?),
        checkOutUtc: TiempoUtc.parsear(j['CheckOutUtc'] as String?),
        unidades: (j['Unidades'] as num?)?.toDouble() ?? 1,
        montoHospedaje: Dinero.desdeDb(j['MontoHospedaje'] as num?),
        montoConsumos: Dinero.desdeDb(j['MontoConsumos'] as num?),
        total: Dinero.desdeDb(j['Total'] as num?),
        metodoPago: MetodoPago.desde((j['MetodoPago'] as num?)?.toInt()),
        estado: EstadoEstadia.desde((j['Estado'] as num?)?.toInt()),
        notas: j['Notas'] as String?,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Consumo cargado a la cuenta de una habitación (minibar, lavandería…).
final class ConsumoHabitacion extends EntidadBase {
  String estadiaId;

  /// Producto del inventario consumido (null si es un cargo manual).
  String? productoId;
  String descripcion;
  double cantidad;
  Dinero precioUnitario;
  DateTime fechaHoraUtc;

  ConsumoHabitacion({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.estadiaId = Uuid.vacio,
    this.productoId,
    this.descripcion = '',
    this.cantidad = 1,
    Dinero? precioUnitario,
    DateTime? fechaHoraUtc,
  })  : precioUnitario = precioUnitario ?? Dinero.cero,
        fechaHoraUtc = fechaHoraUtc ?? DateTime.now().toUtc();

  /// Importe de la línea. Espeja `decimal.Round(Cantidad * PrecioUnitario, 2)`
  /// (redondeo bancario, aquí resuelto con enteros).
  Dinero get importe => precioUnitario.porCantidad(cantidad);

  factory ConsumoHabitacion.desdeFila(Map<String, Object?> f) =>
      ConsumoHabitacion(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        estadiaId: Uuid.normalizar(Leer.texto(f, 'estadia_id')),
        productoId: Leer.textoNulable(f, 'producto_id'),
        descripcion: Leer.texto(f, 'descripcion'),
        cantidad: (Leer.numero(f, 'cantidad') ?? 1).toDouble(),
        precioUnitario: Dinero.desdeDb(Leer.numero(f, 'precio_unitario')),
        fechaHoraUtc: Leer.fecha(f, 'fecha_hora_utc'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'estadia_id': estadiaId,
        'producto_id': productoId,
        'descripcion': descripcion,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario.aDb(),
        'fecha_hora_utc': TiempoUtc.formatoO(fechaHoraUtc),
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'EstadiaId': estadiaId,
        'ProductoId': productoId,
        'Descripcion': descripcion,
        'Cantidad': cantidad,
        'PrecioUnitario': precioUnitario.aDb(),
        'FechaHoraUtc': TiempoUtc.formatoO(fechaHoraUtc),
      };

  factory ConsumoHabitacion.desdeJson(Map<String, Object?> j) =>
      ConsumoHabitacion(
        id: Uuid.normalizar(j['Id'] as String?),
        estadiaId: Uuid.normalizar(j['EstadiaId'] as String?),
        productoId: j['ProductoId'] as String?,
        descripcion: (j['Descripcion'] as String?) ?? '',
        cantidad: (j['Cantidad'] as num?)?.toDouble() ?? 1,
        precioUnitario: Dinero.desdeDb(j['PrecioUnitario'] as num?),
        fechaHoraUtc: TiempoUtc.parsearUtc(j['FechaHoraUtc'] as String?),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
