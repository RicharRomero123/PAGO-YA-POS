// PagoYa Móvil — dominio/entidad_base.dart
//
// PORT de `src/PagoYa.Core/Common/EntidadBase.cs`.
//
// Decisión heredada del escritorio (no se re-discute): la identidad es un UUID
// generado en el CLIENTE, guardado como TEXT. Motivo: varias cajas operan
// offline y luego consolidan en la nube; un autoincrement local generaría IDs
// duplicados al fusionar. `origen_caja_id` dice qué caja/dispositivo creó la
// fila, y es también lo que el filtro de eco del `/sync/pull` usa para no
// devolvernos nuestros propios eventos.

library;

import 'tiempo.dart';
import 'uuid.dart';

/// Base de todas las entidades de negocio sincronizables.
///
/// Se mantiene **mutable** (campos, no `final`) a propósito: es un port literal
/// de las clases C# y los repositorios asignan `actualizadoUtc` justo antes de
/// escribir, igual que hace el escritorio. La inmutabilidad vive en `Dinero`,
/// donde sí evita bugs de cálculo.
abstract class EntidadBase {
  /// Identificador único global (UUID v4 en minúsculas, con guiones).
  String id;

  /// Fecha/hora de creación en UTC. Base para orden y sincronización.
  DateTime creadoUtc;

  /// Última modificación en UTC. Es la marca del last-write-wins.
  DateTime actualizadoUtc;

  /// Caja/sede/dispositivo que originó el registro.
  String origenCajaId;

  EntidadBase({
    String? id,
    DateTime? creadoUtc,
    DateTime? actualizadoUtc,
    this.origenCajaId = '',
  })  : id = id ?? Uuid.v4(),
        creadoUtc = creadoUtc ?? DateTime.now().toUtc(),
        actualizadoUtc = actualizadoUtc ?? DateTime.now().toUtc();

  /// Marca la entidad como modificada ahora (llamado por los repositorios
  /// antes de escribir, igual que `entidad.ActualizadoUtc = DateTime.UtcNow`).
  void tocar([DateTime? ahora]) {
    actualizadoUtc = (ahora ?? DateTime.now()).toUtc();
  }

  /// Campos comunes en el JSON del outbox.
  ///
  /// **PascalCase a propósito.** `OutboxHelper` del escritorio serializa con
  /// las opciones por defecto de `System.Text.Json`, que NO aplican ninguna
  /// política de nombres; y `OutboxStore.AplicarCambiosRemotosAsync`
  /// deserializa también con las opciones por defecto, que son
  /// **case-sensitive**. Si el móvil emitiera `camelCase`, la PC recibiría un
  /// objeto con todos los campos en su valor por omisión: una venta de S/ 0.
  Map<String, Object?> baseAJson() => {
        'Id': id,
        'CreadoUtc': TiempoUtc.formatoO(creadoUtc),
        'ActualizadoUtc': TiempoUtc.formatoO(actualizadoUtc),
        'OrigenCajaId': origenCajaId,
      };

  /// Campos comunes en los parámetros SQL (snake_case del esquema copiado).
  Map<String, Object?> baseAFila() => {
        'id': id,
        'origen_caja_id': origenCajaId,
        'created_utc': TiempoUtc.formatoO(creadoUtc),
        'updated_utc': TiempoUtc.formatoO(actualizadoUtc),
      };
}

/// Lectores tolerantes para los mapas que devuelve SQLite y para los payloads
/// remotos. Toleran `null` y tipos vecinos (int/double, 0/1 como bool) porque
/// SQLite es de tipado dinámico y el payload puede venir de otra versión.
abstract final class Leer {
  static String texto(Map<String, Object?> f, String clave, [String pd = '']) {
    final v = f[clave];
    if (v == null) return pd;
    return v is String ? v : v.toString();
  }

  static String? textoNulable(Map<String, Object?> f, String clave) {
    final v = f[clave];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  static int entero(Map<String, Object?> f, String clave, [int pd = 0]) {
    final v = f[clave];
    if (v == null) return pd;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return int.tryParse(v.toString()) ?? pd;
  }

  static int? enteroNulable(Map<String, Object?> f, String clave) {
    final v = f[clave];
    if (v == null) return null;
    return entero(f, clave);
  }

  static num? numero(Map<String, Object?> f, String clave) {
    final v = f[clave];
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  /// SQLite guarda los booleanos como INTEGER 0/1 (ver esquema.sql).
  static bool booleano(Map<String, Object?> f, String clave,
      [bool pd = false]) {
    final v = f[clave];
    if (v == null) return pd;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true';
  }

  static DateTime fecha(Map<String, Object?> f, String clave) =>
      TiempoUtc.parsearUtc(textoNulable(f, clave));

  static DateTime? fechaNulable(Map<String, Object?> f, String clave) =>
      TiempoUtc.parsear(textoNulable(f, clave));
}
