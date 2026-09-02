// PagoYa Móvil — datos/repositorios/caja_repositorio.dart
//
// PORT de `CajaRepository.cs`. Misma forma que `ICajaRepository`.
//
// Reglas heredadas:
//   * Solo puede existir UNA caja Abierta a la vez (se valida DENTRO de la
//     transacción de apertura, no en la UI: si se valida fuera, dos toques
//     rápidos del botón abren dos cajas).
//   * Abrir caja inserta la sesión + su movimiento `AperturaFondo`, atómico.
//   * Cerrar caja registra el arqueo (monto contado + diferencia).

library;

import '../../dominio/caja.dart';
import '../../dominio/calculo_venta.dart';
import '../../dominio/dinero.dart';
import '../../dominio/enums.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/uuid.dart';
import '../ejecutor_sql.dart';
import '../outbox.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

final class CajaRepositorio extends BaseRepositorio {
  static const String _selectCaja = '''
      SELECT id, nombre, cajero, estado, monto_apertura, fecha_apertura,
             fecha_cierre, monto_cierre, diferencia, origen_caja_id,
             created_utc, updated_utc
      FROM caja
      ''';

  static const String _selectMov = '''
      SELECT id, caja_id, tipo, monto, concepto, fecha_hora, origen_caja_id,
             created_utc, updated_utc
      FROM movimientos_caja
      ''';

  CajaRepositorio(super.db, [super.config]);

  Future<Caja?> obtenerCajaAbierta() async {
    final filas = await db.consultar(
      '$_selectCaja WHERE estado = ? ORDER BY fecha_apertura DESC LIMIT 1',
      [EstadoCaja.abierta.valor],
    );
    return filas.isEmpty ? null : Caja.desdeFila(filas.first);
  }

  Future<Caja?> obtenerPorId(String id) async {
    final filas =
        await db.consultar('$_selectCaja WHERE id = ?', [Uuid.normalizar(id)]);
    return filas.isEmpty ? null : Caja.desdeFila(filas.first);
  }

  /// Abre la caja. Lanza [ErrorDatos] si ya hay una abierta.
  Future<Caja> abrir(Caja caja) async {
    caja.estado = EstadoCaja.abierta;
    await estampar(caja);

    await db.transaccion((tx) async {
      final abiertas = await tx.escalar(
        'SELECT COUNT(*) FROM caja WHERE estado = ?',
        [EstadoCaja.abierta.valor],
      );
      if (((abiertas as num?)?.toInt() ?? 0) > 0) {
        throw const ErrorDatos(
            'Ya existe una caja abierta. Ciérrala antes de abrir otra.');
      }

      final s = Sql.insertar('caja', caja.aFila());
      await tx.ejecutar(s.sql, s.args);

      // Movimiento de fondo de apertura, en la misma transacción.
      final mov = MovimientoCaja(
        cajaId: caja.id,
        tipo: TipoMovimientoCaja.aperturaFondo,
        monto: caja.montoApertura,
        concepto: 'Fondo inicial',
        fechaHora: caja.fechaApertura,
        origenCajaId: caja.origenCajaId,
      );
      final sm = Sql.insertar('movimientos_caja', mov.aFila());
      await tx.ejecutar(sm.sql, sm.args);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.caja,
        entidadId: caja.id,
        operacion: OperacionesSync.insert,
        payload: caja.aJson(),
        origenCajaId: caja.origenCajaId,
      );
      // El movimiento de apertura también viaja: sin él, el arqueo en la nube
      // no cuadra con el de la caja física.
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.movimientoCaja,
        entidadId: mov.id,
        operacion: OperacionesSync.insert,
        payload: mov.aJson(),
        origenCajaId: mov.origenCajaId,
      );
    });

    return caja;
  }

  /// Cierra la caja con el monto contado. Calcula la diferencia contra lo
  /// esperado usando [ArqueoCaja] (regla: solo el efectivo entra al arqueo).
  Future<Caja> cerrar(Caja caja, {required Dinero montoContado}) async {
    final arqueo = await calcularArqueo(caja);

    caja.estado = EstadoCaja.cerrada;
    caja.fechaCierre ??= DateTime.now();
    caja.montoCierre = montoContado;
    caja.diferencia = arqueo.diferencia(montoContado);
    await estampar(caja);

    await db.transaccion((tx) async {
      final s = Sql.actualizar(
        'caja',
        {
          'estado': caja.estado.valor,
          'fecha_cierre': TiempoUtc.formatoOLocal(caja.fechaCierre!),
          'monto_cierre': caja.montoCierre?.aDb(),
          'diferencia': caja.diferencia?.aDb(),
          'updated_utc': TiempoUtc.formatoO(caja.actualizadoUtc),
        },
        condicion: 'id = ?',
        argsCondicion: [caja.id],
      );
      await tx.ejecutar(s.sql, s.args);

      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.caja,
        entidadId: caja.id,
        operacion: OperacionesSync.update,
        payload: caja.aJson(),
        origenCajaId: caja.origenCajaId,
      );
    });

    return caja;
  }

  /// Registra un movimiento de efectivo + su evento, atómico.
  Future<MovimientoCaja> registrarMovimiento(MovimientoCaja movimiento) async {
    await estampar(movimiento);

    await db.transaccion((tx) async {
      final s = Sql.insertar('movimientos_caja', movimiento.aFila());
      await tx.ejecutar(s.sql, s.args);
      await OutboxHelper.registrar(
        tx,
        entidad: EntidadesSync.movimientoCaja,
        entidadId: movimiento.id,
        operacion: OperacionesSync.insert,
        payload: movimiento.aJson(),
        origenCajaId: movimiento.origenCajaId,
      );
    });

    return movimiento;
  }

  Future<List<MovimientoCaja>> listarMovimientos(String cajaId) async {
    final filas = await db.consultar(
      '$_selectMov WHERE caja_id = ? ORDER BY fecha_hora',
      [Uuid.normalizar(cajaId)],
    );
    return filas.map(MovimientoCaja.desdeFila).toList(growable: false);
  }

  /// Sesiones abiertas entre dos fechas (hora local, `substr(...,1,10)`).
  Future<List<Caja>> listarSesiones(DateTime desde, DateTime hasta) async {
    var d = desde;
    var h = hasta;
    if (h.isBefore(d)) {
      final t = d;
      d = h;
      h = t;
    }
    final filas = await db.consultar(
      '$_selectCaja WHERE substr(fecha_apertura, 1, 10) BETWEEN ? AND ? '
      'ORDER BY fecha_apertura DESC',
      [TiempoUtc.formatoFecha(d), TiempoUtc.formatoFecha(h)],
    );
    return filas.map(Caja.desdeFila).toList(growable: false);
  }

  /// Arqueo de la sesión: fondo + ingresos − egresos.
  Future<ArqueoCaja> calcularArqueo(Caja caja) async {
    final movs = await listarMovimientos(caja.id);
    return ArqueoCaja.desdeMovimientos(
      montoApertura: caja.montoApertura,
      movimientos: movs.map((m) => (tipo: m.tipo, monto: m.monto)),
    );
  }
}
