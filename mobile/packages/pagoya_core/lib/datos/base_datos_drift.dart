// PagoYa Móvil — datos/base_datos_drift.dart
//
// ÚNICO archivo de `pagoya_core` que conoce la API de drift.
//
// SIN CODE-GEN: no hay `part 'base_datos_drift.g.dart'` ni `build_runner`.
// El esquema se ejecuta literal desde `Esquema.sentencias` con
// `customStatement`, que es la decisión cerrada de
// docs/MOBILE-ARQUITECTURA.md §4 ("drift … con customStatement del
// esquema.sql — mantiene paridad literal de esquema con la PC"). Por eso
// `allTables` va vacío: drift aquí es solo el motor de conexión, el pool y las
// transacciones; no gestiona el esquema.
//
// ES TAMBIÉN EL PUNTO DE ENTRADA DE LA CAPA DE DATOS (§4.1):
// expone los repositorios como GETTERS, así `composicion.dart` no necesita
// conocer los nombres de las clases concretas y la capa entera se puede
// reimplementar sin tocar el composition root.

library;

import 'package:drift/drift.dart';

import '../configuracion/contratos.dart';
import 'almacen_configuracion.dart';
import 'contratos.dart';
import 'ejecutor_sql.dart';
import 'esquema.dart';
import 'notificador_tablas.dart';
import 'outbox_store.dart';
import 'repositorios/caja_repositorio.dart';
import 'repositorios/hotel_repositorio.dart';
import 'repositorios/mesa_repositorio.dart';
import 'repositorios/producto_repositorio.dart';
import 'repositorios/proveedor_repositorio.dart';
import 'repositorios/reportes_repositorio.dart';
import 'repositorios/usuario_repositorio.dart';
import 'repositorios/venta_repositorio.dart';

/// Base de datos local del POS móvil.
///
/// Se construye con un [QueryExecutor]: en la app, el de
/// `drift_flutter`/`sqlite3_flutter_libs`; en las pruebas,
/// `NativeDatabase.memory()`. `pagoya_core` no elige el ejecutor a propósito —
/// esa dependencia de plataforma vive en `pagoya_movil`.
class BaseDatosPagoYa extends GeneratedDatabase
    implements EjecutorSql, FuenteDeCambios {
  BaseDatosPagoYa(super.executor);

  /// Vacío: el esquema no lo gestiona drift, lo ejecuta [inicializarEsquema].
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const Iterable<TableInfo<Table, dynamic>>.empty();

  @override
  int get schemaVersion => Esquema.version;

  // =========================================================================
  // Repositorios (contrato §4.1: acceso por getters, no por constructores)
  // =========================================================================
  //
  // `late final` para que se construyan una sola vez y compartan la conexión y
  // el notificador. Que sean perezosos importa: una bodega nunca abre el módulo
  // de hotel, y no tiene por qué pagar por instanciarlo.

  /// Catálogo de productos y movimientos de kardex.
  late final RepositorioProductos productos = ProductoRepositorio(this);

  /// Ventas y su detalle (la ruta caliente del POS).
  late final RepositorioVentas ventas = VentaRepositorio(this);

  /// Sesiones de caja, movimientos de efectivo y arqueo.
  late final RepositorioCaja caja = CajaRepositorio(this);

  /// Salón: mesas, comandas y líneas.
  late final RepositorioMesas mesas = MesaRepositorio(this);

  /// Hospedaje: habitaciones, estadías y consumos.
  late final RepositorioHotel hotel = HotelRepositorio(this);

  /// Proveedores.
  late final RepositorioProveedores proveedores = ProveedorRepositorio(this);

  /// Usuarios locales del POS.
  late final RepositorioUsuarios usuarios = UsuarioRepositorio(this);

  /// Agregaciones de solo lectura para la pantalla de reportes.
  late final RepositorioReportes reportes = ReportesRepositorio(this);

  /// Outbox de sincronización. Se expone como [AlmacenOutbox] porque es el
  /// puerto que consume `lib/nube/`; `main.dart` lo usa para sobreescribir el
  /// `almacenOutboxProvider` que declara `flutter-sync`.
  late final AlmacenOutbox outbox = OutboxStore(this);

  /// Configuración del negocio, persistida en la tabla `meta`.
  late final AlmacenConfiguracion configuracion = AlmacenConfiguracionMeta(this);

  // =========================================================================
  // Esquema
  // =========================================================================

  /// Crea el esquema y aplica las migraciones aditivas. Idempotente: se puede
  /// llamar en cada arranque (todo es `IF NOT EXISTS` / "solo si falta").
  ///
  /// Espeja `PagoYaDbContext.InicializarEsquema()`.
  Future<void> inicializarEsquema() async {
    for (final p in Esquema.pragmas) {
      await customStatement(p);
    }
    for (final s in Esquema.sentencias) {
      await customStatement(s);
    }
    for (final (tabla, columna, definicion) in Esquema.migracionesAditivas) {
      await _asegurarColumna(tabla, columna, definicion);
    }
  }

  /// Agrega una columna solo si no existe. Espeja `AsegurarColumna`.
  ///
  /// `ALTER TABLE ADD COLUMN` es la única migración segura en SQLite y no es
  /// idempotente por sí sola, de ahí la consulta previa a `pragma_table_info`.
  Future<void> _asegurarColumna(
      String tabla, String columna, String definicion) async {
    final filas = await customSelect(
      'SELECT COUNT(*) AS n FROM pragma_table_info(?) WHERE name = ?',
      variables: [Variable<Object>(tabla), Variable<Object>(columna)],
    ).get();
    final n = filas.isEmpty ? 0 : (filas.first.data['n'] as num?)?.toInt() ?? 0;
    if (n > 0) return;
    await customStatement('ALTER TABLE $tabla ADD COLUMN $columna $definicion');
  }

  // =========================================================================
  // EjecutorSql
  // =========================================================================

  @override
  Future<void> ejecutar(String sql, [List<Object?> args = const []]) =>
      customStatement(sql, args);

  @override
  Future<int> ejecutarContando(String sql,
          [List<Object?> args = const []]) async =>
      customUpdate(sql, variables: _variables(args));

  @override
  Future<List<Map<String, Object?>>> consultar(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final filas = await customSelect(sql, variables: _variables(args)).get();
    return filas.map((f) => f.data).toList(growable: false);
  }

  @override
  Future<Object?> escalar(String sql, [List<Object?> args = const []]) async {
    final filas = await consultar(sql, args);
    if (filas.isEmpty) return null;
    final valores = filas.first.values;
    return valores.isEmpty ? null : valores.first;
  }

  @override
  Future<T> transaccion<T>(Future<T> Function(EjecutorSql tx) accion) =>
      transaction(() => accion(this));

  List<Variable<Object>> _variables(List<Object?> args) =>
      args.map((a) => Variable<Object>(a)).toList(growable: false);

  // =========================================================================
  // FuenteDeCambios
  // =========================================================================

  final NotificadorTablas _notificador = NotificadorTablas();

  @override
  void notificarCambio(Set<String> tablas) =>
      _notificador.notificarCambio(tablas);

  @override
  Stream<void> cambiosEn(Set<String> tablas) => _notificador.cambiosEn(tablas);

  @override
  Future<void> close() async {
    await _notificador.cerrar();
    await super.close();
  }
}
