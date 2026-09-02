// PagoYa Móvil — datos/outbox.dart
//
// PORT de `src/PagoYa.Data/Repositorios/OutboxHelper.cs`.
//
// ES LO MÁS IMPORTANTE DE ESTA CAPA.
//
// Cada escritura de negocio registra aquí una fila con el snapshot serializado
// de la entidad, EN LA MISMA TRANSACCIÓN que la escritura. No es un detalle de
// implementación, es la garantía del negocio:
//
//   * si la venta se guarda y el evento no  -> la nube pierde la venta y el
//     reporte del dueño no cuadra con su cajón;
//   * si el evento se guarda y la venta no  -> la nube inventa una venta que
//     nunca ocurrió y el stock se descuadra.
//
// Por eso `registrar` recibe el `EjecutorSql` de la transacción en curso y
// NUNCA abre uno propio. Si algún repositorio llama a esto fuera de una
// transacción, el bug es del repositorio.
//
// En el tier Base la tabla existe pero `ServicioSync` es un no-op: las filas
// quedan 'pendientes' y se enviarán en cuanto el usuario active Cloud. No se
// pierde historial por no haber pagado todavía.
//
// ---------------------------------------------------------------------------
// QUÉ VIVE AQUÍ Y QUÉ NO (arbitraje §4.3)
// ---------------------------------------------------------------------------
// `EventoSyncLocal`, `CambioRemoto` y `EntidadesSync` YA NO se declaran en este
// archivo: son el **contrato del cable** y sus campos tienen que casar con
// `server/PagoYa.Api/Contratos/Dtos.cs`, así que el canónico es
// `nube/contratos_sync.dart` (flutter-sync), que además sabe serializar.
//
// Lo que aportaba este archivo —leer una fila de SQLite y decodificar el
// payload— se conserva como **extensiones** sobre los tipos canónicos, así que
// no se pierde nada: `EventoSyncLocalFila.desdeFila(...)`, `evento.payload`,
// `cambio.payload` y `CatalogoLocal.todas`.
//
// `OutboxHelper`, `OperacionesSync` y `EstadoOutbox` sí se quedan: son de la
// TABLA (el INSERT dentro de la transacción, la columna `estado`), no del
// cable, y nadie más los declara.

library;

import 'dart:convert';

import '../dominio/tiempo.dart';
import '../dominio/uuid.dart';
import '../nube/contratos_sync.dart';
import 'ejecutor_sql.dart';
import 'sentencias.dart';

export '../nube/contratos_sync.dart' show CambioRemoto, EntidadesSync, EventoSyncLocal;

/// Operaciones válidas en `outbox_sync.operacion`.
///
/// OJO con `upsert`: el escritorio lo usa para `producto`
/// (`ProductoRepository.GuardarAsync` registra `"UPSERT"`), y al aplicar trata
/// cualquier operación distinta de `DELETE` como upsert. Se replica igual.
abstract final class OperacionesSync {
  static const String insert = 'INSERT';
  static const String update = 'UPDATE';
  static const String upsert = 'UPSERT';
  static const String delete = 'DELETE';
}

/// Estados de `outbox_sync.estado`.
abstract final class EstadoOutbox {
  static const int pendiente = 0;
  static const int enviado = 1;

  /// Dead-letter: superó el máximo de intentos.
  static const int error = 2;
}

/// Registro de eventos en el outbox.
abstract final class OutboxHelper {
  /// Inserta un evento de outbox **dentro de la transacción [tx]**.
  ///
  /// Debe llamarse antes del commit de la escritura de negocio asociada.
  /// [payload] es el mapa `aJson()` de la entidad (PascalCase, ver
  /// `EntidadBase.baseAJson`).
  static Future<void> registrar(
    EjecutorSql tx, {
    required String entidad,
    required String entidadId,
    required String operacion,
    required Map<String, Object?> payload,
    required String origenCajaId,
    DateTime? ahora,
  }) async {
    final s = Sql.insertar('outbox_sync', {
      'id': Uuid.v4(),
      'entidad': entidad,
      'entidad_id': entidadId,
      'operacion': operacion,
      // `jsonEncode` sin indentar, igual que `WriteIndented = false` en C#.
      'payload_json': jsonEncode(payload),
      'estado': EstadoOutbox.pendiente,
      'intentos': 0,
      'origen_caja_id': origenCajaId,
      'created_utc': TiempoUtc.formatoO(ahora ?? DateTime.now()),
      'enviado_utc': null,
    });
    await tx.ejecutar(s.sql, s.args);
  }
}

/// Lectura de `EventoSyncLocal` desde una fila de `outbox_sync`.
///
/// El tipo es de `nube/contratos_sync.dart`; esto es solo el mapeo desde
/// SQLite, que es detalle de la capa de datos.
extension EventoSyncLocalFila on EventoSyncLocal {
  /// Construye el evento desde una fila cruda de `outbox_sync`.
  static EventoSyncLocal desdeFila(Map<String, Object?> f) => EventoSyncLocal(
        id: (f['id'] ?? '').toString(),
        entidad: (f['entidad'] ?? '').toString(),
        entidadId: (f['entidad_id'] ?? '').toString(),
        operacion: (f['operacion'] ?? '').toString(),
        payloadJson: (f['payload_json'] ?? '{}').toString(),
        intentos: (f['intentos'] as num?)?.toInt() ?? 0,
        origenCajaId: (f['origen_caja_id'] ?? '').toString(),
        creadoUtc: TiempoUtc.parsearUtc(f['created_utc']?.toString()),
      );

  /// Payload decodificado. Devuelve un mapa vacío si el JSON está corrupto: un
  /// evento roto no debe bloquear la subida de los demás.
  Map<String, Object?> get payload => _decodificar(payloadJson);
}

/// Decodificación tolerante del payload de un cambio remoto.
extension CambioRemotoPayload on CambioRemoto {
  /// Payload decodificado, o mapa vacío si viene corrupto.
  Map<String, Object?> get payload => _decodificar(payloadJson);
}

/// Vista local del catálogo de entidades sincronizables.
///
/// `EntidadesSync.catalogo` (canónico, un `Set`) es la fuente de verdad. Aquí
/// se añaden dos cosas que la capa de datos sí necesita y el cable no:
/// el ORDEN del contrato y qué subconjunto aplica hoy el escritorio.
extension CatalogoLocal on EntidadesSync {
  /// Las diez entidades, en el orden del contrato (el `Set` canónico no lo
  /// garantiza y los fixtures de paridad comparan por orden).
  static const List<String> todas = <String>[
    EntidadesSync.producto,
    EntidadesSync.venta,
    EntidadesSync.caja,
    EntidadesSync.movimientoCaja,
    EntidadesSync.inventario,
    EntidadesSync.mesa,
    EntidadesSync.pedido,
    EntidadesSync.pedidoLinea,
    EntidadesSync.habitacion,
    EntidadesSync.estadiaHabitacion,
  ];

  /// Subconjunto que `OutboxStore.AplicarCambiosRemotosAsync` del ESCRITORIO
  /// sabe aplicar hoy. El backend y el móvil ya manejan las diez; la PC se
  /// ampliará (§6.3). Mientras tanto, un evento de `mesa` que el móvil emite
  /// llega al servidor y vuelve a otro móvil, pero la PC lo ignora: es una
  /// degradación aceptable, no una pérdida de datos.
  static const Set<String> aplicadasPorEscritorio = <String>{
    EntidadesSync.producto,
    EntidadesSync.venta,
    EntidadesSync.caja,
    EntidadesSync.movimientoCaja,
    EntidadesSync.inventario,
  };

  /// `consumos_habitacion` NO está en el catálogo: los consumos viajan
  /// consolidados en `monto_consumos` de la estadía. Ampliarlo exige tocar los
  /// tres lados a la vez.
  static const String noSincronizada = 'consumos_habitacion';
}

Map<String, Object?> _decodificar(String json) {
  try {
    final d = jsonDecode(json);
    return d is Map<String, Object?> ? d : <String, Object?>{};
  } on FormatException {
    return <String, Object?>{};
  }
}
