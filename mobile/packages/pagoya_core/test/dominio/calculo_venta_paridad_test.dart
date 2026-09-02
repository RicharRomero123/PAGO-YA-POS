// PagoYa Móvil — test/dominio/calculo_venta_paridad_test.dart
//
// PARIDAD con el escritorio: IGV, totales y vuelto.
//
// Consume los fixtures compartidos de `tests/fixtures/paridad/`, los mismos que
// debe consumir el lado C#. Si uno de estos falla, el que se adapta es el
// móvil (docs/MOBILE-ARQUITECTURA.md §8).

library;

import 'package:pagoya_core/dominio/calculo_venta.dart';
import 'package:pagoya_core/dominio/dinero.dart';
import 'package:pagoya_core/dominio/enums.dart';
import 'package:test/test.dart';

import '../ayuda/fixtures_paridad.dart';

void main() {
  group('IGV y totales (fixture igv_totales.json)', () {
    final fixture = leerFixture('igv_totales.json');

    test('la tasa del fixture es la que implementa el móvil', () {
      final tasa = (fixture['formula'] as Map)['tasa_igv'] as num;
      expect(CalculoVenta.tasaIgvMilesimas / 1000, tasa,
          reason: 'La tasa de IGV divergió del contrato compartido.');
    });

    for (final caso in casosDe(fixture)) {
      final nombre = caso['nombre'] as String;
      test('desagregar: $nombre', () {
        final total = Dinero.deSoles(caso['total'] as num);
        final r = CalculoVenta.desagregar(total);

        expect(r.subTotal, Dinero.deSoles(caso['sub_total'] as num),
            reason: 'sub_total de "$nombre"');
        expect(r.igv, Dinero.deSoles(caso['igv'] as num),
            reason: 'igv de "$nombre"');
        // La invariante que hace que el ticket cuadre al céntimo.
        expect(r.subTotal + r.igv, total,
            reason: 'sub_total + igv debe dar exactamente el total');
      });
    }

    for (final carrito in casosDe(fixture, 'carritos')) {
      final nombre = carrito['nombre'] as String;
      test('carrito completo: $nombre', () {
        final lineas = (carrito['lineas'] as List)
            .cast<Map<String, Object?>>()
            .map((l) => LineaCobro(
                  productoId: '',
                  nombre: l['nombre'] as String,
                  precioUnitario: Dinero.deSoles(l['precio_unitario'] as num),
                  cantidad: (l['cantidad'] as num).toInt(),
                ))
            .toList();

        // Cada importe de línea, antes de sumar.
        for (var i = 0; i < lineas.length; i++) {
          final esperado =
              (carrito['lineas'] as List)[i] as Map<String, Object?>;
          expect(lineas[i].importe, Dinero.deSoles(esperado['importe'] as num),
              reason: 'importe de la línea ${esperado['nombre']}');
        }

        final t = CalculoVenta.calcular(lineas);
        expect(t.total, Dinero.deSoles(carrito['total'] as num));
        expect(t.subTotal, Dinero.deSoles(carrito['sub_total'] as num));
        expect(t.igv, Dinero.deSoles(carrito['igv'] as num));
        expect(t.cantidadItems, (carrito['cantidad_items'] as num).toInt());
        expect(t.cuadra, isTrue);
      });
    }

    test('carrito vacío da todo en cero', () {
      final t = CalculoVenta.calcular(const <LineaCobro>[]);
      expect(t.total, Dinero.cero);
      expect(t.subTotal, Dinero.cero);
      expect(t.igv, Dinero.cero);
      expect(t.cantidadItems, 0);
    });

    test('la invariante sub + igv == total se cumple para todo céntimo', () {
      // Barrido exhaustivo hasta S/ 1000: si alguna vez no cuadra, el ticket
      // impreso mostraría un desglose que no suma el total cobrado.
      for (var c = 0; c <= 100000; c++) {
        final total = Dinero.enCentimos(c);
        final r = CalculoVenta.desagregar(total);
        expect(r.subTotal.centimos + r.igv.centimos, c,
            reason: 'no cuadra en $c céntimos');
      }
    });
  });

  group('Vuelto (fixture vuelto.json)', () {
    final fixture = leerFixture('vuelto.json');

    for (final caso in casosDe(fixture)) {
      final nombre = caso['nombre'] as String;
      test(nombre, () {
        final pagaCon = Dinero.deSoles(caso['paga_con'] as num);
        final total = Dinero.deSoles(caso['total'] as num);

        expect(
          CalculoVenta.vuelto(pagaCon: pagaCon, total: total),
          Dinero.deSoles(caso['vuelto'] as num),
          reason: 'vuelto de "$nombre"',
        );
        expect(
          CalculoVenta.faltaEfectivo(pagaCon: pagaCon, total: total),
          caso['falta_efectivo'] as bool,
          reason: 'aviso de "$nombre"',
        );
      });
    }

    test('el vuelto nunca es negativo', () {
      for (var t = 0; t <= 5000; t += 37) {
        for (var p = 0; p <= 5000; p += 53) {
          final v = CalculoVenta.vuelto(
            pagaCon: Dinero.enCentimos(p),
            total: Dinero.enCentimos(t),
          );
          expect(v.esNegativo, isFalse);
        }
      }
    });

    group('parseo del monto del numpad', () {
      final parseo = fixture['parseo_monto'] as Map<String, Object?>;
      for (final caso in casosDe(parseo)) {
        final texto = caso['texto'] as String;
        test('"$texto"', () {
          expect(
            CalculoVenta.parsearMonto(texto),
            Dinero.deSoles(caso['valor'] as num),
          );
        });
      }

      test('null se lee como cero (nunca lanza)', () {
        expect(CalculoVenta.parsearMonto(null), Dinero.cero);
      });
    });
  });

  group('Arqueo de caja', () {
    test('solo el efectivo entra al arqueo; el fondo no se cuenta dos veces', () {
      final arqueo = ArqueoCaja.desdeMovimientos(
        montoApertura: Dinero.deSoles(50.00),
        movimientos: [
          // El movimiento de apertura existe en la tabla pero NO debe sumarse:
          // ya está representado por montoApertura.
          (tipo: TipoMovimientoCaja.aperturaFondo, monto: Dinero.deSoles(50.00)),
          (tipo: TipoMovimientoCaja.ingreso, monto: Dinero.deSoles(12.70)),
          (tipo: TipoMovimientoCaja.ingreso, monto: Dinero.deSoles(22.00)),
          (tipo: TipoMovimientoCaja.egreso, monto: Dinero.deSoles(15.00)),
          (tipo: TipoMovimientoCaja.retiro, monto: Dinero.deSoles(20.00)),
        ],
      );

      expect(arqueo.ingresos, Dinero.deSoles(34.70));
      expect(arqueo.egresos, Dinero.deSoles(35.00));
      expect(arqueo.esperado, Dinero.deSoles(49.70));
    });

    test('la diferencia distingue sobrante de faltante', () {
      const arqueo = ArqueoCaja(
        montoApertura: Dinero.enCentimos(5000),
        ingresos: Dinero.enCentimos(3470),
        egresos: Dinero.enCentimos(3500),
      );
      expect(arqueo.esperado, Dinero.enCentimos(4970));
      // Contó de más: sobrante positivo.
      expect(arqueo.diferencia(Dinero.deSoles(50.00)), Dinero.enCentimos(30));
      // Contó de menos: faltante negativo.
      expect(arqueo.diferencia(Dinero.deSoles(49.00)), Dinero.enCentimos(-70));
      // Cuadró exacto.
      expect(arqueo.diferencia(Dinero.enCentimos(4970)), Dinero.cero);
    });
  });
}
