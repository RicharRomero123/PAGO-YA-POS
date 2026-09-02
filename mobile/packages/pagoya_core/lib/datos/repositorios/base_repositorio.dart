// PagoYa Móvil — datos/repositorios/base_repositorio.dart
//
// Comportamiento común a todos los repositorios: estampar la identidad de
// sincronización del dispositivo en cada fila que se escribe.
//
// POR QUÉ AQUÍ Y NO EN CADA REPOSITORIO: `origen_caja_id` tiene que ser el
// MISMO valor que `flutter-sync` manda como `?origen=` en el pull, porque de
// eso depende el filtro de eco del backend. Se lee de una sola fuente
// (`ConfiguracionDispositivo`) y se aplica en un solo sitio (este), para que
// no pueda haber dos grafías del mismo dispositivo dando vueltas por la BD.

library;

import '../../dominio/entidad_base.dart';
import '../configuracion_dispositivo.dart';
import '../ejecutor_sql.dart';
import '../notificador_tablas.dart';

/// Base con acceso al ejecutor, a la identidad del dispositivo y a las señales
/// de cambio que alimentan los `Stream` de observación.
abstract base class BaseRepositorio {
  final EjecutorSql db;
  final ConfiguracionDispositivo config;

  /// Señales de "esta tabla cambió".
  ///
  /// Sale del propio [db] cuando es la base real ([BaseDatosPagoYa] implementa
  /// [FuenteDeCambios]), para que todos los repositorios que comparten conexión
  /// compartan también las señales: si la venta descuenta stock, la pantalla de
  /// inventario tiene que enterarse aunque esa escritura no pasara por
  /// `ProductoRepositorio`. Con un doble de test que solo ejecute SQL cae a
  /// [SinCambios] y los `observar*` emiten el valor actual y se quedan quietos,
  /// en vez de reventar.
  final FuenteDeCambios cambios;

  BaseRepositorio(this.db, [ConfiguracionDispositivo? config])
      : config = config ?? ConfiguracionDispositivo(db),
        cambios = db is FuenteDeCambios ? db : const SinCambios();

  /// Anuncia que [tablas] cambiaron. Llamar **después** del commit.
  void notificar(Set<String> tablas) => cambios.notificarCambio(tablas);

  /// Construye un `Stream` que emite el valor actual y lo re-consulta en cada
  /// señal de [tablas].
  Stream<T> observar<T>(Set<String> tablas, Future<T> Function() consulta) =>
      observarConsulta(cambios, tablas, consulta);

  /// Estampa `origen_caja_id` (si viene vacío) y marca `actualizado_utc`.
  ///
  /// Se respeta un `origenCajaId` ya puesto: una fila que llegó de otra caja y
  /// se está reescribiendo localmente conserva su origen real.
  Future<T> estampar<T extends EntidadBase>(T entidad) async {
    if (entidad.origenCajaId.isEmpty) {
      entidad.origenCajaId = await config.origenCajaId();
    }
    entidad.tocar();
    return entidad;
  }

  /// `origen_caja_id` de este dispositivo, para los eventos de outbox que no
  /// llevan entidad completa (bajas lógicas, anulaciones).
  Future<String> origenPropio() => config.origenCajaId();
}
