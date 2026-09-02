// PagoYa Móvil — test/rubros/plantillas_rubro_test.dart
//
// Verifica el PORT de `PlantillasRubro.cs`. Lo que se protege aquí:
//
//   * las CLAVES de rubro (las guarda `meta.rubro` y las lee el escritorio);
//   * los CÓDIGOS de producto: si el usuario tiene PagoYa en la PC y en el
//     celular, el mismo producto sembrado debe llevar el mismo código, o al
//     sincronizar el índice único `ix_productos_codigo` rechaza la fila;
//   * la regla `esRubroComida`, que decide si aparece el módulo de Mesas.

library;

import 'package:pagoya_core/dominio/dinero.dart';
import 'package:pagoya_core/dominio/enums.dart';
import 'package:pagoya_core/rubros/plantillas_rubro.dart';
import 'package:test/test.dart';

void main() {
  // Las nueve claves del contrato (docs/MOBILE-ARQUITECTURA.md §7).
  const clavesEsperadas = [
    'bodega',
    'restaurante',
    'cafeteria',
    'polleria',
    'farmacia',
    'ferreteria',
    'licoreria',
    'hotel',
    'otro',
  ];

  group('catálogo de rubros', () {
    test('son exactamente las nueve claves del escritorio, en orden', () {
      expect(PlantillasRubro.todos.map((r) => r.clave).toList(),
          clavesEsperadas);
    });

    test('cada clave del enum RubroNegocio tiene su plantilla', () {
      for (final r in RubroNegocio.values) {
        expect(clavesEsperadas, contains(r.clave),
            reason: 'RubroNegocio.${r.name} no tiene plantilla');
      }
    });

    test('info() cae a bodega si la clave no existe', () {
      expect(PlantillasRubro.info('inexistente').clave, 'bodega');
      expect(PlantillasRubro.info('hotel').clave, 'hotel');
    });

    test('los rubros con PNG propio son los mismos que en el escritorio', () {
      final conImagen = PlantillasRubro.todos
          .where((r) => r.tieneImagen)
          .map((r) => r.clave)
          .toList();
      expect(conImagen,
          ['bodega', 'restaurante', 'farmacia', 'ferreteria', 'hotel']);
    });

    test('deRubro mapea los rubros de comida al icono de restaurante', () {
      expect(IconosRubro.deRubro('cafeteria'), IconosRubro.restaurante);
      expect(IconosRubro.deRubro('polleria'), IconosRubro.restaurante);
      expect(IconosRubro.deRubro('licoreria'), IconosRubro.bodega);
      expect(IconosRubro.deRubro(null), IconosRubro.bodega);
    });
  });

  group('esRubroComida', () {
    test('solo restaurante, pollería y cafetería', () {
      expect(PlantillasRubro.esRubroComida('restaurante'), isTrue);
      expect(PlantillasRubro.esRubroComida('polleria'), isTrue);
      expect(PlantillasRubro.esRubroComida('cafeteria'), isTrue);

      expect(PlantillasRubro.esRubroComida('bodega'), isFalse);
      expect(PlantillasRubro.esRubroComida('hotel'), isFalse);
      expect(PlantillasRubro.esRubroComida('farmacia'), isFalse);
      expect(PlantillasRubro.esRubroComida('ferreteria'), isFalse);
      expect(PlantillasRubro.esRubroComida('licoreria'), isFalse);
      expect(PlantillasRubro.esRubroComida('otro'), isFalse);
    });

    test('es insensible a mayúsculas y tolera null', () {
      expect(PlantillasRubro.esRubroComida('RESTAURANTE'), isTrue);
      expect(PlantillasRubro.esRubroComida(null), isFalse);
      expect(PlantillasRubro.esRubroComida(''), isFalse);
    });
  });

  group('pie de ticket', () {
    test('texto exacto por rubro', () {
      expect(PlantillasRubro.pieTicket('restaurante'),
          '¡Gracias por su preferencia! Vuelva pronto.');
      expect(PlantillasRubro.pieTicket('polleria'),
          '¡Gracias por su preferencia! Vuelva pronto.');
      expect(PlantillasRubro.pieTicket('cafeteria'),
          '¡Gracias por su preferencia! Vuelva pronto.');
      expect(PlantillasRubro.pieTicket('hotel'),
          'Gracias por hospedarse con nosotros.');
      expect(PlantillasRubro.pieTicket('farmacia'), 'Cuidamos tu salud. ¡Gracias!');
      expect(PlantillasRubro.pieTicket('bodega'), '¡Gracias por su compra!');
      expect(PlantillasRubro.pieTicket('otro'), '¡Gracias por su compra!');
    });
  });

  group('productos de plantilla', () {
    test('"otro" arranca con el catálogo vacío', () {
      expect(PlantillasRubro.productos('otro'), isEmpty);
    });

    test('una clave desconocida cae a la plantilla de bodega', () {
      expect(PlantillasRubro.productos('marciano').map((p) => p.codigo),
          PlantillasRubro.productos('bodega').map((p) => p.codigo));
    });

    test('los códigos son únicos dentro de cada rubro', () {
      for (final clave in clavesEsperadas) {
        final codigos = PlantillasRubro.productos(clave).map((p) => p.codigo);
        expect(codigos.toSet().length, codigos.length,
            reason: 'códigos repetidos en "$clave": el índice único '
                'ix_productos_codigo rechazaría la siembra');
      }
    });

    test('conteos por rubro (mismos que el escritorio)', () {
      expect(PlantillasRubro.productos('bodega').length, 11);
      expect(PlantillasRubro.productos('restaurante').length, 11);
      expect(PlantillasRubro.productos('cafeteria').length, 10);
      expect(PlantillasRubro.productos('polleria').length, 10);
      expect(PlantillasRubro.productos('farmacia').length, 20);
      expect(PlantillasRubro.productos('ferreteria').length, 21);
      expect(PlantillasRubro.productos('licoreria').length, 10);
      expect(PlantillasRubro.productos('hotel').length, 6);
    });

    test('precios de referencia sin error de redondeo', () {
      final bodega = PlantillasRubro.productos('bodega');
      final pan = bodega.firstWhere((p) => p.codigo == '7506001');
      expect(pan.nombre, 'Pan francés (und)');
      expect(pan.precio, Dinero.enCentimos(30));
      expect(pan.stock, 200);

      final aceite = bodega.firstWhere((p) => p.codigo == '7502002');
      expect(aceite.precio, Dinero.enCentimos(990)); // 9.90, no 9.89

      final arroz = bodega.firstWhere((p) => p.codigo == '7502001');
      expect(arroz.precio, Dinero.enCentimos(580)); // 5.80
    });

    test('las habitaciones NO son productos del rubro hotel', () {
      final cats =
          PlantillasRubro.productos('hotel').map((p) => p.categoria).toSet();
      expect(cats, isNot(contains('Habitaciones')));
      expect(cats, containsAll(['Minibar', 'Servicios', 'Restaurante']));
    });
  });

  group('campos farmacéuticos', () {
    final farmacia = PlantillasRubro.productos('farmacia');

    test('los antibióticos exigen receta', () {
      final amoxi = farmacia.firstWhere((p) => p.codigo == 'FAR-005');
      expect(amoxi.requiereReceta, isTrue);
      expect(amoxi.principioActivo, 'Amoxicilina');
      expect(amoxi.registroSanitario, 'EG-05678');
      expect(amoxi.stockMinimo, 8);
    });

    test('los que no son medicamento no exigen receta ni llevan DCI', () {
      final curitas = farmacia.firstWhere((p) => p.codigo == 'FAR-014');
      expect(curitas.requiereReceta, isFalse);
      expect(curitas.principioActivo, isNull);
      expect(curitas.mesesVence, 0);
      expect(curitas.fechaVencimiento(DateTime(2026, 9, 2)), isNull);
    });

    test('mesesVence se proyecta desde hoy', () {
      final hoy = DateTime(2026, 9, 2);
      final naproxeno = farmacia.firstWhere((p) => p.codigo == 'FAR-003');
      expect(naproxeno.mesesVence, 2);
      expect(naproxeno.fechaVencimiento(hoy), DateTime(2026, 11, 2));
    });

    test('mesesVence cruza el fin de año sin romperse', () {
      final hoy = DateTime(2026, 11, 15);
      final paracetamol = farmacia.firstWhere((p) => p.codigo == 'FAR-001');
      expect(paracetamol.mesesVence, 18);
      expect(paracetamol.fechaVencimiento(hoy), DateTime(2028, 5, 15));
    });

    test('recorta el día al último del mes destino, como AddMonths de .NET', () {
      // 31-ene + 1 mes: .NET da 28-feb (recorta); Dart, sin corrección, daría
      // 3-mar (desborda). Si divergen, el mismo lote vencería en meses
      // distintos en la PC y en el celular.
      final unMes = PlantillasRubro.productos('farmacia')
          .firstWhere((p) => p.mesesVence == 12);
      expect(unMes.fechaVencimiento(DateTime(2026, 1, 31)),
          DateTime(2027, 1, 31));

      final dosMeses = PlantillasRubro.productos('farmacia')
          .firstWhere((p) => p.mesesVence == 1);
      expect(dosMeses.fechaVencimiento(DateTime(2027, 1, 31)),
          DateTime(2027, 2, 28));
      // Año bisiesto: 2028 sí tiene 29 de febrero.
      expect(dosMeses.fechaVencimiento(DateTime(2028, 1, 31)),
          DateTime(2028, 2, 29));
      expect(dosMeses.fechaVencimiento(DateTime(2026, 12, 15)),
          DateTime(2027, 1, 15));
    });

    test('hay al menos un producto "por vencer" para poblar el módulo', () {
      final hoy = DateTime(2026, 9, 2);
      final proximos = farmacia.where((p) {
        final f = p.fechaVencimiento(hoy);
        return f != null && f.difference(hoy).inDays <= 62;
      });
      expect(proximos, isNotEmpty);
    });
  });

  group('personalización (rubro comida)', () {
    test('el ceviche trae tamaño obligatorio, agregados y notas', () {
      final ceviche = PlantillasRubro.productos('restaurante')
          .firstWhere((p) => p.codigo == 'PLT-001');
      final pers = ceviche.personalizacion!;

      expect(pers.permiteNota, isTrue);
      expect(pers.grupos.length, 3);

      final tamano = pers.grupos[0];
      expect(tamano.nombre, 'Presentación');
      expect(tamano.obligatorio, isTrue);
      expect(tamano.multiple, isFalse);
      expect(tamano.opciones.first.precioExtra, Dinero.cero);
      expect(tamano.opciones[1].precioExtra, Dinero.deSoles(18));

      final agregados = pers.grupos[1];
      expect(agregados.multiple, isTrue);
      expect(agregados.obligatorio, isFalse);
      expect(agregados.opciones.first.nombre, '+ Chicharrón de pescado');
      expect(agregados.opciones.first.precioExtra, Dinero.deSoles(8));

      final notas = pers.grupos[2];
      expect(notas.opciones.map((o) => o.nombre),
          ['Sin cebolla', 'Más picante', 'Sin ají']);
      expect(notas.opciones.every((o) => o.precioExtra.esCero), isTrue);
    });

    test('un extra con decimales no pierde céntimos', () {
      final incaKola = PlantillasRubro.productos('restaurante')
          .firstWhere((p) => p.codigo == 'PLT-008');
      final litro = incaKola.personalizacion!.grupos.first.opciones[1];
      expect(litro.nombre, '1L');
      expect(litro.precioExtra, Dinero.enCentimos(250)); // 2.50
    });

    test('los productos sin modificadores no tienen personalización', () {
      final papa = PlantillasRubro.productos('restaurante')
          .firstWhere((p) => p.codigo == 'PLT-002');
      expect(papa.personalizacion, isNull);
    });

    test('ningún rubro que no sea de comida trae modificadores', () {
      for (final clave in ['bodega', 'farmacia', 'ferreteria', 'licoreria', 'hotel']) {
        for (final p in PlantillasRubro.productos(clave)) {
          expect(p.personalizacion, isNull,
              reason: '$clave/${p.codigo} no debería tener personalización');
        }
      }
    });
  });

  group('categorías sugeridas', () {
    test('empiezan por las de la plantilla y terminan en General', () {
      final cats = PlantillasRubro.categorias('bodega');
      expect(cats.first, 'Bebidas'); // primera categoría de la plantilla
      expect(cats.last, 'General');
    });

    test('no hay duplicados aunque los refuerzos repitan una categoría', () {
      for (final clave in clavesEsperadas) {
        final cats = PlantillasRubro.categorias(clave);
        expect(cats.toSet().length, cats.length, reason: 'duplicados en $clave');
      }
    });

    test('"otro" no queda sin categorías', () {
      expect(PlantillasRubro.categorias('otro'), ['General']);
    });

    test('el hotel sugiere Habitaciones aunque no sean productos', () {
      expect(PlantillasRubro.categorias('hotel'), contains('Habitaciones'));
    });

    test('la farmacia sugiere las categorías DIGEMID', () {
      expect(PlantillasRubro.categorias('farmacia'),
          containsAll(['Analgésicos', 'Antibióticos', 'Genéricos']));
    });

    test('con null se siembra bodega pero SIN sus refuerzos', () {
      // Rareza portada tal cual del escritorio: `Categorias` usa
      // `Productos(clave ?? "bodega")` para las categorías de la plantilla,
      // pero el switch de refuerzos evalúa `(clave ?? "")`, que con null no
      // hace match con "bodega". Resultado: null NO es equivalente a "bodega".
      // Se replica para no cambiar el comportamiento observable.
      final conNull = PlantillasRubro.categorias(null);
      final conBodega = PlantillasRubro.categorias('bodega');

      expect(conNull, [
        'Bebidas',
        'Abarrotes',
        'Snacks',
        'Golosinas',
        'Limpieza',
        'Panadería',
        'General',
      ]);
      expect(conBodega, containsAll(['Lácteos', 'Cigarros']));
      expect(conNull, isNot(contains('Lácteos')));
    });
  });
}
