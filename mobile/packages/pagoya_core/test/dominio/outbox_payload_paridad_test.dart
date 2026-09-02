// PagoYa Móvil — test/dominio/outbox_payload_paridad_test.dart
//
// PARIDAD del payload del outbox.
//
// Es el test que impide el fallo más caro y más silencioso del sistema: que el
// móvil emita `camelCase` y la PC, que deserializa con las opciones por defecto
// de System.Text.Json (CASE-SENSITIVE), construya una venta con todos los
// campos en su valor por omisión — es decir, una venta de S/ 0 que además pisa
// la buena por last-write-wins.

library;

import 'package:pagoya_core/datos/outbox.dart';
import 'package:pagoya_core/dominio/dinero.dart';
import 'package:pagoya_core/dominio/enums.dart';
import 'package:pagoya_core/dominio/tiempo.dart';
import 'package:pagoya_core/dominio/venta.dart';
import 'package:test/test.dart';

import '../ayuda/fixtures_paridad.dart';

void main() {
  final fixture = leerFixture('outbox_payload_venta.json');
  final entrada = fixture['entrada'] as Map<String, Object?>;

  Venta construirVenta() {
    final creado = DateTime.parse(entrada['creado_utc'] as String);
    final actualizado = DateTime.parse(entrada['actualizado_utc'] as String);

    return Venta(
      id: entrada['id'] as String,
      numero: entrada['numero'] as String,
      cajaId: entrada['caja_id'] as String,
      fechaHora: DateTime.parse(entrada['fecha_hora_local'] as String),
      metodoPago: MetodoPago.desde((entrada['metodo_pago'] as num).toInt()),
      estado: EstadoVenta.desde((entrada['estado'] as num).toInt()),
      subTotal: Dinero.deSoles(entrada['sub_total'] as num),
      igv: Dinero.deSoles(entrada['igv'] as num),
      total: Dinero.deSoles(entrada['total'] as num),
      montoRecibido: Dinero.deSoles(entrada['monto_recibido'] as num),
      comprobanteId: entrada['comprobante_id'] as String?,
      origenCajaId: entrada['origen_caja_id'] as String,
      creadoUtc: creado,
      actualizadoUtc: actualizado,
      detalles: (entrada['detalles'] as List)
          .cast<Map<String, Object?>>()
          .map((d) => DetalleVenta(
                id: d['id'] as String,
                ventaId: entrada['id'] as String,
                productoId: d['producto_id'] as String,
                descripcionProducto: d['descripcion_producto'] as String,
                cantidad: (d['cantidad'] as num).toDouble(),
                precioUnitario: Dinero.deSoles(d['precio_unitario'] as num),
                descuento: Dinero.deSoles(d['descuento'] as num),
                importe: Dinero.deSoles(d['importe'] as num),
                origenCajaId: entrada['origen_caja_id'] as String,
                creadoUtc: creado,
                actualizadoUtc: actualizado,
              ))
          .toList(),
    );
  }

  group('payload de venta', () {
    test('coincide con el fixture compartido', () {
      final real = construirVenta().aJson();
      final esperado = fixture['payload_esperado'];

      final dif = diferenciaJson(esperado, real);
      expect(dif, isNull, reason: 'Divergencia con el escritorio -> $dif');
    });

    test('las claves de primer nivel están en PascalCase', () {
      final json = construirVenta().aJson();
      for (final k in json.keys) {
        expect(k.substring(0, 1), k.substring(0, 1).toUpperCase(),
            reason: 'La clave "$k" no está en PascalCase: '
                'System.Text.Json no la reconocería al deserializar.');
      }
    });

    test('las claves de los detalles también', () {
      final det = (construirVenta().aJson()['Detalles'] as List).first as Map;
      for (final k in det.keys) {
        final s = k.toString();
        expect(s.substring(0, 1), s.substring(0, 1).toUpperCase());
      }
    });

    test('los enums viajan como número, no como texto', () {
      final json = construirVenta().aJson();
      expect(json['MetodoPago'], isA<int>());
      expect(json['Estado'], isA<int>());
    });

    test('ida y vuelta: lo que emitimos, lo sabemos leer', () {
      final original = construirVenta();
      final vuelta = Venta.desdeJson(original.aJson());

      expect(vuelta.id, original.id);
      expect(vuelta.numero, original.numero);
      expect(vuelta.total, original.total);
      expect(vuelta.subTotal, original.subTotal);
      expect(vuelta.igv, original.igv);
      expect(vuelta.metodoPago, original.metodoPago);
      expect(vuelta.montoRecibido, original.montoRecibido);
      expect(vuelta.detalles.length, original.detalles.length);
      expect(vuelta.detalles.first.importe, original.detalles.first.importe);
      expect(vuelta.fechaHora.toUtc(), original.fechaHora.toUtc());
    });

    test('los importes del fixture cuadran entre sí', () {
      final v = construirVenta();
      final sumaLineas = Dinero.sumar(v.detalles.map((d) => d.importe));
      expect(sumaLineas, v.total);
      expect(v.subTotal + v.igv, v.total);
    });
  });

  group('payloads con claves en minúsculas (tipos anónimos de C#)', () {
    test('la anulación de venta usa {id, estado}', () {
      final esperado = (fixture['anulacion'] as Map)['payload_esperado'] as Map;
      // Es la forma que construye VentaRepositorio.anular.
      final real = {
        'id': entrada['id'],
        'estado': EstadoVenta.anulada.valor,
      };
      expect(diferenciaJson(esperado, real), isNull);
      expect((fixture['anulacion'] as Map)['operacion'], OperacionesSync.update);
    });

    test('la baja de producto usa {id}', () {
      final baja = fixture['baja_producto'] as Map;
      final esperado = baja['payload_esperado'] as Map;
      final real = {'id': esperado['id']};
      expect(diferenciaJson(esperado, real), isNull);
      expect(baja['operacion'], OperacionesSync.delete);
    });
  });

  group('catálogo cerrado de entidades', () {
    test('el móvil usa exactamente los diez nombres acordados', () {
      final cat = fixture['catalogo_entidades'] as Map<String, Object?>;
      final esperadas = (cat['valores'] as List).cast<String>();
      expect(EntidadesSync.todas, esperadas);
    });

    test('se conoce cuáles aplica hoy el escritorio', () {
      final cat = fixture['catalogo_entidades'] as Map<String, Object?>;
      final pc = (cat['aplicadas_hoy_por_el_escritorio'] as List).cast<String>();
      expect(EntidadesSync.aplicadasPorEscritorio, pc.toSet());
    });

    test('un nombre fuera del catálogo se detecta', () {
      expect(EntidadesSync.esConocida('venta'), isTrue);
      expect(EntidadesSync.esConocida('estadia_habitacion'), isTrue);
      expect(EntidadesSync.esConocida('consumo_habitacion'), isFalse);
      expect(EntidadesSync.esConocida('proveedor'), isFalse);
    });
  });

  group('formato de fechas compatible con DateTime.ToString("o")', () {
    test('UTC lleva 7 dígitos de fracción y sufijo Z', () {
      final t = DateTime.utc(2026, 9, 2, 19, 30, 5, 123, 456);
      expect(TiempoUtc.formatoO(t), '2026-09-02T19:30:05.1234560Z');
    });

    test('rellena con ceros cuando no hay fracción', () {
      final t = DateTime.utc(2026, 1, 5, 8, 4, 3);
      expect(TiempoUtc.formatoO(t), '2026-01-05T08:04:03.0000000Z');
    });

    test('la longitud fija hace correcta la comparación lexicográfica del LWW',
        () {
      // El SQL del last-write-wins compara TEXTO:
      //   WHERE excluded.updated_utc > productos.updated_utc
      // Con longitud variable, ".123456Z" > ".1234560Z" daría un orden falso.
      final antes = TiempoUtc.formatoO(DateTime.utc(2026, 9, 2, 19, 30, 5, 123));
      final despues =
          TiempoUtc.formatoO(DateTime.utc(2026, 9, 2, 19, 30, 5, 124));
      expect(antes.length, despues.length);
      expect(antes.compareTo(despues), lessThan(0));
    });

    test('una fecha local lleva su desfase horario', () {
      final texto = TiempoUtc.formatoOLocal(DateTime(2026, 9, 2, 14, 30, 5));
      // No se fija el desfase (depende de la máquina), pero sí el formato.
      expect(texto, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}[+-]\d{2}:\d{2}$'));
      // Y tiene que volver a parsearse al mismo instante.
      expect(DateTime.parse(texto), DateTime(2026, 9, 2, 14, 30, 5));
    });

    test('parsear tolera nulo y basura sin lanzar', () {
      expect(TiempoUtc.parsear(null), isNull);
      expect(TiempoUtc.parsear('   '), isNull);
      expect(TiempoUtc.parsear('no es fecha'), isNull);
      expect(TiempoUtc.parsearUtc(null).millisecondsSinceEpoch, 0);
    });
  });
}
