// PagoYa Móvil — datos/notificador_tablas.dart
//
// Señal de "esta tabla cambió", para los `Stream` de observación que pide
// `datos/contratos.dart`.
//
// POR QUÉ NO SE USA `.watch()` DE DRIFT
// -------------------------------------
// Los streams reactivos de drift necesitan saber de qué `TableInfo` lee cada
// consulta, y eso solo lo sabe el código generado. Aquí el esquema se ejecuta
// con `customStatement` (decisión cerrada, §4: paridad literal con el
// `esquema.sql` del escritorio), así que no hay `TableInfo` que declarar. Sin
// esta pieza, `observarMesas()` no existiría y dos mozos podrían tomar la misma
// mesa — que es justo lo que el caso de uso estrella del móvil no puede
// permitirse.
//
// El mecanismo es deliberadamente tonto: tras cada escritura commiteada, el
// repositorio dice qué tablas tocó; los observadores vuelven a consultar. Para
// un salón de veinte mesas o un catálogo de bodega, re-consultar es más barato
// que mantener un diff, y no puede desincronizarse de la BD.

library;

import 'dart:async';

/// Fuente de señales de cambio por tabla.
///
/// La implementa `BaseDatosPagoYa`, para que todos los repositorios que
/// comparten una conexión compartan también las señales: si `VentaRepositorio`
/// descuenta stock, la pantalla de inventario tiene que enterarse aunque la
/// escritura no haya pasado por `ProductoRepositorio`.
abstract interface class FuenteDeCambios {
  /// Anuncia que [tablas] cambiaron. Se llama **después** del commit: avisar
  /// dentro de la transacción haría que un observador leyera datos que un
  /// rollback posterior va a borrar.
  void notificarCambio(Set<String> tablas);

  /// Emite un evento cada vez que cambia alguna de [tablas].
  Stream<void> cambiosEn(Set<String> tablas);
}

/// Implementación en memoria de [FuenteDeCambios].
///
/// Es un `broadcast` porque hay varios observadores a la vez (mapa del salón,
/// barra de caja, inventario) y ninguno debe recibir la señal de los otros.
final class NotificadorTablas implements FuenteDeCambios {
  final StreamController<Set<String>> _controlador =
      StreamController<Set<String>>.broadcast(sync: true);

  @override
  void notificarCambio(Set<String> tablas) {
    if (tablas.isEmpty || _controlador.isClosed) return;
    _controlador.add(tablas);
  }

  @override
  Stream<void> cambiosEn(Set<String> tablas) => _controlador.stream
      .where((cambiadas) => cambiadas.any(tablas.contains))
      .map((_) => null);

  /// Cierra el notificador. La llama `BaseDatosPagoYa.close()`.
  Future<void> cerrar() => _controlador.close();
}

/// Fuente que nunca emite. Se usa cuando el `EjecutorSql` inyectado no es la
/// base de datos real (por ejemplo un doble de test que solo ejecuta SQL):
/// los `observar*` devuelven el valor actual y se quedan quietos, en vez de
/// reventar.
final class SinCambios implements FuenteDeCambios {
  const SinCambios();

  @override
  void notificarCambio(Set<String> tablas) {}

  @override
  Stream<void> cambiosEn(Set<String> tablas) => const Stream<void>.empty();
}

/// Nombres de tabla usados en las señales. Son los del `esquema.sql`
/// compartido: si aquí se escribe `mesa` en vez de `mesas`, el observador
/// simplemente no se entera y la pantalla se queda congelada sin error.
abstract final class Tablas {
  static const String productos = 'productos';
  static const String proveedores = 'proveedores';
  static const String caja = 'caja';
  static const String movimientosCaja = 'movimientos_caja';
  static const String ventas = 'ventas';
  static const String detalleVentas = 'detalle_ventas';
  static const String inventario = 'inventario';
  static const String comprobantes = 'comprobantes';
  static const String habitaciones = 'habitaciones';
  static const String estadiasHabitacion = 'estadias_habitacion';
  static const String consumosHabitacion = 'consumos_habitacion';
  static const String mesas = 'mesas';
  static const String pedidos = 'pedidos';
  static const String pedidoLineas = 'pedido_lineas';
  static const String outboxSync = 'outbox_sync';
  static const String usuarios = 'usuarios';
  static const String meta = 'meta';
}

/// Utilidad para construir un `Stream` de consulta re-ejecutada.
///
/// Emite el valor actual de inmediato (para que la UI pinte sin esperar a la
/// primera escritura) y después uno por cada señal de [fuente].
Stream<T> observarConsulta<T>(
  FuenteDeCambios fuente,
  Set<String> tablas,
  Future<T> Function() consulta,
) async* {
  yield await consulta();
  await for (final _ in fuente.cambiosEn(tablas)) {
    yield await consulta();
  }
}
