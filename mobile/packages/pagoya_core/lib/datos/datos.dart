// PagoYa Móvil — barrel de la capa de datos.
//
// `base_datos_drift.dart` NO se exporta aquí a propósito: es el único archivo
// que importa `package:drift/drift.dart`, y mantenerlo fuera del barrel deja
// claro que el resto de la capa depende de `EjecutorSql`, no de drift. La app
// lo importa explícitamente donde construye la conexión.

library;

export 'configuracion_dispositivo.dart';
export 'correlativos.dart';
export 'ejecutor_sql.dart';
export 'esquema.dart';
export 'outbox.dart';
export 'outbox_store.dart';
export 'repositorios/base_repositorio.dart';
export 'repositorios/caja_repositorio.dart';
export 'repositorios/hotel_repositorio.dart';
export 'repositorios/mesa_repositorio.dart';
export 'repositorios/producto_repositorio.dart';
export 'repositorios/proveedor_repositorio.dart';
export 'repositorios/usuario_repositorio.dart';
export 'repositorios/venta_repositorio.dart';
export 'sentencias.dart';
