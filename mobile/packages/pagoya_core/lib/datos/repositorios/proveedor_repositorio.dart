// PagoYa Móvil — datos/repositorios/proveedor_repositorio.dart
//
// PORT de `ProveedorRepository.cs` / `IProveedorRepository`.
//
// `proveedor` NO está en el catálogo cerrado de entidades sincronizadas, así
// que estas escrituras no generan evento de outbox: el maestro de proveedores
// se administra por dispositivo. Si algún día entra al catálogo, hay que
// añadir el `OutboxHelper.registrar` aquí y el caso en `OutboxStore`.

library;

import '../../dominio/proveedor.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/uuid.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

final class ProveedorRepositorio extends BaseRepositorio {
  static const String _select = '''
      SELECT id, nombre, ruc, contacto, telefono, direccion, notas, activo,
             origen_caja_id, created_utc, updated_utc
      FROM proveedores
      ''';

  static const List<String> _actualizables = [
    'nombre',
    'ruc',
    'contacto',
    'telefono',
    'direccion',
    'notas',
    'activo',
    'updated_utc',
  ];

  ProveedorRepositorio(super.db, [super.config]);

  Future<List<Proveedor>> listar({bool soloActivos = true}) async {
    final filas = await db.consultar(
      soloActivos
          ? '$_select WHERE activo = 1 ORDER BY nombre COLLATE NOCASE'
          : '$_select ORDER BY nombre COLLATE NOCASE',
    );
    return filas.map(Proveedor.desdeFila).toList(growable: false);
  }

  Future<Proveedor?> obtenerPorId(String id) async {
    final filas =
        await db.consultar('$_select WHERE id = ?', [Uuid.normalizar(id)]);
    return filas.isEmpty ? null : Proveedor.desdeFila(filas.first);
  }

  Future<void> guardar(Proveedor proveedor) async {
    await estampar(proveedor);
    final s = Sql.upsert('proveedores', proveedor.aFila(),
        columnasActualizables: _actualizables);
    await db.ejecutar(s.sql, s.args);
  }

  /// Baja lógica: los productos siguen apuntando al proveedor por
  /// `productos.proveedor_id`, así que borrarlo dejaría referencias colgando.
  Future<void> desactivar(String id) => db.ejecutar(
        'UPDATE proveedores SET activo = 0, updated_utc = ? WHERE id = ?',
        [TiempoUtc.formatoO(DateTime.now()), Uuid.normalizar(id)],
      );
}
