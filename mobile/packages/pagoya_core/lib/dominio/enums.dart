// PagoYa Móvil — dominio/enums.dart
//
// PORT 1:1 de `src/PagoYa.Core/Enums/*.cs`.
//
// REGLA CRÍTICA: los valores numéricos son los que viajan por SQLite
// (columnas INTEGER) y por el JSON del outbox (System.Text.Json serializa los
// enums de C# como NÚMERO, no como texto). Cambiar un valor aquí rompe la
// sincronización con la PC de forma silenciosa: una venta anulada llegaría
// como completada, o un pago con Yape se contaría como efectivo en el arqueo.
//
// Por eso cada enum lleva su `valor` explícito y se (de)serializa por número,
// nunca por `index` ni por nombre.

library;

/// Contrato común de los enums del dominio: llevan su código numérico estable.
abstract interface class EnumConValor {
  int get valor;
}

/// Busca el miembro cuyo `valor` coincide; si no existe usa [porDefecto].
///
/// Tolerante a valores desconocidos a propósito: si una versión más nueva de
/// la PC introduce un estado que este móvil no conoce, es mejor degradar al
/// valor por defecto que reventar la sincronización entera.
T enumDesdeValor<T extends EnumConValor>(
  List<T> valores,
  int? codigo,
  T porDefecto,
) {
  if (codigo == null) return porDefecto;
  for (final v in valores) {
    if (v.valor == codigo) return v;
  }
  return porDefecto;
}

/// Método de pago usado por el cliente. Relevante para el arqueo de caja.
/// Espeja `PagoYa.Core.Enums.MetodoPago`.
enum MetodoPago implements EnumConValor {
  /// Efectivo en soles (PEN).
  efectivo(0),

  /// Tarjeta de crédito o débito (POS bancario).
  tarjeta(1),

  /// Billetera digital: Yape, Plin, etc.
  billeteraDigital(2),

  /// Transferencia bancaria.
  transferencia(3),

  /// Venta a crédito / fiado.
  credito(4);

  const MetodoPago(this.valor);
  @override
  final int valor;

  static MetodoPago desde(int? v) => enumDesdeValor(values, v, efectivo);

  /// Etiqueta tal como la muestra el POS de escritorio (`CobroRapidoViewModel.MetodosPago`).
  String get etiqueta => switch (this) {
        efectivo => 'Efectivo',
        billeteraDigital => 'Yape / Plin',
        tarjeta => 'Tarjeta',
        transferencia => 'Transferencia',
        credito => 'Crédito',
      };

  /// Mapeo desde la etiqueta de la UI, igual que `CobroRapidoViewModel.MapearMetodo`.
  static MetodoPago desdeEtiqueta(String etiqueta) => switch (etiqueta) {
        'Efectivo' => efectivo,
        'Yape / Plin' => billeteraDigital,
        'Tarjeta' => tarjeta,
        _ => efectivo,
      };
}

/// Estado del ciclo de vida de una venta. Espeja `EstadoVenta`.
enum EstadoVenta implements EnumConValor {
  /// Venta registrada y pagada.
  completada(0),

  /// Venta anulada (reversa). Se conserva por trazabilidad.
  anulada(1);

  const EstadoVenta(this.valor);
  @override
  final int valor;

  static EstadoVenta desde(int? v) => enumDesdeValor(values, v, completada);
}

/// Estado de una sesión de caja (arqueo). Espeja `EstadoCaja`.
enum EstadoCaja implements EnumConValor {
  /// Caja abierta: acepta ventas y movimientos.
  abierta(0),

  /// Caja cerrada: sesión finalizada tras el arqueo.
  cerrada(1);

  const EstadoCaja(this.valor);
  @override
  final int valor;

  static EstadoCaja desde(int? v) => enumDesdeValor(values, v, abierta);
}

/// Tipo de movimiento de efectivo distinto a una venta. Espeja `TipoMovimientoCaja`.
enum TipoMovimientoCaja implements EnumConValor {
  /// Monto inicial al abrir la caja (fondo).
  aperturaFondo(0),

  /// Ingreso de efectivo (ej. aporte del dueño).
  ingreso(1),

  /// Salida de efectivo (ej. pago a proveedor).
  egreso(2),

  /// Retiro parcial de efectivo de la caja.
  retiro(3);

  const TipoMovimientoCaja(this.valor);
  @override
  final int valor;

  static TipoMovimientoCaja desde(int? v) => enumDesdeValor(values, v, ingreso);

  /// Signo con el que el movimiento entra al arqueo (+ suma, − resta).
  int get signo => switch (this) {
        aperturaFondo || ingreso => 1,
        egreso || retiro => -1,
      };
}

/// Tipo de comprobante emitido. Los códigos siguen el Catálogo 01 de SUNAT.
/// Espeja `TipoComprobante` — OJO: los valores NO son consecutivos.
enum TipoComprobante implements EnumConValor {
  /// Nota de venta / ticket interno. NO es comprobante electrónico SUNAT.
  notaVenta(0),

  /// Factura electrónica. Catálogo 01 SUNAT = "01".
  factura(1),

  /// Boleta de venta electrónica. Catálogo 01 SUNAT = "03".
  boleta(3);

  const TipoComprobante(this.valor);
  @override
  final int valor;

  static TipoComprobante desde(int? v) => enumDesdeValor(values, v, notaVenta);
}

/// Rubro/giro del negocio. Espeja `RubroNegocio`.
/// OJO: `otro` vale 99, no 8.
enum RubroNegocio implements EnumConValor {
  bodega(0, 'bodega'),
  restaurante(1, 'restaurante'),
  cafeteria(2, 'cafeteria'),
  polleria(3, 'polleria'),
  farmacia(4, 'farmacia'),
  ferreteria(5, 'ferreteria'),
  licoreria(6, 'licoreria'),
  hotel(7, 'hotel'),
  otro(99, 'otro');

  const RubroNegocio(this.valor, this.clave);

  @override
  final int valor;

  /// Clave de texto usada por `PlantillasRubro` y por la configuración local.
  /// Debe coincidir carácter a carácter con la del escritorio.
  final String clave;

  static RubroNegocio desde(int? v) => enumDesdeValor(values, v, bodega);

  static RubroNegocio desdeClave(String? clave) {
    final c = (clave ?? '').toLowerCase();
    for (final r in values) {
      if (r.clave == c) return r;
    }
    return bodega;
  }
}

/// Rol de un usuario del POS. Espeja `RolUsuario`.
enum RolUsuario implements EnumConValor {
  /// Dueño/administrador: acceso total.
  administrador(0),

  /// Cajero/empleado: opera ventas y caja.
  cajero(1);

  const RolUsuario(this.valor);
  @override
  final int valor;

  static RolUsuario desde(int? v) => enumDesdeValor(values, v, cajero);
}

/// Estado operativo de una mesa del salón. Espeja `EstadoMesa`.
enum EstadoMesa implements EnumConValor {
  libre(0),
  ocupada(1),
  porCobrar(2),
  reservada(3);

  const EstadoMesa(this.valor);
  @override
  final int valor;

  static EstadoMesa desde(int? v) => enumDesdeValor(values, v, libre);
}

/// Estado de una comanda/cuenta de mesa. Espeja `EstadoPedido`.
enum EstadoPedido implements EnumConValor {
  abierta(0),
  cobrada(1),
  anulada(2);

  const EstadoPedido(this.valor);
  @override
  final int valor;

  static EstadoPedido desde(int? v) => enumDesdeValor(values, v, abierta);
}

/// Estado operativo de una habitación. Espeja `EstadoHabitacion`.
enum EstadoHabitacion implements EnumConValor {
  disponible(0),
  ocupada(1),
  limpieza(2),
  mantenimiento(3),
  reservada(4);

  const EstadoHabitacion(this.valor);
  @override
  final int valor;

  static EstadoHabitacion desde(int? v) => enumDesdeValor(values, v, disponible);
}

/// Estado de una estadía (hospedaje). Espeja `EstadoEstadia`.
enum EstadoEstadia implements EnumConValor {
  activa(0),
  cerrada(1),
  anulada(2);

  const EstadoEstadia(this.valor);
  @override
  final int valor;

  static EstadoEstadia desde(int? v) => enumDesdeValor(values, v, activa);
}

/// Tipo/categoría de habitación. Espeja `TipoHabitacion`.
enum TipoHabitacion implements EnumConValor {
  simple(0),
  doble(1),
  matrimonial(2),
  triple(3),
  suite(4),
  familiar(5);

  const TipoHabitacion(this.valor);
  @override
  final int valor;

  static TipoHabitacion desde(int? v) => enumDesdeValor(values, v, simple);
}

/// Modalidad de cobro del hospedaje. Espeja `TipoCobroHospedaje`.
enum TipoCobroHospedaje implements EnumConValor {
  noche(0),
  hora(1);

  const TipoCobroHospedaje(this.valor);
  @override
  final int valor;

  static TipoCobroHospedaje desde(int? v) => enumDesdeValor(values, v, noche);
}

/// Cómo se define el descuento de un producto. Espeja `TipoDescuento`.
enum TipoDescuento implements EnumConValor {
  /// Sin descuento: se vende al precio normal.
  ninguno(0),

  /// Descuento porcentual (0–100).
  porcentaje(1),

  /// Precio de oferta fijo en soles.
  oferta(2);

  const TipoDescuento(this.valor);
  @override
  final int valor;

  static TipoDescuento desde(int? v) => enumDesdeValor(values, v, ninguno);
}

// -----------------------------------------------------------------------------
//  `TierLicencia` NO vive aquí. Retirado en la pasada final (§4.3).
//
//  El canónico es el de `licencia/estado_licencia.dart` (flutter-licencia): lo
//  usan `mapearTier`, `EstadoLicencia` y cuatro suites de tests; el de este
//  archivo no lo consumía nadie. Además §4.1 ya lo había decidido — el tier es
//  parte del contrato del TOKEN, no del dominio de ventas, y ponerlo aquí
//  obligaba a `flutter-licencia` a esperar a `flutter-datos`.
//
//  Tenerlo duplicado provocaba `ambiguous_export` en el barril `pagoya_core.dart`
//  y tumbaba `main.dart`, `composicion.dart` y toda la UI a la vez. Con este
//  enum ya fuera, el `hide TierLicencia` temporal del barril puede retirarse
//  (lo retira `mobile-lead`: el barril es suyo).
//
//  Si necesitas el tier desde el dominio: `import '../licencia/estado_licencia.dart';`
// -----------------------------------------------------------------------------
