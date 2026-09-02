/// Puerto del **outbox local** visto desde la sincronización.
///
/// El outbox real (tabla `outbox_sync` + cursor en `meta`, sobre drift) lo
/// implementa `flutter-datos` en `pagoya_core/lib/datos/`. Este archivo declara
/// ÚNICAMENTE la interfaz que el motor de sync consume, para que
/// `lib/nube/` no dependa de la capa de datos ni de drift — igual que
/// `PagoYa.Cloud` depende de `IOutboxStore` y no de `PagoYa.Data`.
///
/// NOTA DE COORDINACIÓN (flutter-datos / mobile-lead):
/// si publican la interfaz canónica en `datos/contratos.dart`, este archivo
/// debe reducirse a un `export` de aquella. Mientras tanto la implementación de
/// `datos/` solo tiene que declarar `implements AlmacenOutbox` importando este
/// puerto; no hay dependencia en el otro sentido.
///
/// Es el espejo Dart de `src/PagoYa.Core/Contratos/IOutboxStore.cs` más dos
/// contadores que el escritorio no necesitaba y la pantalla de nube del móvil sí.
library;

import 'contratos_sync.dart';

abstract class AlmacenOutbox {
  // Los ids son UUID en `TEXT`. El backend puede devolverlos con otra caja
  // (mayúsculas/minúsculas) de la que se enviaron, así que toda comparación de
  // id en la implementación debe ser **insensible a mayúsculas** (`lower(id)`).

  /// Lee hasta [max] eventos pendientes (`estado = 0`), más antiguos primero.
  Future<List<EventoSyncLocal>> leerPendientes(int max);

  /// Marca eventos como enviados (`estado = 1`, `enviado_utc = now`).
  /// Idempotente: marcar dos veces el mismo id no es un error.
  Future<void> marcarEnviados(List<String> ids);

  /// Registra un intento fallido: incrementa `intentos`. Al superar
  /// [maxIntentos] mueve el evento a `estado = 2` (**dead-letter**) para que un
  /// evento venenoso no bloquee la cola; por debajo lo deja pendiente.
  ///
  /// Devuelve cuántos eventos acabaron en dead-letter en esta llamada (la
  /// pantalla de nube lo muestra; si crece, hay algo que soporte debe mirar).
  Future<int> registrarFallo(List<String> ids, int maxIntentos);

  /// Aplica cambios remotos a las tablas locales con **last-write-wins** por
  /// `updated_utc`. Devuelve cuántos se aplicaron.
  ///
  /// OJO (contrato con flutter-datos): `productos.stock_actual` es caché
  /// derivada. Al aplicar cambios se recalcula desde el kardex `inventario`, no
  /// se sobrescribe por LWW, o dos cajas vendiendo a la vez pierden ventas.
  Future<int> aplicarCambiosRemotos(List<CambioRemoto> cambios);

  /// Cursor de la última bajada (`null` si nunca sincronizó).
  Future<String?> leerCursor();

  /// Persiste el cursor tras aplicar los cambios remotos. Debe ser durable
  /// ANTES de considerar la página consumida: es lo que hace el ciclo reanudable.
  Future<void> guardarCursor(String cursor);

  /// Cuántos eventos esperan subir (`estado = 0`).
  Future<int> contarPendientes();

  /// Cuántos eventos quedaron apartados en dead-letter (`estado = 2`).
  Future<int> contarDeadLetter();

  /// Devuelve a la cola los eventos en dead-letter (botón de soporte:
  /// "reintentar los fallidos"). Devuelve cuántos volvieron a `estado = 0`.
  Future<int> reencolarDeadLetter();
}
