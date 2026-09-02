// PagoYa Móvil — test/dominio/dinero_test.dart
//
// La clase que evita que el ticket del celular difiera del de la PC. Estos
// tests no dependen de la BD ni de fixtures: son la red de seguridad de la
// aritmética.

library;

import 'package:pagoya_core/dominio/dinero.dart';
import 'package:test/test.dart';

void main() {
  group('divRedondeadoMitadPar (equivalente a MidpointRounding.ToEven)', () {
    test('redondea hacia el par en los empates', () {
      // 5/2 = 2.5 -> 2 (par);  7/2 = 3.5 -> 4 (par)
      expect(divRedondeadoMitadPar(5, 2), 2);
      expect(divRedondeadoMitadPar(7, 2), 4);
      expect(divRedondeadoMitadPar(1, 2), 0);
      expect(divRedondeadoMitadPar(3, 2), 2);
    });

    test('fuera de los empates redondea al más cercano', () {
      expect(divRedondeadoMitadPar(4, 3), 1); // 1.333
      expect(divRedondeadoMitadPar(5, 3), 2); // 1.666
    });

    test('es simétrico con negativos', () {
      expect(divRedondeadoMitadPar(-5, 2), -2);
      expect(divRedondeadoMitadPar(-7, 2), -4);
      expect(divRedondeadoMitadPar(-5, 3), -2);
    });

    test('rechaza denominador cero', () {
      expect(() => divRedondeadoMitadPar(1, 0), throwsArgumentError);
    });
  });

  group('construcción', () {
    test('desde soles enteros es exacta', () {
      expect(Dinero.deSoles(3).centimos, 300);
      expect(Dinero.deSoles(0).centimos, 0);
    });

    test('desde soles con decimales absorbe el error binario del double', () {
      // 0.29 * 100 en binario es 28.999999999999996; sin corrección daría 28.
      expect(Dinero.deSoles(0.29).centimos, 29);
      expect(Dinero.deSoles(3.50).centimos, 350);
      expect(Dinero.deSoles(9.90).centimos, 990);
      expect(Dinero.deSoles(5.80).centimos, 580);
      expect(Dinero.deSoles(0.30).centimos, 30);
    });

    test('desdeDb tolera null como cero, y desdeDbNulable lo conserva', () {
      expect(Dinero.desdeDb(null), Dinero.cero);
      expect(Dinero.desdeDbNulable(null), isNull);
      expect(Dinero.desdeDbNulable(12.7)!.centimos, 1270);
    });
  });

  group('ida y vuelta con la columna REAL de SQLite', () {
    test('todo céntimo del rango de un POS sobrevive el viaje', () {
      for (var c = 0; c <= 200000; c += 7) {
        final d = Dinero.enCentimos(c);
        expect(Dinero.desdeDb(d.aDb()).centimos, c,
            reason: 'se perdió precisión en $c céntimos');
      }
    });

    test('también con importes negativos (diferencias de arqueo)', () {
      for (var c = -50000; c <= 0; c += 13) {
        final d = Dinero.enCentimos(c);
        expect(Dinero.desdeDb(d.aDb()).centimos, c);
      }
    });
  });

  group('aritmética', () {
    test('suma y resta son exactas donde el double falla', () {
      // 0.1 + 0.2 == 0.30000000000000004 en double; aquí es 0.30 clavado.
      final r = Dinero.deSoles(0.10) + Dinero.deSoles(0.20);
      expect(r.centimos, 30);
      expect(r.aDb(), 0.30);
    });

    test('acumular céntimos mil veces no deriva', () {
      var acc = Dinero.cero;
      for (var i = 0; i < 1000; i++) {
        acc = acc + Dinero.deSoles(0.01);
      }
      expect(acc.centimos, 1000);
      expect(acc.formatear(), '10.00');
    });

    test('multiplicación por cantidad entera es exacta (carrito del POS)', () {
      expect((Dinero.deSoles(3.50) * 3).centimos, 1050);
      expect((Dinero.deSoles(0.30) * 5).centimos, 150);
      expect((Dinero.deSoles(0.01) * 0).centimos, 0);
    });

    test('porCantidad con decimales redondea al par', () {
      // 2.5 kg a 1.11 -> 2.775 -> 2.78 (sube al par)
      expect(Dinero.deSoles(1.11).porCantidad(2.5).centimos, 278);
      // 1.5 kg a 1.15 -> 1.725 -> 1.72 (baja al par)
      expect(Dinero.deSoles(1.15).porCantidad(1.5).centimos, 172);
    });

    test('porcentaje usa enteros y respeta el empate bancario', () {
      // 3.55 al 50 % -> 1.775 -> 1.78. Con double daría 1.77.
      expect(Dinero.deSoles(3.55).porcentaje(5000).centimos, 178);
      // 3.45 al 50 % -> 1.725 -> 1.72.
      expect(Dinero.deSoles(3.45).porcentaje(5000).centimos, 172);
    });

    test('sumar una colección', () {
      final total = Dinero.sumar([
        Dinero.deSoles(3.50) * 2,
        Dinero.deSoles(0.30) * 5,
        Dinero.deSoles(4.20),
      ]);
      expect(total.centimos, 1270);
    });
  });

  group('comparación e igualdad', () {
    test('dos importes con los mismos céntimos son iguales', () {
      expect(Dinero.deSoles(1.50), Dinero.enCentimos(150));
      expect(Dinero.deSoles(1.50).hashCode, Dinero.enCentimos(150).hashCode);
    });

    test('operadores relacionales', () {
      final a = Dinero.deSoles(1.00);
      final b = Dinero.deSoles(2.00);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= Dinero.deSoles(1.00), isTrue);
      expect(a >= Dinero.deSoles(1.00), isTrue);
      expect(a.compareTo(b), lessThan(0));
    });
  });

  group('formato', () {
    test('siempre dos decimales', () {
      expect(Dinero.cero.formatear(), '0.00');
      expect(Dinero.enCentimos(5).formatear(), '0.05');
      expect(Dinero.enCentimos(50).formatear(), '0.50');
      expect(Dinero.enCentimos(1270).formatear(), '12.70');
      expect(Dinero.enCentimos(100000).formatear(), '1000.00');
    });

    test('negativos llevan el signo delante', () {
      expect(Dinero.enCentimos(-1270).formatear(), '-12.70');
      expect(Dinero.enCentimos(-5).formatear(), '-0.05');
    });

    test('con símbolo para el ticket', () {
      expect(Dinero.enCentimos(1270).formatearConSimbolo(), 'S/ 12.70');
    });
  });
}
