// PagoYa Móvil — dominio/caja.dart
//
// PORT de `Caja.cs` y `MovimientoCaja.cs`.
//
// Invariante heredada del escritorio (`CajaRepository.AbrirCajaAsync`): solo
// puede existir UNA caja Abierta a la vez en el dispositivo. Se valida dentro
// de la transacción de apertura, no en la UI.

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Sesión de caja (turno de arqueo).
final class Caja extends EntidadBase {
  /// Nombre/etiqueta de la caja o terminal.
  String nombre;

  /// Cajero que abrió la sesión.
  String cajero;
  EstadoCaja estado;

  /// Fondo inicial en efectivo.
  Dinero montoApertura;

  /// Hora LOCAL de apertura (los reportes filtran por `substr(...,1,10)`).
  DateTime fechaApertura;
  DateTime? fechaCierre;

  /// Monto contado al cierre (arqueo real). Null hasta cerrar.
  Dinero? montoCierre;

  /// Diferencia entre lo esperado y lo contado. Null hasta cerrar.
  Dinero? diferencia;

  Caja({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.nombre = 'Caja 1',
    this.cajero = '',
    this.estado = EstadoCaja.abierta,
    Dinero? montoApertura,
    DateTime? fechaApertura,
    this.fechaCierre,
    this.montoCierre,
    this.diferencia,
  })  : montoApertura = montoApertura ?? Dinero.cero,
        fechaApertura = fechaApertura ?? DateTime.now();

  factory Caja.desdeFila(Map<String, Object?> f) => Caja(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        nombre: Leer.texto(f, 'nombre', 'Caja 1'),
        cajero: Leer.texto(f, 'cajero'),
        estado: EstadoCaja.desde(Leer.entero(f, 'estado')),
        montoApertura: Dinero.desdeDb(Leer.numero(f, 'monto_apertura')),
        fechaApertura:
            TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_apertura')) ??
                DateTime.now(),
        fechaCierre: TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_cierre')),
        montoCierre: Dinero.desdeDbNulable(Leer.numero(f, 'monto_cierre')),
        diferencia: Dinero.desdeDbNulable(Leer.numero(f, 'diferencia')),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'nombre': nombre,
        'cajero': cajero,
        'estado': estado.valor,
        'monto_apertura': montoApertura.aDb(),
        'fecha_apertura': TiempoUtc.formatoOLocal(fechaApertura),
        'fecha_cierre':
            fechaCierre == null ? null : TiempoUtc.formatoOLocal(fechaCierre!),
        'monto_cierre': montoCierre?.aDb(),
        'diferencia': diferencia?.aDb(),
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Nombre': nombre,
        'Cajero': cajero,
        'Estado': estado.valor,
        'MontoApertura': montoApertura.aDb(),
        'FechaApertura': TiempoUtc.formatoOLocal(fechaApertura),
        'FechaCierre':
            fechaCierre == null ? null : TiempoUtc.formatoOLocal(fechaCierre!),
        'MontoCierre': montoCierre?.aDb(),
        'Diferencia': diferencia?.aDb(),
      };

  factory Caja.desdeJson(Map<String, Object?> j) => Caja(
        id: Uuid.normalizar(j['Id'] as String?),
        nombre: (j['Nombre'] as String?) ?? 'Caja 1',
        cajero: (j['Cajero'] as String?) ?? '',
        estado: EstadoCaja.desde((j['Estado'] as num?)?.toInt()),
        montoApertura: Dinero.desdeDb(j['MontoApertura'] as num?),
        fechaApertura:
            TiempoUtc.parsear(j['FechaApertura'] as String?) ?? DateTime.now(),
        fechaCierre: TiempoUtc.parsear(j['FechaCierre'] as String?),
        montoCierre: Dinero.desdeDbNulable(j['MontoCierre'] as num?),
        diferencia: Dinero.desdeDbNulable(j['Diferencia'] as num?),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}

/// Movimiento de efectivo distinto a una venta. Alimenta el arqueo.
final class MovimientoCaja extends EntidadBase {
  String cajaId;
  TipoMovimientoCaja tipo;

  /// Siempre positivo; el signo lo da [tipo] (ver `TipoMovimientoCaja.signo`).
  Dinero monto;
  String concepto;
  DateTime fechaHora;

  MovimientoCaja({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.cajaId = Uuid.vacio,
    this.tipo = TipoMovimientoCaja.ingreso,
    Dinero? monto,
    this.concepto = '',
    DateTime? fechaHora,
  })  : monto = monto ?? Dinero.cero,
        fechaHora = fechaHora ?? DateTime.now();

  factory MovimientoCaja.desdeFila(Map<String, Object?> f) => MovimientoCaja(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        cajaId: Uuid.normalizar(Leer.texto(f, 'caja_id')),
        tipo: TipoMovimientoCaja.desde(Leer.entero(f, 'tipo')),
        monto: Dinero.desdeDb(Leer.numero(f, 'monto')),
        concepto: Leer.texto(f, 'concepto'),
        fechaHora:
            TiempoUtc.parsear(Leer.textoNulable(f, 'fecha_hora')) ?? DateTime.now(),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'caja_id': cajaId,
        'tipo': tipo.valor,
        'monto': monto.aDb(),
        'concepto': concepto,
        'fecha_hora': TiempoUtc.formatoOLocal(fechaHora),
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'CajaId': cajaId,
        'Tipo': tipo.valor,
        'Monto': monto.aDb(),
        'Concepto': concepto,
        'FechaHora': TiempoUtc.formatoOLocal(fechaHora),
      };

  factory MovimientoCaja.desdeJson(Map<String, Object?> j) => MovimientoCaja(
        id: Uuid.normalizar(j['Id'] as String?),
        cajaId: Uuid.normalizar(j['CajaId'] as String?),
        tipo: TipoMovimientoCaja.desde((j['Tipo'] as num?)?.toInt()),
        monto: Dinero.desdeDb(j['Monto'] as num?),
        concepto: (j['Concepto'] as String?) ?? '',
        fechaHora: TiempoUtc.parsear(j['FechaHora'] as String?) ?? DateTime.now(),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
