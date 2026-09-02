// ignore_for_file: constant_identifier_names
//
// PagoYa Móvil — dominio/dinero.dart
//
// PORT de la aritmética monetaria del POS de escritorio (C# `decimal`).
//
// POR QUÉ EXISTE ESTA CLASE
// -------------------------
// En el escritorio todos los montos son `decimal` (base 10, exacto para
// centavos). Dart no tiene `decimal`: `double` es binario y 0.1 + 0.2 no es
// 0.3. Si el móvil sumara `double` línea a línea, el total del ticket del
// celular divergiría del de la PC — y esa divergencia se sincroniza a la nube
// y aparece en el arqueo de caja.
//
// Solución: TODO monto vive como **entero de céntimos** (`int`). Dart usa
// enteros de 64 bits nativos en móvil, así que S/ 92 000 000 000 000 000 cabe
// sin problema. Solo al persistir se convierte a `double` con 2 decimales,
// porque el esquema SQLite del escritorio guarda los montos como REAL y el
// esquema **se copia sin cambios de forma** (ver docs/MOBILE-ARQUITECTURA.md §1).
//
// REDONDEO
// --------
// `decimal.Round(x, 2)` en C# usa `MidpointRounding.ToEven` por defecto
// (redondeo bancario: 1.775 -> 1.78, 1.785 -> 1.78). Dart `num.round()` usa
// medio-hacia-arriba. Por eso NUNCA se usa `.round()` sobre doubles aquí:
// todos los redondeos pasan por `divRedondeadoMitadPar`, que trabaja sobre
// enteros y replica ToEven exactamente.

library;

/// División entera redondeada al entero más cercano, con desempate
/// **half-to-even** (bancario), igual que `decimal.Round(..., MidpointRounding.ToEven)`.
///
/// Trabaja solo con enteros: no hay error de representación binaria, así que
/// el resultado es idéntico al de `decimal` de C# siempre que la entrada sea
/// exactamente representable como fracción de enteros (que es el caso: los
/// montos son céntimos y las tasas son racionales fijas).
int divRedondeadoMitadPar(int numerador, int denominador) {
  if (denominador == 0) {
    throw ArgumentError.value(denominador, 'denominador', 'no puede ser 0');
  }
  var n = numerador;
  var d = denominador;
  var negativo = false;
  if (d < 0) {
    d = -d;
    n = -n;
  }
  if (n < 0) {
    negativo = true;
    n = -n;
  }
  var q = n ~/ d;
  final r = n % d;
  final doble = r * 2;
  if (doble > d || (doble == d && q.isOdd)) q += 1;
  return negativo ? -q : q;
}

/// Redondea un `double` al entero más cercano con desempate half-to-even.
///
/// Solo se usa en la frontera con el mundo `double` (lectura de la BD, entrada
/// del usuario). Dentro del dominio se usa la variante entera.
int redondearMitadPar(double v) {
  if (v.isNaN || v.isInfinite) {
    throw ArgumentError.value(v, 'v', 'no es un número finito');
  }
  final piso = v.floor();
  final frac = v - piso;
  if (frac > 0.5) return piso + 1;
  if (frac < 0.5) return piso;
  return piso.isEven ? piso : piso + 1;
}

/// Importe monetario en soles (PEN) representado como **entero de céntimos**.
///
/// Inmutable. Todas las operaciones devuelven un `Dinero` nuevo.
///
/// Paridad con el escritorio: equivale a un `decimal` de escala 2. Las
/// operaciones que en C# no redondean (suma, resta, multiplicación por un
/// entero) tampoco redondean aquí, porque en céntimos son exactas.
final class Dinero implements Comparable<Dinero> {
  /// Importe en céntimos de sol. 1 sol = 100 céntimos.
  final int centimos;

  /// Construye directamente desde céntimos (la representación interna).
  const Dinero.enCentimos(this.centimos);

  /// Cero soles.
  static const Dinero cero = Dinero.enCentimos(0);

  /// Desde un importe en soles.
  ///
  /// Si [soles] es `int` la conversión es exacta. Si es `double` se redondea a
  /// céntimos con half-to-even; el `double` ya trae error binario, así que un
  /// valor como `1.775` (que en binario es 1.7749999…) redondea a `1.77`
  /// mientras que el `decimal` 1.775m de C# redondea a `1.78`. Por eso, para
  /// cálculos con paridad exigida (descuentos porcentuales) se usan las
  /// variantes enteras y no esta fábrica.
  factory Dinero.deSoles(num soles) {
    if (soles is int) return Dinero.enCentimos(soles * 100);
    return Dinero.enCentimos(redondearMitadPar((soles as double) * 100.0));
  }

  /// Lee un monto tal como está guardado en SQLite (columna REAL, 2 decimales).
  ///
  /// La columna siempre se escribió desde un `Dinero`/`decimal` con 2
  /// decimales, así que `valor * 100` cae a menos de 1e-9 de un entero y el
  /// redondeo recupera el céntimo exacto.
  factory Dinero.desdeDb(num? valor) {
    if (valor == null) return Dinero.cero;
    return Dinero.deSoles(valor);
  }

  /// Lee un monto opcional de SQLite (`NULL` -> `null`, no cero).
  static Dinero? desdeDbNulable(num? valor) =>
      valor == null ? null : Dinero.desdeDb(valor);

  /// Valor para persistir en la columna REAL de SQLite / serializar a JSON.
  ///
  /// Siempre tiene como mucho 2 decimales. Es el ÚNICO punto donde el importe
  /// se convierte a `double`: nunca se hace aritmética con el resultado.
  double aDb() => centimos / 100.0;

  /// Alias legible de [aDb] para la UI y los reportes.
  double get enSoles => aDb();

  bool get esCero => centimos == 0;
  bool get esNegativo => centimos < 0;
  bool get esPositivo => centimos > 0;

  Dinero operator +(Dinero otro) => Dinero.enCentimos(centimos + otro.centimos);
  Dinero operator -(Dinero otro) => Dinero.enCentimos(centimos - otro.centimos);
  Dinero operator -() => Dinero.enCentimos(-centimos);

  /// Multiplicación por una cantidad **entera** (el caso del carrito del POS).
  ///
  /// Exacta: espeja `CarritoItemViewModel.ImporteLinea => PrecioUnitario * Cantidad`
  /// donde `Cantidad` es `int`. No redondea porque no hace falta.
  Dinero operator *(int cantidad) => Dinero.enCentimos(centimos * cantidad);

  /// Multiplicación por una cantidad con hasta 3 decimales, expresada en
  /// milésimas (2.5 kg -> 2500). Exacta como racional, redondeo half-to-even
  /// al céntimo — igual que `decimal.Round(Cantidad * Precio, 2)`.
  Dinero porMilesimas(int milesimas) =>
      Dinero.enCentimos(divRedondeadoMitadPar(centimos * milesimas, 1000));

  /// Multiplicación por una cantidad fraccionaria (kg, litros).
  ///
  /// Si [cantidad] es entera, es exacta. Si no, se convierte a milésimas —
  /// la precisión que el POS acepta para cantidades (`0.###` en la UI del
  /// escritorio).
  Dinero porCantidad(num cantidad) {
    if (cantidad is int) return this * cantidad;
    return porMilesimas(redondearMitadPar((cantidad as double) * 1000.0));
  }

  /// Aplica un porcentaje expresado en **centésimas de punto** (18 % -> 1800).
  ///
  /// Exacto y con redondeo bancario, para poder replicar
  /// `decimal.Round(PrecioVenta * (1 - pct/100), 2)` sin pasar por `double`.
  Dinero porcentaje(int centesimasDePunto) =>
      Dinero.enCentimos(divRedondeadoMitadPar(centimos * centesimasDePunto, 10000));

  @override
  int compareTo(Dinero otro) => centimos.compareTo(otro.centimos);

  bool operator <(Dinero otro) => centimos < otro.centimos;
  bool operator <=(Dinero otro) => centimos <= otro.centimos;
  bool operator >(Dinero otro) => centimos > otro.centimos;
  bool operator >=(Dinero otro) => centimos >= otro.centimos;

  @override
  bool operator ==(Object otro) => otro is Dinero && otro.centimos == centimos;

  @override
  int get hashCode => centimos.hashCode;

  /// Texto con 2 decimales y punto decimal (`"12.30"`). Sin símbolo.
  String formatear() {
    final negativo = centimos < 0;
    final abs = negativo ? -centimos : centimos;
    final enteros = abs ~/ 100;
    final decs = (abs % 100).toString().padLeft(2, '0');
    return '${negativo ? '-' : ''}$enteros.$decs';
  }

  /// Texto para el ticket y la UI: `"S/ 12.30"`.
  String formatearConSimbolo() => 'S/ ${formatear()}';

  @override
  String toString() => 'Dinero(${formatear()})';

  /// Suma de una colección de importes (sin redondeo: exacta).
  static Dinero sumar(Iterable<Dinero> montos) {
    var total = 0;
    for (final m in montos) {
      total += m.centimos;
    }
    return Dinero.enCentimos(total);
  }
}
