// PagoYa Móvil — datos/repositorios/usuario_repositorio.dart
//
// PORT de `UsuarioRepository.cs` / `IUsuarioRepository`.
//
// `usuario` NO está en el catálogo cerrado de entidades sincronizadas: las
// credenciales no viajan por el outbox. El login es local al dispositivo.
//
// Este repositorio NO calcula hashes de contraseña: recibe `passwordHash` y
// `passwordSalt` ya calculados por `flutter-licencia` (que es quien tiene la
// dependencia de cripto). Mantener el hashing fuera de la capa de datos evita
// que una contraseña en claro llegue nunca a un `String` de este archivo.

library;

import '../../dominio/enums.dart';
import '../../dominio/tiempo.dart';
import '../../dominio/usuario.dart';
import '../../dominio/uuid.dart';
import '../sentencias.dart';
import 'base_repositorio.dart';

final class UsuarioRepositorio extends BaseRepositorio {
  static const String _select = '''
      SELECT id, nombre_usuario, nombre_completo, password_hash, password_salt,
             rol, activo, ultimo_acceso_utc, origen_caja_id,
             created_utc, updated_utc
      FROM usuarios
      ''';

  static const List<String> _actualizables = [
    'nombre_usuario',
    'nombre_completo',
    'password_hash',
    'password_salt',
    'rol',
    'activo',
    'ultimo_acceso_utc',
    'updated_utc',
  ];

  UsuarioRepositorio(super.db, [super.config]);

  /// True si ya hay algún usuario creado (decide si mostrar el asistente de
  /// primer arranque o la pantalla de login).
  Future<bool> existeAlguno() async {
    final v = await db.escalar('SELECT COUNT(*) FROM usuarios');
    return ((v as num?)?.toInt() ?? 0) > 0;
  }

  /// Usuarios activos. La regla del tier Base (máximo 2) se aplica en la capa
  /// de licencia, no aquí: este repositorio solo informa.
  Future<int> contarActivos() async {
    final v = await db.escalar('SELECT COUNT(*) FROM usuarios WHERE activo = 1');
    return (v as num?)?.toInt() ?? 0;
  }

  Future<Usuario?> obtenerPorNombre(String nombreUsuario) async {
    final filas = await db.consultar(
      '$_select WHERE nombre_usuario = ?',
      [Usuario.normalizarNombre(nombreUsuario)],
    );
    return filas.isEmpty ? null : Usuario.desdeFila(filas.first);
  }

  Future<List<Usuario>> listar() async {
    final filas =
        await db.consultar('$_select ORDER BY rol, nombre_usuario');
    return filas.map(Usuario.desdeFila).toList(growable: false);
  }

  Future<void> guardar(Usuario usuario) async {
    usuario.nombreUsuario = Usuario.normalizarNombre(usuario.nombreUsuario);
    await estampar(usuario);
    final s = Sql.upsert('usuarios', usuario.aFila(),
        columnasActualizables: _actualizables);
    await db.ejecutar(s.sql, s.args);
  }

  /// Baja lógica. Un usuario desactivado no puede entrar ni cuenta al límite
  /// del tier, pero su nombre sigue apareciendo en los arqueos históricos.
  Future<void> desactivar(String id) => db.ejecutar(
        'UPDATE usuarios SET activo = 0, updated_utc = ? WHERE id = ?',
        [TiempoUtc.formatoO(DateTime.now()), Uuid.normalizar(id)],
      );

  Future<void> registrarAcceso(String id, DateTime cuandoUtc) => db.ejecutar(
        'UPDATE usuarios SET ultimo_acceso_utc = ?, updated_utc = ? WHERE id = ?',
        [
          TiempoUtc.formatoO(cuandoUtc),
          TiempoUtc.formatoO(DateTime.now()),
          Uuid.normalizar(id),
        ],
      );

  /// True si queda al menos un administrador activo distinto de [exceptoId].
  ///
  /// Evita el pie en el que el dueño se desactiva a sí mismo y se queda sin
  /// acceso a la configuración de su propio POS.
  Future<bool> quedaOtroAdministrador(String exceptoId) async {
    final v = await db.escalar(
      'SELECT COUNT(*) FROM usuarios WHERE activo = 1 AND rol = ? AND id <> ?',
      [RolUsuario.administrador.valor, Uuid.normalizar(exceptoId)],
    );
    return ((v as num?)?.toInt() ?? 0) > 0;
  }
}
