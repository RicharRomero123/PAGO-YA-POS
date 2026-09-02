// PagoYa Móvil — test/dominio/producto_descuento_paridad_test.dart
//
// PARIDAD del precio efectivo con descuento (Producto.PrecioFinal en C#).
// Es el cálculo donde el redondeo bancario sí produce empates reales, así que
// es el que mejor detecta si alguien reintrodujo `double` en el camino.

library;

import 'package:pagoya_core/dominio/dinero.dart';
import 'package:pagoya_core/dominio/enums.dart';
import 'package:pagoya_core/dominio/producto.dart';
import 'package:test/test.dart';

import '../ayuda/fixtures_paridad.dart';

void main() {
  group('precio final con descuento (fixture precio_final_producto.json)', () {
    final fixture = leerFixture('precio_final_producto.json');

    test('los códigos de TipoDescuento coinciden con el contrato', () {
      final tipos = fixture['tipos_descuento'] as Map<String, Object?>;
      expect(TipoDescuento.ninguno.valor, tipos['ninguno']);
      expect(TipoDescuento.porcentaje.valor, tipos['porcentaje']);
      expect(TipoDescuento.oferta.valor, tipos['oferta']);
    });

    for (final caso in casosDe(fixture)) {
      final nombre = caso['nombre'] as String;
      test(nombre, () {
        final p = Producto(
          nombre: 'Prueba',
          precioVenta: Dinero.deSoles(caso['precio_venta'] as num),
          tipoDescuento:
              TipoDescuento.desde((caso['tipo_descuento'] as num).toInt()),
          descuentoValor: Dinero.deSoles(caso['descuento_valor'] as num),
        );

        expect(p.precioFinal, Dinero.deSoles(caso['precio_final'] as num),
            reason: 'precio_final de "$nombre"');
        expect(p.tieneDescuento, caso['tiene_descuento'] as bool,
            reason: 'tiene_descuento de "$nombre"');
        expect(p.porcentajeDescuento,
            (caso['porcentaje_descuento'] as num).toInt(),
            reason: 'porcentaje_descuento de "$nombre"');
      });
    }

    test('el precio final nunca supera al normal ni baja de cero', () {
      // Barrido sobre precios y porcentajes: la invariante del contrato es que
      // PrecioFinal está siempre en [0, PrecioVenta].
      for (var precio = 5; precio <= 20000; precio += 137) {
        for (var pct = -500; pct <= 12000; pct += 311) {
          final p = Producto(
            precioVenta: Dinero.enCentimos(precio),
            tipoDescuento: TipoDescuento.porcentaje,
            descuentoValor: Dinero.enCentimos(pct),
          );
          expect(p.precioFinal.centimos, inInclusiveRange(0, precio),
              reason: 'precio $precio con $pct centésimas de punto');
        }
      }
    });
  });

  group('estado de vencimiento (rubro farmacia)', () {
    final hoy = DateTime(2026, 9, 2);

    test('sin fecha no hay estado', () {
      final p = Producto(nombre: 'Clavos');
      expect(p.diasParaVencer(hoy), isNull);
      expect(p.estaVencido(hoy), isFalse);
      expect(p.porVencer(hoy: hoy), isFalse);
    });

    test('vencido ayer', () {
      final p = Producto(fechaVencimiento: DateTime(2026, 9, 1));
      expect(p.diasParaVencer(hoy), -1);
      expect(p.estaVencido(hoy), isTrue);
      expect(p.porVencer(hoy: hoy), isFalse);
    });

    test('vence hoy: aún NO está vencido', () {
      final p = Producto(fechaVencimiento: DateTime(2026, 9, 2));
      expect(p.diasParaVencer(hoy), 0);
      expect(p.estaVencido(hoy), isFalse);
      expect(p.porVencer(hoy: hoy), isTrue);
    });

    test('el umbral por defecto son 30 días', () {
      final dentro = Producto(fechaVencimiento: DateTime(2026, 10, 1));
      final fuera = Producto(fechaVencimiento: DateTime(2026, 10, 3));
      expect(dentro.porVencer(hoy: hoy), isTrue); // 29 días
      expect(fuera.porVencer(hoy: hoy), isFalse); // 31 días
    });

    test('compara solo la parte de fecha, no la hora', () {
      final p = Producto(fechaVencimiento: DateTime(2026, 9, 2, 23, 59));
      expect(p.diasParaVencer(DateTime(2026, 9, 2, 0, 1)), 0);
    });
  });

  group('stock bajo', () {
    test('solo avisa si controla stock y el umbral está definido', () {
      expect(
        Producto(controlaStock: true, stockMinimo: 10, stockActual: 10).stockBajo,
        isTrue,
      );
      expect(
        Producto(controlaStock: true, stockMinimo: 10, stockActual: 11).stockBajo,
        isFalse,
      );
      // Umbral 0 = sin aviso, aunque el stock esté en cero.
      expect(
        Producto(controlaStock: true, stockMinimo: 0, stockActual: 0).stockBajo,
        isFalse,
      );
      // Un servicio no controla stock: nunca avisa.
      expect(
        Producto(controlaStock: false, stockMinimo: 10, stockActual: 0).stockBajo,
        isFalse,
      );
    });
  });
}
