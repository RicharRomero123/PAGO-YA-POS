/// Carrito de la venta en curso y datos del pago.
///
/// Dueño: `flutter-ui`. Port de `CobroRapidoViewModel.Carrito` +
/// `CarritoItemViewModel`, con dos añadidos que el escritorio no necesita:
/// personalización por línea (rubro comida) y control de stock al agregar.
///
/// **Aquí no se escribe nada en SQLite.** Este archivo solo mantiene el estado
/// de la venta que el cajero está armando; guardarla es de `cobro_estado.dart`,
/// y el cálculo de importes es de `CalculoVenta` (`pagoya_core`), nunca de un
/// `double` suelto en un widget.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import 'catalogo_estado.dart';

// ---------------------------------------------------------------------------
// Personalización (modificadores del rubro comida)
// ---------------------------------------------------------------------------

/// Lo que el cajero eligió en el diálogo de modificadores de un producto.
@immutable
final class SeleccionPersonalizacion {
  /// Crea una selección.
  const SeleccionPersonalizacion({
    this.opciones = const <OpcionModificador>[],
    this.nota,
  });

  /// Selección vacía: producto simple, sin modificadores ni nota.
  static const SeleccionPersonalizacion ninguna = SeleccionPersonalizacion();

  /// Opciones marcadas, en el orden en que aparecen los grupos.
  final List<OpcionModificador> opciones;

  /// Nota libre para la cocina ("sin cebolla").
  final String? nota;

  /// Suma de los recargos de las opciones elegidas.
  Dinero get recargo =>
      Dinero.sumar(opciones.map((OpcionModificador o) => o.precioExtra));

  /// Sufijo que se pega al nombre para congelar la descripción de venta.
  String get sufijo => opciones.isEmpty
      ? ''
      : ' (${opciones.map((OpcionModificador o) => o.nombre).join(', ')})';

  /// `true` si no hay nada elegido ni escrito.
  bool get esVacia =>
      opciones.isEmpty && (nota == null || nota!.trim().isEmpty);

  /// Firma estable para distinguir dos líneas del mismo producto.
  String get firma =>
      '${opciones.map((OpcionModificador o) => o.nombre).join('+')}#'
      '${nota?.trim() ?? ''}';
}

// ---------------------------------------------------------------------------
// Línea del carrito
// ---------------------------------------------------------------------------

/// Una línea del carrito. Port de `CarritoItemViewModel`.
///
/// La cantidad es `int` a propósito, igual que en el escritorio: el carrito del
/// POS sube y baja de uno en uno, y así `importe = precio × cantidad` es exacto
/// y no necesita redondeo.
@immutable
final class LineaCarrito {
  /// Crea una línea.
  const LineaCarrito({
    required this.clave,
    required this.productoId,
    required this.nombre,
    required this.descripcion,
    required this.precioUnitario,
    required this.cantidad,
    required this.controlaStock,
    required this.stockDisponible,
    this.nota,
  });

  /// Identidad de la línea: producto + firma de personalización.
  ///
  /// Dos "Pollo a la brasa" con salsas distintas son **dos líneas**, no una de
  /// cantidad 2: la cocina tiene que poder leerlas por separado.
  final String clave;

  /// Producto del catálogo.
  final String productoId;

  /// Nombre limpio del producto (sin modificadores), para la lista compacta.
  final String nombre;

  /// Descripción congelada que va al ticket: nombre + modificadores.
  final String descripcion;

  /// Precio unitario ya con descuento del producto y recargos de modificadores.
  final Dinero precioUnitario;

  /// Unidades.
  final int cantidad;

  /// `true` si el producto descuenta stock.
  final bool controlaStock;

  /// Stock que había al agregar, para no pasarse al subir la cantidad.
  final double stockDisponible;

  /// Nota de cocina.
  final String? nota;

  /// `ImporteLinea => PrecioUnitario * Cantidad` del escritorio.
  Dinero get importe => precioUnitario * cantidad;

  /// Vista de la línea para `CalculoVenta`.
  LineaCobro get aLineaCobro => LineaCobro(
        productoId: productoId,
        nombre: descripcion,
        precioUnitario: precioUnitario,
        cantidad: cantidad,
      );

  /// Copia con otra cantidad.
  LineaCarrito conCantidad(int nueva) => LineaCarrito(
        clave: clave,
        productoId: productoId,
        nombre: nombre,
        descripcion: descripcion,
        precioUnitario: precioUnitario,
        cantidad: nueva,
        controlaStock: controlaStock,
        stockDisponible: stockDisponible,
        nota: nota,
      );
}

/// Qué pasó al intentar agregar un producto al carrito.
enum ResultadoCarrito {
  /// Se agregó.
  agregado,

  /// El producto está en cero y controla stock.
  sinStock,

  /// Hay stock, pero no tanto como se pidió.
  stockInsuficiente;

  /// Mensaje ya redactado para el aviso de la pantalla. `null` si todo fue bien.
  String? mensajeFallo(String nombreProducto, {double disponible = 0}) =>
      switch (this) {
        ResultadoCarrito.agregado => null,
        ResultadoCarrito.sinStock => 'Sin stock: $nombreProducto',
        ResultadoCarrito.stockInsuficiente =>
          'Solo quedan ${disponible.toStringAsFixed(disponible == disponible.roundToDouble() ? 0 : 3)} de $nombreProducto',
      };
}

// ---------------------------------------------------------------------------
// El carrito
// ---------------------------------------------------------------------------

/// Carrito de la venta en curso.
final NotifierProvider<CarritoNotifier, List<LineaCarrito>> carritoProvider =
    NotifierProvider<CarritoNotifier, List<LineaCarrito>>(CarritoNotifier.new);

/// Agrega, quita y ajusta cantidades. **Sin efectos en la base de datos.**
final class CarritoNotifier extends Notifier<List<LineaCarrito>> {
  @override
  List<LineaCarrito> build() => const <LineaCarrito>[];

  /// Agrega un producto (o suma una unidad si ya estaba con la misma
  /// personalización).
  ///
  /// Devuelve el motivo cuando **no** se pudo agregar, para que la pantalla
  /// avise sin tener que replicar la regla de stock.
  ResultadoCarrito agregar(
    Producto producto, {
    int cantidad = 1,
    SeleccionPersonalizacion personalizacion =
        SeleccionPersonalizacion.ninguna,
  }) {
    if (producto.agotado) return ResultadoCarrito.sinStock;

    final clave = '${producto.id}|${personalizacion.firma}';
    final indice = state.indexWhere((LineaCarrito l) => l.clave == clave);
    final actual = indice < 0 ? 0 : state[indice].cantidad;
    final nueva = actual + cantidad;

    if (producto.controlaStock && nueva > producto.stockActual) {
      return ResultadoCarrito.stockInsuficiente;
    }

    if (indice >= 0) {
      final copia = <LineaCarrito>[...state];
      copia[indice] = copia[indice].conCantidad(nueva);
      state = List<LineaCarrito>.unmodifiable(copia);
      return ResultadoCarrito.agregado;
    }

    final linea = LineaCarrito(
      clave: clave,
      productoId: producto.id,
      nombre: producto.nombre,
      descripcion: '${producto.nombre}${personalizacion.sufijo}',
      precioUnitario: producto.precioFinal + personalizacion.recargo,
      cantidad: nueva,
      controlaStock: producto.controlaStock,
      stockDisponible: producto.stockActual,
      nota: personalizacion.nota,
    );
    state = List<LineaCarrito>.unmodifiable(<LineaCarrito>[...state, linea]);
    return ResultadoCarrito.agregado;
  }

  /// Sube una unidad. Respeta el stock igual que [agregar].
  ResultadoCarrito incrementar(String clave) {
    final indice = state.indexWhere((LineaCarrito l) => l.clave == clave);
    if (indice < 0) return ResultadoCarrito.agregado;

    final linea = state[indice];
    if (linea.controlaStock && linea.cantidad + 1 > linea.stockDisponible) {
      return ResultadoCarrito.stockInsuficiente;
    }
    final copia = <LineaCarrito>[...state];
    copia[indice] = linea.conCantidad(linea.cantidad + 1);
    state = List<LineaCarrito>.unmodifiable(copia);
    return ResultadoCarrito.agregado;
  }

  /// Baja una unidad; al llegar a cero quita la línea.
  void decrementar(String clave) {
    final indice = state.indexWhere((LineaCarrito l) => l.clave == clave);
    if (indice < 0) return;

    final linea = state[indice];
    if (linea.cantidad <= 1) {
      quitar(clave);
      return;
    }
    final copia = <LineaCarrito>[...state];
    copia[indice] = linea.conCantidad(linea.cantidad - 1);
    state = List<LineaCarrito>.unmodifiable(copia);
  }

  /// Quita la línea entera.
  void quitar(String clave) {
    state = List<LineaCarrito>.unmodifiable(
      state.where((LineaCarrito l) => l.clave != clave).toList(),
    );
  }

  /// Vacía el carrito (tras cobrar, o con el botón "Cancelar venta").
  void limpiar() => state = const <LineaCarrito>[];

  /// Reemplaza el carrito de golpe. Lo usa el cobro de una mesa: la comanda ya
  /// tiene sus líneas y no se re-teclean.
  void reemplazar(List<LineaCarrito> lineas) =>
      state = List<LineaCarrito>.unmodifiable(lineas);
}

/// Totales de la venta en curso: subtotal, IGV 18 % y total.
///
/// Sale de `CalculoVenta`, que es el port literal de `RecalcularTotales()` del
/// escritorio. **Ninguna pantalla suma precios por su cuenta.**
final Provider<TotalesVenta> totalesProvider = Provider<TotalesVenta>((Ref ref) {
  final lineas = ref.watch(carritoProvider);
  if (lineas.isEmpty) return TotalesVenta.vacio;
  return CalculoVenta.calcular(
    lineas.map((LineaCarrito l) => l.aLineaCobro),
  );
});

// ---------------------------------------------------------------------------
// Pago
// ---------------------------------------------------------------------------

/// Cómo se está cobrando la venta en curso.
@immutable
final class EstadoPago {
  /// Crea el estado del pago.
  const EstadoPago({this.metodo = MetodoPago.efectivo, this.textoRecibido = ''});

  /// Método elegido. Los tres visibles en móvil son efectivo, Yape/Plin y
  /// tarjeta, igual que `CobroRapidoViewModel.MetodosPago`.
  final MetodoPago metodo;

  /// Lo tecleado en el numpad, tal cual. Se guarda como **texto** y no como
  /// número para que "10." y "10.5" se puedan escribir dígito a dígito sin que
  /// el estado se los reescriba bajo los dedos.
  final String textoRecibido;

  /// Monto recibido ya parseado, con el mismo parser del escritorio.
  Dinero get recibido => CalculoVenta.parsearMonto(textoRecibido);

  /// Copia con cambios.
  EstadoPago copiarCon({MetodoPago? metodo, String? textoRecibido}) => EstadoPago(
        metodo: metodo ?? this.metodo,
        textoRecibido: textoRecibido ?? this.textoRecibido,
      );
}

/// Estado del pago de la venta en curso.
final NotifierProvider<PagoNotifier, EstadoPago> pagoProvider =
    NotifierProvider<PagoNotifier, EstadoPago>(PagoNotifier.new);

/// Método de pago y monto recibido. El teclado numérico despacha aquí.
final class PagoNotifier extends Notifier<EstadoPago> {
  /// Máximo de dígitos enteros que acepta el numpad (S/ 999 999.99).
  static const int _maxEnteros = 6;

  @override
  EstadoPago build() => const EstadoPago();

  /// Cambia el método de pago. Al salir de efectivo se borra el monto recibido:
  /// un vuelto colgado de un pago con Yape es una lectura falsa peligrosa.
  void elegirMetodo(MetodoPago metodo) {
    state = metodo == MetodoPago.efectivo
        ? state.copiarCon(metodo: metodo)
        : const EstadoPago(metodo: MetodoPago.billeteraDigital)
            .copiarCon(metodo: metodo);
  }

  /// Añade un dígito o el punto decimal. Ignora lo que no cabe en un importe.
  void escribir(String tecla) {
    final texto = state.textoRecibido;

    if (tecla == '.') {
      if (texto.contains('.')) return;
      state = state.copiarCon(textoRecibido: texto.isEmpty ? '0.' : '$texto.');
      return;
    }

    final punto = texto.indexOf('.');
    if (punto >= 0) {
      // Como mucho dos decimales: no existen fracciones de céntimo.
      if (texto.length - punto - 1 >= 2) return;
    } else if (texto.length >= _maxEnteros) {
      return;
    }

    // Evita "007": el cero solo se queda si va seguido de punto.
    final base = texto == '0' ? '' : texto;
    state = state.copiarCon(textoRecibido: '$base$tecla');
  }

  /// Borra el último carácter.
  void borrar() {
    final texto = state.textoRecibido;
    if (texto.isEmpty) return;
    state = state.copiarCon(
      textoRecibido: texto.substring(0, texto.length - 1),
    );
  }

  /// Deja el monto recibido en blanco.
  void limpiarMonto() => state = state.copiarCon(textoRecibido: '');

  /// Fija un monto de golpe (botones rápidos: 10, 20, 50, 100, "exacto").
  void fijarMonto(Dinero monto) =>
      state = state.copiarCon(textoRecibido: monto.formatear());

  /// Vuelve al estado inicial tras cobrar.
  void reiniciar() => state = const EstadoPago();
}

/// Vuelto de la venta en curso. Nunca negativo, igual que en el escritorio.
final Provider<Dinero> vueltoProvider = Provider<Dinero>((Ref ref) {
  final pago = ref.watch(pagoProvider);
  if (pago.metodo != MetodoPago.efectivo) return Dinero.cero;
  return CalculoVenta.vuelto(
    pagaCon: pago.recibido,
    total: ref.watch(totalesProvider).total,
  );
});

/// `true` si el efectivo entregado no alcanza (tinte de aviso en el numpad).
final Provider<bool> faltaEfectivoProvider = Provider<bool>((Ref ref) {
  final pago = ref.watch(pagoProvider);
  if (pago.metodo != MetodoPago.efectivo) return false;
  return CalculoVenta.faltaEfectivo(
    pagaCon: pago.recibido,
    total: ref.watch(totalesProvider).total,
  );
});
