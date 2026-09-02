/// Contratos de **persistencia local** (SQLite vía drift).
///
/// Espejo 1:1 de `src/PagoYa.Core/Contratos/I*Repository.cs` y `IOutboxStore.cs`.
/// Dueño de ESTE archivo: `mobile-lead`. Los implementa `flutter-datos` en
/// `lib/datos/` con drift sobre el MISMO `esquema.sql` del escritorio.
///
/// ## Convenciones de portado C# → Dart (aplican a todo el archivo)
///
/// | C# | Dart | Por qué |
/// |---|---|---|
/// | `Guid` | `String` | Las PK ya son UUID en TEXT (ARQUITECTURA §4). Un `Guid` de Dart sería una capa de conversión sin valor. |
/// | `decimal` monetario | [Dinero] | Regla invariante: nadie hace aritmética de precios con `double` suelto. |
/// | `decimal` de cantidad | `double` | Unidades y kilos no son dinero; no necesitan céntimos exactos. |
/// | `DateOnly` | `DateTime` a medianoche **local** | Dart no tiene `DateOnly`. Es fecha de negocio (el día del POS), no un instante UTC. |
/// | `CancellationToken` | (omitido) | Dart no lo tiene; se cancela cerrando el stream o descartando el Future. |
/// | `Task<IReadOnlyList<T>>` | `Future<List<T>>` | Se devuelven listas no modificables por convención. |
///
/// ---
///
/// ## Reconciliación con `datos/repositorios/` (pasada final, §4.2)
///
/// `flutter-datos` implementó contra la forma documentada de `I*Repository.cs`
/// porque este archivo todavía no existía cuando empezó. Al aparecer, varias
/// firmas no coincidían. Criterio aplicado, el mismo de siempre: **gana la que
/// tiene implementación y tests**, así que estas interfaces se ajustaron a sus
/// clases y no al revés. Los cambios fueron: `buscar`, `anular`, `abrir` y
/// `cerrar`.
///
/// Donde el contrato pide algo que **nadie implementó**, no hay a quién ceder:
/// se marca `PENDIENTE (flutter-datos)` en el propio método. Son cinco
/// `Stream` de observación, `listarCategorias`, `siguienteNumero` y todo
/// `RepositorioReportes`. Ninguno es capricho: los `Stream` son lo que hace que
/// dos mozos no tomen la misma mesa y que la barra de caja se refresque sola, y
/// `siguienteNumero` es el correlativo `M01-000123` de §6.
///
/// **Ninguna clase de `datos/repositorios/` declara todavía `implements
/// Repositorio*`.** Mientras no lo hagan, el compilador no verifica nada de
/// esto y `composicion.dart` no puede tipar los getters de `BaseDatosPagoYa`.
/// Ese `implements` es lo que convierte este archivo de documentación en
/// contrato.
library;

import 'package:meta/meta.dart';

import '../dominio/dominio.dart';

/// # Veredicto del outbox (pasada final de reconciliación — §4.2, ya NO es
/// provisional)
///
/// `AlmacenOutbox` es **canónico en `nube/puerto_outbox.dart`**, y
/// `EventoSyncLocal` / `CambioRemoto` / `EntidadesSync` en
/// `nube/contratos_sync.dart`. Este archivo solo lo **reexporta**, para que
/// quien implemente la persistencia siga necesitando un único import.
///
/// ## Por qué gana la nube y no `datos/`
///
/// El criterio de siempre —gana quien tiene implementación y tests— aquí
/// empata: `datos/outbox.dart` tiene `OutboxStore` + dos suites, y
/// `nube/contratos_sync.dart` tiene `ServicioSyncNube`, `TransporteHttpSync` y
/// cuatro suites. Así que decide la arquitectura:
///
/// 1. **El puerto pertenece a quien lo consume.** `AlmacenOutbox` existe para
///    que `lib/nube/` no dependa de drift, exactamente como `PagoYa.Cloud`
///    depende de `IOutboxStore` y no de `PagoYa.Data`. Si el puerto viviera
///    aquí, `nube/` importaría `datos/` y la inversión de dependencias se
///    perdería.
/// 2. **`EventoSyncLocal` y `CambioRemoto` son el contrato del cable**, no de la
///    tabla: sus nombres de campo tienen que coincidir con
///    `server/PagoYa.Api/Contratos/Dtos.cs`. Ponerlos donde vive la
///    serialización HTTP es lo que evita que se desincronicen del backend.
/// 3. La versión de `nube/` es además la que sabe hablar por el cable
///    (`aJson()`, `CambioRemoto.desdeJson`); la de `datos/` solo sabe leer una
///    fila de SQLite, que es un detalle de implementación.
///
/// ## Qué le toca hacer a `flutter-datos` (no es un rediseño, son extensiones)
///
/// Retirar de `datos/outbox.dart` las declaraciones de `EventoSyncLocal`,
/// `CambioRemoto` y `EntidadesSync`, importar las canónicas, y conservar lo
/// suyo como **extensiones** sobre ellas, que no pierde nada:
///
/// ```dart
/// import '../nube/contratos_sync.dart';
///
/// extension EventoSyncLocalFila on EventoSyncLocal {
///   static EventoSyncLocal desdeFila(Map<String, Object?> f) => …;
///   Map<String, Object?> get payload => …;   // jsonDecode tolerante
/// }
/// extension CatalogoLocal on EntidadesSync {
///   static const List<String> todas = …;                 // orden del contrato
///   static const Set<String> aplicadasPorEscritorio = …; // lo que la PC aplica hoy
/// }
/// ```
///
/// `OutboxHelper`, `OperacionesSync` y `EstadoOutbox` **se quedan en `datos/`**:
/// esos sí son de la tabla (`INSERT` en la transacción, columna `estado`), no
/// del cable, y nadie más los declara.
///
/// Y `OutboxStore` debe declarar `implements AlmacenOutbox`. Hoy no lo hace, y
/// por eso no encaja en `FabricaSync.crear(outbox: …)`. Le faltan tres cosas:
/// `contarDeadLetter()`, `reencolarDeadLetter()`, y que `registrarFallo`
/// devuelva `Future<int>` (cuántos cayeron a dead-letter en esa llamada) en vez
/// de `Future<void>` — es el número que pinta la pantalla de nube.
export '../nube/puerto_outbox.dart';

// ---------------------------------------------------------------------------
// Productos
// ---------------------------------------------------------------------------

/// Repositorio de [Producto]. Espejo de `IProductoRepository`.
abstract interface class RepositorioProductos {
  /// Producto por Id, o `null`.
  Future<Producto?> obtenerPorId(String id);

  /// Búsqueda por código de barras / SKU. Es la ruta caliente del POS: la usa
  /// tanto el teclado como el escáner de cámara, así que debe ir por índice.
  Future<Producto?> obtenerPorCodigo(String codigo);

  /// Lista productos activos, con filtro opcional por nombre o código.
  ///
  /// Posicional y sin `categoria`: así lo implementó `ProductoRepositorio`, y
  /// gana la implementación. El filtro por categoría se hace en memoria sobre
  /// el resultado — un catálogo de bodega son cientos de filas, no millones.
  Future<List<Producto>> buscar([String? filtro]);

  /// Lista las categorías distintas presentes en el catálogo.
  ///
  /// PENDIENTE (flutter-datos): sin implementar. Es un
  /// `SELECT DISTINCT categoria FROM productos WHERE activo = 1 ORDER BY 1`.
  /// Lo consume el selector de categorías del inventario y del onboarding.
  Future<List<String>> listarCategorias();

  /// Inserta o actualiza (upsert por Id). **Debe** escribir el evento
  /// correspondiente en `outbox_sync` dentro de la MISMA transacción.
  Future<void> guardar(Producto producto);

  /// Borrado lógico (marca inactivo, no borra: rompería el historial de ventas).
  Future<void> desactivar(String id);

  /// Observa el catálogo para que la pantalla de inventario se refresque sola.
  ///
  /// PENDIENTE (flutter-datos): sin implementar.
  Stream<List<Producto>> observarCatalogo();
}

// ---------------------------------------------------------------------------
// Ventas
// ---------------------------------------------------------------------------

/// Repositorio de [Venta] con su detalle. Espejo de `IVentaRepository`.
abstract interface class RepositorioVentas {
  /// Venta con sus detalles cargados, o `null`.
  Future<Venta?> obtenerPorId(String id);

  /// Registra una venta completa (cabecera + detalles) de forma **atómica**.
  ///
  /// La implementación DEBE, en una sola transacción:
  /// 1. insertar la cabecera y el detalle,
  /// 2. registrar el movimiento de kardex en `inventario`,
  /// 3. refrescar la caché `productos.stock_actual`,
  /// 4. encolar el evento en `outbox_sync`.
  ///
  /// El paso 4 va **dentro** de la transacción a propósito (regla §5.3): si se
  /// encolara después y la app muere en medio, la venta existiría localmente y
  /// jamás llegaría a la nube. La red se intenta *después* de commitear.
  Future<void> registrar(Venta venta);

  /// Ventas de una sesión de caja.
  Future<List<Venta>> listarPorCaja(String cajaId);

  /// Anula una venta: borrado lógico + reversa del kardex.
  ///
  /// Sin `motivo`: `VentaRepositorio.anular` no lo recibe y gana la
  /// implementación. `ventas` no tiene columna para el motivo en el
  /// `esquema.sql` compartido, así que añadirlo aquí habría exigido una
  /// migración en la PC y en el móvil a la vez para un campo que nadie lee.
  Future<void> anular(String id);

  /// Siguiente número correlativo para esta caja.
  ///
  /// Formato acordado en MOBILE-ARQUITECTURA §6: `<prefijo>-<correlativo>`,
  /// p. ej. `M01-000123` en el móvil y `C01-000123` en la PC. Sin el prefijo,
  /// dos cajas offline generan el mismo número y el reporte consolidado no
  /// cuadra.
  ///
  /// PENDIENTE (flutter-datos): no está en `VentaRepositorio`. La lógica ya
  /// existe en `datos/correlativos.dart` (`Correlativos`) y en
  /// `ConfiguracionDispositivo.prefijoDispositivo()`; falta exponerla por aquí,
  /// que es donde la busca quien cobra.
  Future<String> siguienteNumero(String prefijoDispositivo);
}

// ---------------------------------------------------------------------------
// Caja
// ---------------------------------------------------------------------------

/// Repositorio de sesiones de [Caja] y sus [MovimientoCaja].
/// Espejo de `ICajaRepository`.
abstract interface class RepositorioCaja {
  /// Sesión abierta actualmente, o `null` si no hay ninguna.
  Future<Caja?> obtenerCajaAbierta();

  /// Sesión por Id.
  Future<Caja?> obtenerPorId(String id);

  /// Abre una sesión con su fondo inicial.
  ///
  /// Se llamaba `abrirCaja`; `CajaRepositorio` lo llama `abrir` y gana la
  /// implementación (dentro de `RepositorioCaja` el sufijo era redundante).
  Future<Caja> abrir(Caja caja);

  /// Cierra la sesión registrando arqueo y diferencia.
  ///
  /// [montoContado] es lo que el cajero contó de verdad en el cajón; la
  /// diferencia contra lo esperado la calcula la implementación. Este parámetro
  /// no estaba en mi versión y es exactamente el dato que hace útil el arqueo:
  /// sin él, "cerrar caja" no puede detectar un faltante.
  Future<Caja> cerrar(Caja caja, {required Dinero montoContado});

  /// Registra un movimiento de efectivo (ingreso, egreso, retiro).
  Future<void> registrarMovimiento(MovimientoCaja movimiento);

  /// Movimientos de una sesión.
  Future<List<MovimientoCaja>> listarMovimientos(String cajaId);

  /// Sesiones cuya apertura (fecha local) cae en `[desde, hasta]` inclusive,
  /// más recientes primero.
  Future<List<Caja>> listarSesiones(DateTime desde, DateTime hasta);

  /// Observa la caja abierta: la barra superior del POS muestra el efectivo en
  /// tiempo real sin tener que consultar en cada venta.
  ///
  /// PENDIENTE (flutter-datos): sin implementar.
  Stream<Caja?> observarCajaAbierta();
}

// ---------------------------------------------------------------------------
// Mesas / comandas (rubro comida)
// ---------------------------------------------------------------------------

/// Salón: mesas, comandas abiertas y sus líneas. Espejo de `IMesaRepository`.
///
/// Este es el **caso de uso estrella del móvil**: el mozo toma el pedido en la
/// mesa con el celular. Ojo con MOBILE-ARQUITECTURA §6.3: `mesa`, `pedido` y
/// `pedido_linea` todavía NO están en las entidades que sincroniza el backend;
/// hasta que `backend-seats` las agregue, esto funciona offline por dispositivo.
abstract interface class RepositorioMesas {
  /// Mesas ordenadas por zona y número.
  Future<List<Mesa>> listarMesas({bool soloActivas = true});

  /// Mesa por Id, o `null`.
  Future<Mesa?> obtenerMesa(String id);

  /// Upsert de una mesa.
  Future<void> guardarMesa(Mesa mesa);

  /// Borrado lógico de una mesa.
  Future<void> desactivarMesa(String id);

  /// Cambia solo el estado operativo (mapa del salón).
  Future<void> cambiarEstadoMesa(String id, EstadoMesa estado);

  /// Observa el mapa del salón. Con varios mozos en el mismo salón esto es lo
  /// que evita que dos tomen la misma mesa.
  ///
  /// PENDIENTE (flutter-datos): sin implementar. Es el más caro de los cinco
  /// `Stream` que faltan, porque sin él el caso de uso estrella del móvil
  /// (varios mozos, un salón) se apoya en que cada uno recargue a mano.
  Stream<List<Mesa>> observarMesas();

  /// Pedido abierto de una mesa (con líneas), o `null` si está libre.
  Future<Pedido?> obtenerPedidoAbierto(String mesaId);

  /// Pedido por Id (con líneas), o `null`.
  Future<Pedido?> obtenerPedido(String pedidoId);

  /// Upsert de la cabecera del pedido.
  Future<void> guardarPedido(Pedido pedido);

  /// Líneas del pedido, en orden de creación.
  Future<List<PedidoLinea>> listarLineas(String pedidoId);

  /// Agrega una línea a la comanda.
  Future<void> agregarLinea(PedidoLinea linea);

  /// Quita una línea de la comanda.
  Future<void> quitarLinea(String lineaId);

  /// Marca como enviadas a cocina todas las líneas pendientes del pedido.
  Future<void> marcarLineasEnviadas(String pedidoId);

  /// Suma de los importes de las líneas del pedido.
  Future<Dinero> totalPedido(String pedidoId);
}

// ---------------------------------------------------------------------------
// Hotel
// ---------------------------------------------------------------------------

/// Hospedaje: habitaciones, estadías y consumos. Espejo de `IHotelRepository`.
abstract interface class RepositorioHotel {
  /// Habitaciones ordenadas por piso y número.
  Future<List<Habitacion>> listarHabitaciones({bool soloActivas = true});

  /// Habitación por Id, o `null`.
  Future<Habitacion?> obtenerHabitacion(String id);

  /// Upsert de una habitación.
  Future<void> guardarHabitacion(Habitacion habitacion);

  /// Borrado lógico de una habitación.
  Future<void> desactivarHabitacion(String id);

  /// Cambia solo el estado operativo (mapa de recepción).
  Future<void> cambiarEstadoHabitacion(String id, EstadoHabitacion estado);

  /// Observa el mapa de recepción.
  ///
  /// PENDIENTE (flutter-datos): sin implementar.
  Stream<List<Habitacion>> observarHabitaciones();

  /// Estadía activa de una habitación (huésped actual), o `null`.
  Future<EstadiaHabitacion?> obtenerEstadiaActiva(String habitacionId);

  /// Estadía por Id, o `null`.
  Future<EstadiaHabitacion?> obtenerEstadia(String estadiaId);

  /// Upsert de una estadía: el check-in la crea, el check-out la cierra.
  Future<void> guardarEstadia(EstadiaHabitacion estadia);

  /// Consumos de una estadía, del más reciente al más antiguo.
  Future<List<ConsumoHabitacion>> listarConsumos(String estadiaId);

  /// Carga un consumo a la cuenta de la habitación.
  Future<void> agregarConsumo(ConsumoHabitacion consumo);

  /// Quita un consumo de la cuenta.
  Future<void> quitarConsumo(String consumoId);

  /// Suma de los consumos de la estadía.
  Future<Dinero> totalConsumos(String estadiaId);
}

// ---------------------------------------------------------------------------
// Proveedores y usuarios
// ---------------------------------------------------------------------------

/// Proveedores. Espejo de `IProveedorRepository`.
abstract interface class RepositorioProveedores {
  /// Proveedores ordenados por nombre.
  Future<List<Proveedor>> listar({bool soloActivos = true});

  /// Proveedor por Id, o `null`.
  Future<Proveedor?> obtenerPorId(String id);

  /// Upsert de un proveedor.
  Future<void> guardar(Proveedor proveedor);

  /// Borrado lógico.
  Future<void> desactivar(String id);
}

/// Usuarios locales del POS (login offline). Espejo de `IUsuarioRepository`.
///
/// En móvil esto cobra más importancia que en la PC: varios mozos comparten el
/// mismo local y cada comanda debe quedar atribuida a quien la tomó.
abstract interface class RepositorioUsuarios {
  /// `false` en el primer arranque: hay que mostrar el setup inicial.
  Future<bool> existeAlguno();

  /// Cantidad de usuarios activos (límite del tier Base).
  Future<int> contarActivos();

  /// Busca por nombre de login, insensible a mayúsculas. `null` si no existe.
  Future<Usuario?> obtenerPorNombre(String nombreUsuario);

  /// Todos los usuarios, activos e inactivos (pantalla de gestión).
  Future<List<Usuario>> listar();

  /// Upsert de un usuario.
  Future<void> guardar(Usuario usuario);

  /// Borrado lógico (preserva el historial de ventas del usuario).
  Future<void> desactivar(String id);

  /// Marca el último acceso tras un login exitoso.
  Future<void> registrarAcceso(String id, DateTime cuandoUtc);
}

// ---------------------------------------------------------------------------
// Reportes
// ---------------------------------------------------------------------------

/// Consultas de agregación de solo-lectura. Espejo de `IReportesRepository`.
///
/// PENDIENTE (flutter-datos): **no existe `ReportesRepositorio`**. Es el único
/// de los ocho repositorios sin ningún archivo detrás, y `composicion.dart` ya
/// expone `repositorioReportesProvider` contra `BaseDatosPagoYa.reportes`.
/// Es lo que alimenta la pantalla de "ventas del día", que es lo primero que
/// mira el dueño al cerrar.
abstract interface class RepositorioReportes {
  /// Reporte del día [fecha] (fecha **local** del POS, no UTC).
  Future<ReporteDia> obtenerReporteDelDia(DateTime fecha);

  /// Todas las ventas (incluidas las anuladas) en `[desde, hasta]` inclusive,
  /// más recientes primero. Para exportar y compartir por WhatsApp.
  Future<List<VentaResumen>> listarVentasRango(DateTime desde, DateTime hasta);
}

/// Reporte consolidado de una jornada. Espejo del record `ReporteDia`.
@immutable
final class ReporteDia {
  /// Crea el reporte del día.
  const ReporteDia({
    required this.fecha,
    required this.totalVendido,
    required this.cantidadVentas,
    required this.ticketPromedio,
    required this.productosVendidos,
    required this.ultimasVentas,
    required this.masVendidos,
    required this.porMetodo,
  });

  /// Día sin ventas. Evita `null` en la UI.
  factory ReporteDia.vacio(DateTime fecha) => ReporteDia(
        fecha: fecha,
        totalVendido: Dinero.cero,
        cantidadVentas: 0,
        ticketPromedio: Dinero.cero,
        productosVendidos: 0,
        ultimasVentas: const <VentaResumen>[],
        masVendidos: const <ProductoRanking>[],
        porMetodo: const <TotalPorMetodo>[],
      );

  /// Día del reporte (fecha local, hora en cero).
  final DateTime fecha;

  /// Total vendido en soles.
  final Dinero totalVendido;

  /// Número de ventas completadas.
  final int cantidadVentas;

  /// Ticket promedio.
  final Dinero ticketPromedio;

  /// Unidades vendidas (no es dinero: puede ser fraccionario por kilos).
  final double productosVendidos;

  /// Últimas ventas del día, incluidas las anuladas (trazabilidad).
  final List<VentaResumen> ultimasVentas;

  /// Ranking de más vendidos (solo ventas completadas).
  final List<ProductoRanking> masVendidos;

  /// Desglose por método de pago, para conciliar el arqueo.
  final List<TotalPorMetodo> porMetodo;
}

/// Fila de "últimas ventas". Incluye anuladas a propósito.
@immutable
final class VentaResumen {
  /// Crea la fila del resumen.
  const VentaResumen({
    required this.id,
    required this.numero,
    required this.fechaHora,
    required this.metodo,
    required this.total,
    required this.estado,
  });

  /// Id de la venta.
  final String id;

  /// Correlativo legible (`M01-000123`).
  final String numero;

  /// Momento del cobro.
  final DateTime fechaHora;

  /// Método de pago.
  final MetodoPago metodo;

  /// Total cobrado.
  final Dinero total;

  /// Estado (completada / anulada).
  final EstadoVenta estado;
}

/// Producto dentro del ranking de más vendidos.
@immutable
final class ProductoRanking {
  /// Crea una fila del ranking.
  const ProductoRanking({
    required this.nombre,
    required this.unidades,
    required this.total,
  });

  /// Nombre del producto.
  final String nombre;

  /// Unidades vendidas.
  final double unidades;

  /// Importe acumulado.
  final Dinero total;
}

/// Total y cantidad de ventas por método de pago.
@immutable
final class TotalPorMetodo {
  /// Crea el total de un método de pago.
  const TotalPorMetodo({
    required this.metodo,
    required this.total,
    required this.cantidad,
  });

  /// Método de pago agregado.
  final MetodoPago metodo;

  /// Importe acumulado.
  final Dinero total;

  /// Número de ventas con ese método.
  final int cantidad;
}

// ---------------------------------------------------------------------------
// Outbox — definido por `flutter-sync`, reexportado arriba
// ---------------------------------------------------------------------------
//
// `AlmacenOutbox`, `EventoSyncLocal` y `CambioRemoto` viven en
// `nube/puerto_outbox.dart` y `nube/contratos_sync.dart`. Quien implemente la
// persistencia debe respetar dos reglas que se documentan aquí porque son de la
// capa de datos, no del transporte:
//
// 1. **La escritura al outbox va DENTRO de la misma transacción** que la venta
//    (regla §5.3). Si se encolara después y la app muere en medio, la venta
//    existiría localmente y jamás llegaría a la nube.
//
// 2. **`productos.stock_actual` es caché derivada, no la verdad.** Al aplicar
//    cambios remotos con last-write-wins, recalcúlalo desde el kardex
//    (`inventario`, append-only) en vez de copiar el campo del payload remoto.
//    Con dos cajas vendiendo a la vez, sobrescribirlo pierde ventas
//    (riesgo conocido, MOBILE-ARQUITECTURA §6).
