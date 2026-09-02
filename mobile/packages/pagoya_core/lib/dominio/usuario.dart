// PagoYa Móvil — dominio/usuario.dart
//
// PORT de `Usuario.cs`.
//
// SEGURIDAD: la contraseña NUNCA viaja ni se guarda en claro; se guarda el
// hash PBKDF2 + salt (columnas `password_hash` / `password_salt`), que es lo
// que ya hace `PagoYa.Core.Common.Passwords` en el escritorio. Este archivo
// solo transporta esos dos textos: el cálculo del hash es responsabilidad de
// `flutter-licencia` (tiene la dependencia de cripto), no del núcleo de datos.
//
// Regla de negocio (tier Base): máximo 2 usuarios ACTIVOS — 1 administrador
// y 1 adicional. Más usuarios exigen licencia premium.

library;

import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

final class Usuario extends EntidadBase {
  /// Login, normalizado a minúsculas (índice único `ix_usuarios_nombre`).
  String nombreUsuario;
  String nombreCompleto;

  /// Hash PBKDF2 (SHA-256) en base64. Nunca la contraseña.
  String passwordHash;

  /// Salt aleatorio por usuario, en base64.
  String passwordSalt;

  RolUsuario rol;
  bool activo;
  DateTime? ultimoAccesoUtc;

  Usuario({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.nombreUsuario = '',
    this.nombreCompleto = '',
    this.passwordHash = '',
    this.passwordSalt = '',
    this.rol = RolUsuario.cajero,
    this.activo = true,
    this.ultimoAccesoUtc,
  });

  /// Normalización del login, igual que en el escritorio.
  static String normalizarNombre(String nombre) => nombre.trim().toLowerCase();

  factory Usuario.desdeFila(Map<String, Object?> f) => Usuario(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        nombreUsuario: Leer.texto(f, 'nombre_usuario'),
        nombreCompleto: Leer.texto(f, 'nombre_completo'),
        passwordHash: Leer.texto(f, 'password_hash'),
        passwordSalt: Leer.texto(f, 'password_salt'),
        rol: RolUsuario.desde(Leer.entero(f, 'rol', 1)),
        activo: Leer.booleano(f, 'activo', true),
        ultimoAccesoUtc: Leer.fechaNulable(f, 'ultimo_acceso_utc'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'nombre_usuario': nombreUsuario,
        'nombre_completo': nombreCompleto,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'rol': rol.valor,
        'activo': activo ? 1 : 0,
        'ultimo_acceso_utc':
            ultimoAccesoUtc == null ? null : TiempoUtc.formatoO(ultimoAccesoUtc!),
      };

  /// Snapshot para el outbox.
  ///
  /// OJO: `usuarios` NO está entre las entidades que
  /// `OutboxStore.AplicarCambiosRemotosAsync` sabe aplicar hoy (solo producto,
  /// venta, caja, movimiento_caja, inventario). El móvil no emite eventos de
  /// usuario por ahora; este mapeo existe para cuando `backend-seats` amplíe
  /// las entidades sincronizadas (docs/MOBILE-ARQUITECTURA.md §6.3).
  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'NombreUsuario': nombreUsuario,
        'NombreCompleto': nombreCompleto,
        'PasswordHash': passwordHash,
        'PasswordSalt': passwordSalt,
        'Rol': rol.valor,
        'Activo': activo,
        'UltimoAccesoUtc':
            ultimoAccesoUtc == null ? null : TiempoUtc.formatoO(ultimoAccesoUtc!),
      };
}
