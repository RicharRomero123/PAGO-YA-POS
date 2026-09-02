// PagoYa Móvil — datos/repositorios/hotel_repositorio.dart
//
// PORT de `HotelRepository.cs` / `IHotelRepository`: habitaciones, estadías y
// consumos cargados al cuarto.
//
// SINCRONIZACIÓN: `habitacion` y `estadia_habitacion` están en el catálogo
// cerrado de `backend-seats` y sí emiten evento. `consumos_habitacion` NO está
// en el catálogo: los consumos viajan consolidados en `monto_consumos` de la
// estadía, así que se recalculan localmente y se persisten en la estadía antes
// de emitir su evento.

library;

import '../../dominio/dinero.dart';
import '../../dominio/enums.dart';
import '../../dominio/hotel.dart';
import '../../dominio/uuid.dart';
import '../ejecutor_sql.dart';
import '../outbox.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

final class HotelRepositorio extends BaseRepositorio {
  static const String _selectHab = '''
      SELECT id, numero, piso, tipo, precio_noche, precio_hora, capacidad,
             estado, notas, imagen_ruta, comodidades, activa,
             origen_caja_id, created_utc, updated_utc
      FROM habitaciones
      ''';

  static const String _selectEst = '''
      SELECT id, habitacion_id, numero_habitacion, huesped_nombre,
             huesped_documento, huesped_telefono, personas, tipo_cobro,
             precio_unitario, check_in_utc, check_out_utc, unidades,
             monto_hospedaje, monto_consumos, total, metodo_pago, estado, notas,
             origen_caja_id, created_utc, updated_utc
      FROM estadias_habitacion
      ''';

  static const String _selectCon = '''
      SELECT id, estadia_id, producto_id, descripcion, cantidad,
             precio_unitario, fecha_hora_utc, origen_caja_id,
             created_utc, updated_utc
      FROM consumos_habitacion
      ''';

  HotelRepositorio(super.db, [super.config]);

  // --------------------------------------------------------- Habitaciones ---

  Future<List<Habitacion>> listarHabitaciones({bool soloActivas = true}) async {
    final filas = await db.consultar(
      soloActivas
          ? '$_selectHab WHERE activa = 1 ORDER BY piso, numero'
          : '$_selectHab ORDER BY piso, numero',
    );
    return filas.map(Habitacion.desdeFila).toList(growable: false);
  }

  Future<Habitacion?> obtenerHabitacion(String id) async {
    final filas =
        await db.consultar('$_selectHab WHERE id = ?', [Uuid.normalizar(id)]);
    return filas.isEmpty ? null : Habitacion.desdeFila(filas.first);
  }

  Future<void> guardarHabitacion(Habitacion h) async {
    await estampar(h);
    await db.transaccion((tx) async {
      final s = Sql.upsert('habitaciones', h.aFila(),
          columnasActualizables: const [
            'numero',
            'piso',
            'tipo',
            'precio_noche',
            'precio_hora',
            'capacidad',
            'estado',
            'notas',
            'imagen_ruta',
            'comodidades',
            'activa',
            'updated_utc',
          ]);
      await tx.ejecutar(s.sql, s.args);
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.habitacion,
        entidadId: h.id,
        operacion: OperacionesSync.upsert,
        payload: h.aJson(),
        origenCajaId: h.origenCajaId,
      );
    });
  }

  Future<void> desactivarHabitacion(String id) async {
    final h = await obtenerHabitacion(id);
    if (h == null) return;
    h.activa = false;
    await guardarHabitacion(h);
  }

  Future<void> cambiarEstadoHabitacion(String id, EstadoHabitacion estado) async {
    final h = await obtenerHabitacion(id);
    if (h == null) return;
    h.estado = estado;
    await guardarHabitacion(h);
  }

  // -------------------------------------------------------------- Estadías ---

  /// Estadía activa de una habitación (null si está libre).
  Future<EstadiaHabitacion?> obtenerEstadiaActiva(String habitacionId) async {
    final filas = await db.consultar(
      '$_selectEst WHERE habitacion_id = ? AND estado = ? '
      'ORDER BY check_in_utc DESC LIMIT 1',
      [Uuid.normalizar(habitacionId), EstadoEstadia.activa.valor],
    );
    return filas.isEmpty ? null : EstadiaHabitacion.desdeFila(filas.first);
  }

  Future<EstadiaHabitacion?> obtenerEstadia(String estadiaId) async {
    final filas = await db
        .consultar('$_selectEst WHERE id = ?', [Uuid.normalizar(estadiaId)]);
    return filas.isEmpty ? null : EstadiaHabitacion.desdeFila(filas.first);
  }

  /// Guarda la estadía recalculando sus importes desde los consumos.
  ///
  /// `montoConsumos` se recalcula aquí y no se confía en lo que traiga el
  /// objeto: los consumos no se sincronizan línea a línea, así que el total
  /// consolidado tiene que salir siempre de la tabla local.
  Future<EstadiaHabitacion> guardarEstadia(EstadiaHabitacion estadia) async {
    await estampar(estadia);

    await db.transaccion((tx) async {
      estadia.montoConsumos = await _totalConsumos(tx, estadia.id);
      estadia.montoHospedaje =
          estadia.precioUnitario.porCantidad(estadia.unidades);
      estadia.total = estadia.montoHospedaje + estadia.montoConsumos;

      final s = Sql.upsert('estadias_habitacion', estadia.aFila(),
          columnasActualizables: const [
            'numero_habitacion',
            'huesped_nombre',
            'huesped_documento',
            'huesped_telefono',
            'personas',
            'tipo_cobro',
            'precio_unitario',
            'check_out_utc',
            'unidades',
            'monto_hospedaje',
            'monto_consumos',
            'total',
            'metodo_pago',
            'estado',
            'notas',
            'updated_utc',
          ]);
      await tx.ejecutar(s.sql, s.args);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.estadiaHabitacion,
        entidadId: estadia.id,
        operacion: OperacionesSync.upsert,
        payload: estadia.aJson(),
        origenCajaId: estadia.origenCajaId,
      );
    });

    return estadia;
  }

  /// Check-out: cierra la estadía y deja la habitación en limpieza.
  ///
  /// La habitación NO pasa a `disponible` directamente: en un hotel real hay
  /// que limpiar el cuarto antes de volver a venderlo, y ese estado intermedio
  /// es lo que evita que recepción alquile una habitación sucia.
  Future<EstadiaHabitacion> cerrarEstadia(
    EstadiaHabitacion estadia, {
    required MetodoPago metodoPago,
    DateTime? checkOutUtc,
  }) async {
    estadia.checkOutUtc = (checkOutUtc ?? DateTime.now()).toUtc();
    estadia.metodoPago = metodoPago;
    estadia.estado = EstadoEstadia.cerrada;
    final guardada = await guardarEstadia(estadia);
    await cambiarEstadoHabitacion(estadia.habitacionId, EstadoHabitacion.limpieza);
    return guardada;
  }

  // -------------------------------------------------------------- Consumos ---

  Future<List<ConsumoHabitacion>> listarConsumos(String estadiaId) async {
    final filas = await db.consultar(
      '$_selectCon WHERE estadia_id = ? ORDER BY fecha_hora_utc',
      [Uuid.normalizar(estadiaId)],
    );
    return filas.map(ConsumoHabitacion.desdeFila).toList(growable: false);
  }

  /// Carga un consumo a la habitación y actualiza el total de la estadía.
  Future<ConsumoHabitacion> agregarConsumo(ConsumoHabitacion consumo) async {
    await estampar(consumo);
    final s = Sql.insertar('consumos_habitacion', consumo.aFila());
    await db.ejecutar(s.sql, s.args);

    final estadia = await obtenerEstadia(consumo.estadiaId);
    if (estadia != null) await guardarEstadia(estadia);
    return consumo;
  }

  Future<void> quitarConsumo(String consumoId) async {
    final idn = Uuid.normalizar(consumoId);
    final filas = await db.consultar('$_selectCon WHERE id = ?', [idn]);
    if (filas.isEmpty) return;
    final estadiaId = (filas.first['estadia_id'] ?? '').toString();

    await db.ejecutar('DELETE FROM consumos_habitacion WHERE id = ?', [idn]);

    final estadia = await obtenerEstadia(estadiaId);
    if (estadia != null) await guardarEstadia(estadia);
  }

  Future<Dinero> totalConsumos(String estadiaId) =>
      _totalConsumos(db, Uuid.normalizar(estadiaId));

  /// Suma los consumos con el redondeo del dominio.
  ///
  /// Se suma línea a línea con [Dinero] en vez de con `SUM()` de SQLite: la
  /// suma de REALes en SQL acumula error binario y el total del check-out
  /// podría diferir en un céntimo del que muestra la app.
  static Future<Dinero> _totalConsumos(EjecutorSql db, String estadiaId) async {
    final filas = await db.consultar(
      'SELECT cantidad, precio_unitario FROM consumos_habitacion '
      'WHERE estadia_id = ?',
      [estadiaId],
    );
    return Dinero.sumar(filas.map((f) {
      final precio = Dinero.desdeDb(f['precio_unitario'] as num?);
      final cantidad = (f['cantidad'] as num?)?.toDouble() ?? 1;
      return precio.porCantidad(cantidad);
    }));
  }

  /// Utilidad para el mapa de recepción: número de habitación -> huésped
  /// actual, para pintar el nombre en el tile de la habitación ocupada.
  Future<Map<String, String>> huespedesPorHabitacion() async {
    final filas = await db.consultar(
      'SELECT habitacion_id, huesped_nombre FROM estadias_habitacion '
      'WHERE estado = ?',
      [EstadoEstadia.activa.valor],
    );
    return {
      for (final f in filas)
        (f['habitacion_id'] ?? '').toString():
            (f['huesped_nombre'] ?? '').toString(),
    };
  }
}
