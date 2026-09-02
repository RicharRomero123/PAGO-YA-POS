// PagoYa Móvil — dominio/calculo_venta.dart
//
// PORT del cálculo de totales de `CobroRapidoViewModel` (escritorio).
//
// EL ORIGINAL EN C# ES ESTE (y no se cambia ni una coma):
//
//     private const decimal TasaIgv = 0.18m;
//     ...
//     Total    = Carrito.Sum(c => c.ImporteLinea);        // ImporteLinea = Precio * Cantidad (int)
//     Subtotal = decimal.Round(Total / (1 + TasaIgv), 2);  // MidpointRounding.ToEven
//     Igv      = decimal.Round(Total - Subtotal, 2);
//
// TRES DETALLES QUE HAY QUE RESPETAR SÍ O SÍ
// ------------------------------------------
// 1. El precio del catálogo YA INCLUYE IGV (es lo normal en una bodega
//    peruana). Por eso el total se calcula PRIMERO sumando líneas, y el
//    subtotal se DESAGREGA hacia atrás. Calcular subtotal + 18 % daría otro
//    número por el redondeo.
//
// 2. `decimal.Round(x, 2)` usa redondeo BANCARIO (medio al par). Aquí se
//    replica con aritmética entera en `divRedondeadoMitadPar`.
//
//    Nota: con importes en céntimos el empate exacto es IMPOSIBLE en la
//    división por 1.18 (habría que resolver 18·X ≡ 41 (mod 100), que no tiene
//    solución porque el lado izquierdo siempre es par). Aun así se usa el
//    redondeo bancario para que la implementación sea correcta también si
//    algún día cambia la tasa del IGV.
//
// 3. El IGV NO se calcula como `total * 0.18/1.18`, sino como
//    `total - subtotal`. Así subtotal + igv == total SIEMPRE, y el ticket
//    cuadra al céntimo.

library;

import 'dinero.dart';
import 'enums.dart';

/// Una línea del carrito lista para cobrar.
///
/// Espeja `CarritoItemViewModel`: la cantidad es un `int` (el carrito del POS
/// solo incrementa de uno en uno) y por eso `importe` es exacto, sin redondeo.
final class LineaCobro {
  final String productoId;
  final String nombre;
  final Dinero precioUnitario;
  final int cantidad;

  const LineaCobro({
    required this.productoId,
    required this.nombre,
    required this.precioUnitario,
    this.cantidad = 1,
  });

  /// `ImporteLinea => PrecioUnitario * Cantidad` del escritorio.
  Dinero get importe => precioUnitario * cantidad;

  LineaCobro conCantidad(int nueva) => LineaCobro(
        productoId: productoId,
        nombre: nombre,
        precioUnitario: precioUnitario,
        cantidad: nueva,
      );
}

/// Resultado del cálculo de totales de una venta.
final class TotalesVenta {
  /// Valor de venta (sin IGV).
  final Dinero subTotal;

  /// IGV (18 %) desagregado del total.
  final Dinero igv;

  /// Total a pagar (lo que suma el carrito).
  final Dinero total;

  /// Suma de las cantidades de las líneas (el contador "X ítems" de la UI).
  final int cantidadItems;

  const TotalesVenta({
    required this.subTotal,
    required this.igv,
    required this.total,
    required this.cantidadItems,
  });

  static const TotalesVenta vacio = TotalesVenta(
    subTotal: Dinero.cero,
    igv: Dinero.cero,
    total: Dinero.cero,
    cantidadItems: 0,
  );

  /// Invariante que el ticket debe cumplir siempre.
  bool get cuadra => subTotal + igv == total;

  @override
  String toString() => 'TotalesVenta(sub=${subTotal.formatear()}, '
      'igv=${igv.formatear()}, total=${total.formatear()}, items=$cantidadItems)';
}

/// Cálculo monetario de la venta. Todo el POS pasa por aquí.
abstract final class CalculoVenta {
  /// IGV del Perú expresado en **milésimas** (18 % = 180 ‰).
  ///
  /// Se guarda como entero para que la desagregación sea una división de
  /// enteros exacta y no dependa de `double`.
  static const int tasaIgvMilesimas = 180;

  /// Denominador de la desagregación: 1 + tasa, en milésimas (1.18 -> 1180).
  static const int _factorConIgv = 1000 + tasaIgvMilesimas;

  /// Desagrega un total que YA incluye IGV.
  ///
  /// `subTotal = round(total / 1.18, 2)` con redondeo bancario;
  /// `igv = total - subTotal`.
  static ({Dinero subTotal, Dinero igv}) desagregar(Dinero total) {
    final sub = Dinero.enCentimos(
      divRedondeadoMitadPar(total.centimos * 1000, _factorConIgv),
    );
    return (subTotal: sub, igv: total - sub);
  }

  /// Calcula los totales del carrito, igual que `RecalcularTotales()`.
  static TotalesVenta calcular(Iterable<LineaCobro> lineas) {
    var totalCentimos = 0;
    var items = 0;
    for (final l in lineas) {
      totalCentimos += l.importe.centimos;
      items += l.cantidad;
    }
    final total = Dinero.enCentimos(totalCentimos);
    final d = desagregar(total);
    return TotalesVenta(
      subTotal: d.subTotal,
      igv: d.igv,
      total: total,
      cantidadItems: items,
    );
  }

  /// Vuelto = paga con − total. **Nunca negativo**: si el efectivo no alcanza
  /// devuelve cero, igual que `Vuelto => PagaCon > Total ? PagaCon - Total : 0m`.
  static Dinero vuelto({required Dinero pagaCon, required Dinero total}) =>
      pagaCon > total ? pagaCon - total : Dinero.cero;

  /// True si el efectivo entregado no alcanza (tinte de aviso en la UI).
  /// Espeja `VueltoEsNegativo => PagaCon > 0 && PagaCon < Total`.
  static bool faltaEfectivo({required Dinero pagaCon, required Dinero total}) =>
      pagaCon.esPositivo && pagaCon < total;

  /// Parsea el monto "Paga con" tal como lo hace el escritorio:
  /// `decimal.TryParse(value, NumberStyles.Number, InvariantCulture)` — punto
  /// como separador decimal — y **0 si no parsea** (no lanza).
  ///
  /// Se hace con enteros y no con `double.parse` para que "0.1" no arrastre
  /// error binario: se separa la parte entera de los decimales y se trunca a
  /// 2 dígitos, que es lo máximo que el numpad del POS permite escribir.
  static Dinero parsearMonto(String? texto) {
    final t = (texto ?? '').trim();
    if (t.isEmpty) return Dinero.cero;

    final negativo = t.startsWith('-');
    final cuerpo = negativo ? t.substring(1) : t;
    final partes = cuerpo.split('.');
    if (partes.length > 2) return Dinero.cero;

    final enteroTxt = partes[0].isEmpty ? '0' : partes[0];
    final entero = int.tryParse(enteroTxt);
    if (entero == null) return Dinero.cero;

    var centimos = entero * 100;
    if (partes.length == 2 && partes[1].isNotEmpty) {
      final decTxt = partes[1].padRight(2, '0').substring(0, 2);
      final dec = int.tryParse(decTxt);
      if (dec == null) return Dinero.cero;
      centimos += dec;
    }
    return Dinero.enCentimos(negativo ? -centimos : centimos);
  }
}

/// Arqueo de una sesión de caja.
///
/// PORT de la regla que aplica `CobroRapidoViewModel` al cobrar: **solo el
/// efectivo entra al arqueo** (`if (venta.MetodoPago == MetodoPago.Efectivo)`
/// registra un `MovimientoCaja`), así que un pago con Yape no debe aparecer en
/// el conteo físico del cajón.
final class ArqueoCaja {
  /// Fondo con el que se abrió la caja.
  final Dinero montoApertura;

  /// Ingresos de efectivo (ventas en efectivo + aportes).
  final Dinero ingresos;

  /// Egresos y retiros de efectivo.
  final Dinero egresos;

  const ArqueoCaja({
    required this.montoApertura,
    required this.ingresos,
    required this.egresos,
  });

  /// Efectivo que DEBERÍA haber en el cajón.
  Dinero get esperado => montoApertura + ingresos - egresos;

  /// Diferencia contra lo contado: positiva = sobrante, negativa = faltante.
  Dinero diferencia(Dinero contado) => contado - esperado;

  /// Construye el arqueo a partir de los movimientos de la sesión.
  ///
  /// El movimiento `aperturaFondo` NO se suma a [ingresos]: ya está
  /// representado por [montoApertura], y contarlo dos veces inflaría el
  /// esperado en el monto del fondo.
  static ArqueoCaja desdeMovimientos({
    required Dinero montoApertura,
    required Iterable<({TipoMovimientoCaja tipo, Dinero monto})> movimientos,
  }) {
    var ingresos = 0;
    var egresos = 0;
    for (final m in movimientos) {
      // El fondo ya está representado por montoApertura: contarlo otra vez
      // inflaría el esperado y el arqueo saldría con un sobrante fantasma.
      if (m.tipo == TipoMovimientoCaja.aperturaFondo) continue;

      if (m.tipo.signo > 0) {
        ingresos += m.monto.centimos;
      } else {
        egresos += m.monto.centimos;
      }
    }
    return ArqueoCaja(
      montoApertura: montoApertura,
      ingresos: Dinero.enCentimos(ingresos),
      egresos: Dinero.enCentimos(egresos),
    );
  }
}
