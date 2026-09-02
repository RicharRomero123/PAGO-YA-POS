// PagoYa Móvil — test/datos/outbox_transaccional_test.dart
//
// Prueba lo más importante de la capa de datos: que la escritura de negocio y
// su fila de `outbox_sync` viajen SIEMPRE juntas, y que el stock no se pierda
// al aplicar cambios remotos.
//
// REQUISITOS DE DEPENDENCIAS (dueño del pubspec: `mobile-lead`):
//   dev_dependencies: test, drift, sqlite3 (para NativeDatabase.memory()).
//   dependencies:     drift
// Si `dart test` se queja de `package:drift/native.dart`, falta `sqlite3` en
// dev_dependencies — no es un fallo de este código.

library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:pagoya_core/datos/base_datos_drift.dart';
import 'package:pagoya_core/datos/configuracion_dispositivo.dart';
import 'package:pagoya_core/datos/correlativos.dart';
import 'package:pagoya_core/datos/esquema.dart';
import 'package:pagoya_core/datos/outbox.dart';
import 'package:pagoya_core/datos/outbox_store.dart';
import 'package:pagoya_core/datos/repositorios/caja_repositorio.dart';
import 'package:pagoya_core/datos/repositorios/producto_repositorio.dart';
import 'package:pagoya_core/datos/repositorios/venta_repositorio.dart';
import 'package:pagoya_core/dominio/caja.dart';
import 'package:pagoya_core/dominio/dinero.dart';
import 'package:pagoya_core/dominio/enums.dart';
import 'package:pagoya_core/dominio/inventario.dart';
import 'package:pagoya_core/dominio/producto.dart';
import 'package:pagoya_core/dominio/uuid.dart';
import 'package:pagoya_core/dominio/venta.dart';
import 'package:test/test.dart';

void main() {
  late BaseDatosPagoYa db;
  late ConfiguracionDispositivo config;
  late ProductoRepositorio productos;
  late VentaRepositorio ventas;
  late CajaRepositorio cajas;
  late OutboxStore outbox;

  setUp(() async {
    db = BaseDatosPagoYa(NativeDatabase.memory());
    await db.inicializarEsquema();

    config = ConfiguracionDispositivo(db);
    await config.guardarVinculacion(devicePrefix: 'M01', origen: 'movil-01');

    productos = ProductoRepositorio(db, config);
    ventas = VentaRepositorio(db, config);
    cajas = CajaRepositorio(db, config);
    outbox = OutboxStore(db);
  });

  tearDown(() async => db.close());

  Future<List<Map<String, Object?>>> filasOutbox([String? entidad]) => entidad ==
          null
      ? db.consultar('SELECT * FROM outbox_sync ORDER BY created_utc')
      : db.consultar(
          'SELECT * FROM outbox_sync WHERE entidad = ? ORDER BY created_utc',
          [entidad]);

  Future<double> stockDe(String id) async =>
      ((await db.escalar('SELECT stock_actual FROM productos WHERE id = ?', [id]))
              as num)
          .toDouble();

  Future<Caja> abrirCaja() => cajas.abrir(Caja(
        nombre: 'Caja móvil',
        cajero: 'Rosa',
        montoApertura: Dinero.deSoles(50.00),
      ));

  Future<Producto> sembrarProducto({
    String codigo = '7501055',
    String nombre = 'Inca Kola 500ml',
    double stock = 48,
    num precio = 3.50,
    bool controlaStock = true,
  }) async {
    final p = Producto(
      codigo: codigo,
      nombre: nombre,
      precioVenta: Dinero.deSoles(precio),
      stockActual: stock,
      controlaStock: controlaStock,
    );
    await productos.crearConStockInicial(p);
    return p;
  }

  group('esquema', () {
    test('crea todas las tablas del escritorio', () async {
      final filas = await db.consultar(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      final tablas = filas.map((f) => f['name'] as String).toSet();

      expect(
        tablas,
        containsAll([
          'productos',
          'proveedores',
          'caja',
          'movimientos_caja',
          'ventas',
          'detalle_ventas',
          'inventario',
          'comprobantes',
          'habitaciones',
          'estadias_habitacion',
          'consumos_habitacion',
          'mesas',
          'pedidos',
          'pedido_lineas',
          'outbox_sync',
          'usuarios',
          'meta',
        ]),
      );
    });

    test('aplica las migraciones aditivas de descuento', () async {
      final cols = await db.consultar("SELECT name FROM pragma_table_info('productos')");
      final nombres = cols.map((c) => c['name'] as String).toSet();
      expect(nombres, containsAll(['tipo_descuento', 'descuento_valor']));
    });

    test('es idempotente: se puede reinicializar sin romper nada', () async {
      await db.inicializarEsquema();
      await db.inicializarEsquema();
      final v = await db.escalar(
          'SELECT valor FROM meta WHERE clave = ?', [ClavesMeta.versionEsquema]);
      expect(v.toString(), '1');
    });
  });

  group('venta atómica', () {
    test('escribe cabecera, detalle, kardex y outbox en un solo commit',
        () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto();

      final venta = Venta(
        cajaId: caja.id,
        metodoPago: MetodoPago.efectivo,
        subTotal: Dinero.deSoles(2.97),
        igv: Dinero.deSoles(0.53),
        total: Dinero.deSoles(3.50),
        montoRecibido: Dinero.deSoles(5.00),
        detalles: [
          DetalleVenta(
            productoId: p.id,
            descripcionProducto: p.nombre,
            cantidad: 1,
            precioUnitario: Dinero.deSoles(3.50),
            importe: Dinero.deSoles(3.50),
          ),
        ],
      );

      final guardada = await ventas.registrar(venta);

      // Correlativo con prefijo de dispositivo.
      expect(guardada.numero, 'M01-000001');

      // Cabecera y detalle.
      final leida = await ventas.obtenerPorId(guardada.id);
      expect(leida, isNotNull);
      expect(leida!.total, Dinero.deSoles(3.50));
      expect(leida.detalles, hasLength(1));
      expect(leida.origenCajaId, 'movil-01');

      // Stock descontado y kardex escrito.
      expect(await stockDe(p.id), 47);
      final kardex = await productos.kardex(p.id);
      expect(kardex, hasLength(2)); // apertura + venta
      final salida = kardex.firstWhere((k) => k.cantidad < 0);
      expect(salida.cantidad, -1);
      expect(salida.stockResultante, 47);
      expect(salida.motivo, 'Venta M01-000001');
      expect(salida.referenciaId, guardada.id);

      // Outbox: producto (siembra) + inventario (apertura) + venta + inventario
      // (salida) + caja + movimiento de apertura.
      final eventosVenta = await filasOutbox(EntidadesSync.venta);
      expect(eventosVenta, hasLength(1));
      expect(eventosVenta.first['operacion'], OperacionesSync.insert);
      expect(eventosVenta.first['entidad_id'], guardada.id);
      expect(eventosVenta.first['estado'], EstadoOutbox.pendiente);
      expect(eventosVenta.first['origen_caja_id'], 'movil-01');

      final eventosInv = await filasOutbox(EntidadesSync.inventario);
      expect(eventosInv, hasLength(2)); // apertura + salida de la venta
    });

    test('el payload de la venta lleva sus detalles y se puede releer',
        () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto();
      final v = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(7.00),
        detalles: [
          DetalleVenta(
            productoId: p.id,
            descripcionProducto: p.nombre,
            cantidad: 2,
            precioUnitario: Dinero.deSoles(3.50),
            importe: Dinero.deSoles(7.00),
          ),
        ],
      ));

      final evento = EventoSyncLocal.desdeFila(
          (await filasOutbox(EntidadesSync.venta)).first);
      final payload = evento.payload;

      expect(payload['Numero'], v.numero);
      expect(payload['Total'], 7.0);
      expect((payload['Detalles'] as List), hasLength(1));

      final reconstruida = Venta.desdeJson(payload);
      expect(reconstruida.id, v.id);
      expect(reconstruida.detalles.first.cantidad, 2);
    });

    test('ROLLBACK: si el detalle viola una FK no queda nada escrito', () async {
      final caja = await abrirCaja();
      final outboxAntes = (await filasOutbox()).length;

      final venta = Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(3.50),
        detalles: [
          DetalleVenta(
            // Producto inexistente: rompe detalle_ventas.producto_id.
            productoId: Uuid.v4(),
            descripcionProducto: 'Fantasma',
            cantidad: 1,
            precioUnitario: Dinero.deSoles(3.50),
            importe: Dinero.deSoles(3.50),
          ),
        ],
      );

      await expectLater(ventas.registrar(venta), throwsA(anything));

      // Ni cabecera, ni detalle, ni evento: la caja no queda a medias.
      expect(await db.escalar('SELECT COUNT(*) FROM ventas'), 0);
      expect(await db.escalar('SELECT COUNT(*) FROM detalle_ventas'), 0);
      expect((await filasOutbox()).length, outboxAntes);
    });

    test('ROLLBACK: el correlativo no se consume si la venta falla', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto();

      // Primera venta OK -> consume el 1.
      final ok = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(3.50),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 1,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(3.50)),
        ],
      ));
      expect(ok.numero, 'M01-000001');

      // Segunda venta falla -> NO debe consumir el 2.
      await expectLater(
        ventas.registrar(Venta(
          cajaId: caja.id,
          total: Dinero.deSoles(1.00),
          detalles: [
            DetalleVenta(
                productoId: Uuid.v4(),
                cantidad: 1,
                precioUnitario: Dinero.deSoles(1.00),
                importe: Dinero.deSoles(1.00)),
          ],
        )),
        throwsA(anything),
      );

      // Tercera venta OK -> tiene que ser el 2, sin hueco.
      final tercera = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(3.50),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 1,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(3.50)),
        ],
      ));
      expect(tercera.numero, 'M01-000002');
    });

    test('una venta sin líneas se rechaza antes de tocar la BD', () async {
      final caja = await abrirCaja();
      await expectLater(
        ventas.registrar(Venta(cajaId: caja.id)),
        throwsA(isA<Object>()),
      );
      expect(await db.escalar('SELECT COUNT(*) FROM ventas'), 0);
    });

    test('un producto que no controla stock no genera kardex', () async {
      final caja = await abrirCaja();
      final servicio = await sembrarProducto(
        codigo: 'SRV-001',
        nombre: 'Lavandería (prenda)',
        stock: 0,
        precio: 8.00,
        controlaStock: false,
      );

      await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(8.00),
        detalles: [
          DetalleVenta(
              productoId: servicio.id,
              cantidad: 1,
              precioUnitario: Dinero.deSoles(8.00),
              importe: Dinero.deSoles(8.00)),
        ],
      ));

      expect(await productos.kardex(servicio.id), isEmpty);
      expect(await stockDe(servicio.id), 0);
    });
  });

  group('anulación', () {
    test('devuelve el stock, marca la venta y emite {id, estado}', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto(stock: 10);

      final v = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(7.00),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 2,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(7.00)),
        ],
      ));
      expect(await stockDe(p.id), 8);

      await ventas.anular(v.id);

      expect(await stockDe(p.id), 10);
      final releida = await ventas.obtenerPorId(v.id);
      expect(releida!.estado, EstadoVenta.anulada);

      final eventos = await filasOutbox(EntidadesSync.venta);
      final anulacion =
          eventos.firstWhere((e) => e['operacion'] == OperacionesSync.update);
      final payload = EventoSyncLocal.desdeFila(anulacion).payload;

      // Claves en MINÚSCULAS: es el tipo anónimo que espera el escritorio.
      expect(payload.keys, containsAll(['id', 'estado']));
      expect(payload['estado'], EstadoVenta.anulada.valor);
      // Y con el origen del dispositivo, para que el filtro de eco funcione.
      expect(anulacion['origen_caja_id'], 'movil-01');
    });

    test('anular dos veces es idempotente (no duplica la reversa)', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto(stock: 10);
      final v = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(3.50),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 1,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(3.50)),
        ],
      ));

      await ventas.anular(v.id);
      await ventas.anular(v.id);

      expect(await stockDe(p.id), 10, reason: 'la reversa se aplicó dos veces');
    });
  });

  group('caja', () {
    test('no deja abrir dos cajas a la vez', () async {
      await abrirCaja();
      await expectLater(abrirCaja(), throwsA(anything));
      final v = await db.escalar(
          'SELECT COUNT(*) FROM caja WHERE estado = ?', [EstadoCaja.abierta.valor]);
      expect(v, 1);
    });

    test('la apertura escribe caja + movimiento de fondo + dos eventos',
        () async {
      final caja = await abrirCaja();
      final movs = await cajas.listarMovimientos(caja.id);
      expect(movs, hasLength(1));
      expect(movs.first.tipo, TipoMovimientoCaja.aperturaFondo);
      expect(movs.first.monto, Dinero.deSoles(50.00));

      expect(await filasOutbox(EntidadesSync.caja), hasLength(1));
      expect(await filasOutbox(EntidadesSync.movimientoCaja), hasLength(1));
    });

    test('el cierre calcula la diferencia sin contar el fondo dos veces',
        () async {
      final caja = await abrirCaja();
      await cajas.registrarMovimiento(MovimientoCaja(
        cajaId: caja.id,
        tipo: TipoMovimientoCaja.ingreso,
        monto: Dinero.deSoles(12.70),
        concepto: 'Venta M01-000001 (Efectivo)',
      ));
      await cajas.registrarMovimiento(MovimientoCaja(
        cajaId: caja.id,
        tipo: TipoMovimientoCaja.retiro,
        monto: Dinero.deSoles(20.00),
        concepto: 'Retiro',
      ));

      // Esperado: 50 + 12.70 - 20 = 42.70. Se cuentan 42.00 -> faltan 0.70.
      final cerrada =
          await cajas.cerrar(caja, montoContado: Dinero.deSoles(42.00));

      expect(cerrada.estado, EstadoCaja.cerrada);
      expect(cerrada.montoCierre, Dinero.deSoles(42.00));
      expect(cerrada.diferencia, Dinero.enCentimos(-70));
    });
  });

  group('correlativos con prefijo del servidor', () {
    test('sin vincular usa el prefijo de respaldo documentado', () async {
      final db2 = BaseDatosPagoYa(NativeDatabase.memory());
      await db2.inicializarEsquema();
      final cfg = ConfiguracionDispositivo(db2);

      expect(await cfg.estaVinculado(), isFalse);
      expect(await cfg.prefijoDispositivo(),
          ConfiguracionDispositivo.prefijoSinVincular);

      final corr = Correlativos(db2, cfg);
      final n = await db2.transaccion((tx) => corr.siguienteVenta(tx));
      expect(n, 'M00-000001');

      await db2.close();
    });

    test('guarda el devicePrefix que devolvió el servidor, normalizado',
        () async {
      await config.guardarVinculacion(devicePrefix: ' m07 ', origen: 'movil-07');
      config.invalidarCache();
      expect(await config.prefijoDispositivo(), 'M07');
      expect(await config.origenCajaId(), 'movil-07');
    });

    test('rechaza vincular sin devicePrefix', () async {
      await expectLater(
        config.guardarVinculacion(devicePrefix: '  ', origen: 'x'),
        throwsA(anything),
      );
    });

    test('el contador es monótono y se formatea a seis dígitos', () async {
      final corr = Correlativos(db, config);
      final numeros = <String>[];
      for (var i = 0; i < 3; i++) {
        numeros.add(await db.transaccion((tx) => corr.siguienteVenta(tx)));
      }
      expect(numeros, ['M01-000001', 'M01-000002', 'M01-000003']);
    });

    test('ventas y pedidos llevan contadores independientes', () async {
      final corr = Correlativos(db, config);
      expect(await db.transaccion((tx) => corr.siguienteVenta(tx)),
          'M01-000001');
      expect(await db.transaccion((tx) => corr.siguientePedido(tx)),
          'M01-000001');
      expect(await db.transaccion((tx) => corr.siguienteVenta(tx)),
          'M01-000002');
    });

    test('prefijoDe distingue el formato nuevo del viejo del escritorio', () {
      expect(Correlativos.prefijoDe('M01-000123'), 'M01');
      expect(Correlativos.prefijoDe('C01-000123'), 'C01');
      // Formato viejo del escritorio: "V-" + yyMMdd-HHmmss -> sin prefijo.
      expect(Correlativos.prefijoDe('V-260902-143012'), '');
      expect(Correlativos.prefijoDe('singuion'), '');
      expect(Correlativos.prefijoDe(''), '');
    });
  });

  group('aplicación de cambios remotos', () {
    CambioRemoto cambio(String entidad, String id, Map<String, Object?> payload,
            {String op = 'UPSERT', DateTime? ts, String origen = 'pc-01'}) =>
        CambioRemoto(
          entidad: entidad,
          entidadId: id,
          operacion: op,
          payloadJson: _json(payload),
          actualizadoUtc: ts ?? DateTime.now().toUtc(),
          origenCajaId: origen,
        );

    test('un producto remoto nuevo se inserta con su stock de apertura',
        () async {
      final remoto = Producto(
        codigo: 'PC-001',
        nombre: 'Arroz Costeño 1kg',
        precioVenta: Dinero.deSoles(5.80),
        stockActual: 30,
        origenCajaId: 'pc-01',
      );

      final n = await outbox.aplicarCambiosRemotos(
          [cambio(EntidadesSync.producto, remoto.id, remoto.aJson())]);

      expect(n, 1);
      expect(await stockDe(remoto.id), 30);
    });

    test('LWW: un cambio más viejo NO pisa lo local', () async {
      final p = await sembrarProducto();
      final ayer = DateTime.now().toUtc().subtract(const Duration(days: 1));

      final viejo = Producto.desdeJson(p.aJson())
        ..nombre = 'Nombre viejo de la PC'
        ..actualizadoUtc = ayer;

      final n = await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.producto, p.id, viejo.aJson(), ts: ayer),
      ]);

      expect(n, 0, reason: 'el LWW debía descartar el cambio viejo');
      final actual = await productos.obtenerPorId(p.id);
      expect(actual!.nombre, 'Inca Kola 500ml');
    });

    test('LWW: un cambio más nuevo sí actualiza', () async {
      final p = await sembrarProducto();
      final manana = DateTime.now().toUtc().add(const Duration(days: 1));

      final nuevo = Producto.desdeJson(p.aJson())
        ..nombre = 'Inca Kola 500ml (nuevo)'
        ..precioVenta = Dinero.deSoles(4.00);

      final n = await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.producto, p.id, nuevo.aJson(), ts: manana),
      ]);

      expect(n, 1);
      final actual = await productos.obtenerPorId(p.id);
      expect(actual!.nombre, 'Inca Kola 500ml (nuevo)');
      expect(actual.precioVenta, Dinero.deSoles(4.00));
    });

    test('EL CASO CRÍTICO: el upsert remoto NO pisa el stock local', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto(stock: 10);

      // El móvil vende 2 -> stock local 8.
      await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(7.00),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 2,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(7.00)),
        ],
      ));
      expect(await stockDe(p.id), 8);

      // Llega de la PC el snapshot del producto con stock 7 (ella vendió 3),
      // MÁS NUEVO que lo local. Con LWW puro el stock quedaría en 7 y se
      // perdería la venta del móvil.
      final desdePc = Producto.desdeJson(p.aJson())..stockActual = 7;
      await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.producto, p.id, desdePc.aJson(),
            ts: DateTime.now().toUtc().add(const Duration(minutes: 5))),
      ]);

      expect(await stockDe(p.id), 8,
          reason: 'el snapshot remoto pisó el stock: se perdió una venta');

      // Ahora llega el KARDEX de la PC (−3): ahí sí se aplica el delta.
      final kardexPc = Inventario(
        productoId: p.id,
        cantidad: -3,
        stockResultante: 7,
        motivo: MotivosKardex.venta('C01-000045'),
        origenCajaId: 'pc-01',
      );
      await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.inventario, kardexPc.id, kardexPc.aJson(),
            op: 'INSERT'),
      ]);

      // 10 − 2 (móvil) − 3 (PC) = 5. Ninguna venta se perdió.
      expect(await stockDe(p.id), 5);
    });

    test('el kardex remoto duplicado no descuenta dos veces', () async {
      final p = await sembrarProducto(stock: 10);
      final k = Inventario(
        productoId: p.id,
        cantidad: -3,
        stockResultante: 7,
        motivo: 'Venta C01-000045',
        origenCajaId: 'pc-01',
      );
      final c = cambio(EntidadesSync.inventario, k.id, k.aJson(), op: 'INSERT');

      expect(await outbox.aplicarCambiosRemotos([c]), 1);
      expect(await stockDe(p.id), 7);

      // Reenvío del mismo evento (mismo UUID): insert-if-absent -> no aplica.
      expect(await outbox.aplicarCambiosRemotos([c]), 0);
      expect(await stockDe(p.id), 7, reason: 'se descontó dos veces');
    });

    test('el orden de llegada del kardex no cambia el resultado', () async {
      final p = await sembrarProducto(stock: 100);
      final movs = [
        Inventario(productoId: p.id, cantidad: -3, motivo: 'a'),
        Inventario(productoId: p.id, cantidad: -7, motivo: 'b'),
        Inventario(productoId: p.id, cantidad: 20, motivo: 'c'),
      ];
      final cambios = movs
          .map((m) =>
              cambio(EntidadesSync.inventario, m.id, m.aJson(), op: 'INSERT'))
          .toList();

      await outbox.aplicarCambiosRemotos(cambios.reversed.toList());
      expect(await stockDe(p.id), 110);
    });

    test('la baja remota de producto lo desactiva', () async {
      final p = await sembrarProducto();
      await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.producto, p.id, {'id': p.id},
            op: OperacionesSync.delete,
            ts: DateTime.now().toUtc().add(const Duration(minutes: 1))),
      ]);
      final actual = await productos.obtenerPorId(p.id);
      expect(actual!.activo, isFalse);
    });

    test('la anulación remota de venta cambia solo el estado', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto();
      final v = await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(3.50),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 1,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(3.50)),
        ],
      ));

      await outbox.aplicarCambiosRemotos([
        cambio(EntidadesSync.venta, v.id,
            {'id': v.id, 'estado': EstadoVenta.anulada.valor},
            op: OperacionesSync.update,
            ts: DateTime.now().toUtc().add(const Duration(minutes: 1))),
      ]);

      final releida = await ventas.obtenerPorId(v.id);
      expect(releida!.estado, EstadoVenta.anulada);
      expect(releida.total, Dinero.deSoles(3.50), reason: 'no debía tocar el total');
    });

    test('una entidad desconocida se ignora sin romper el lote', () async {
      final p = await sembrarProducto();
      final n = await outbox.aplicarCambiosRemotos([
        cambio('entidad_del_futuro', Uuid.v4(), {'algo': 1}),
        cambio(EntidadesSync.producto, p.id, (Producto.desdeJson(p.aJson())..nombre = 'X').aJson(),
            ts: DateTime.now().toUtc().add(const Duration(minutes: 1))),
      ]);
      expect(n, 1, reason: 'la entidad desconocida no debe contar ni abortar');
      expect((await productos.obtenerPorId(p.id))!.nombre, 'X');
    });

    test('un lote vacío no abre transacción ni falla', () async {
      expect(await outbox.aplicarCambiosRemotos(const []), 0);
    });
  });

  group('cola del outbox', () {
    test('leerPendientes respeta el orden y el límite', () async {
      await sembrarProducto(codigo: 'A', nombre: 'A');
      await sembrarProducto(codigo: 'B', nombre: 'B');

      final todos = await outbox.leerPendientes(100);
      expect(todos.length, greaterThanOrEqualTo(4));
      final limitados = await outbox.leerPendientes(2);
      expect(limitados, hasLength(2));
    });

    test('marcarEnviados los saca de la cola', () async {
      await sembrarProducto();
      final pendientes = await outbox.leerPendientes(100);
      expect(await outbox.contarPendientes(), pendientes.length);

      await outbox.marcarEnviados(pendientes.map((e) => e.id).toList());
      expect(await outbox.contarPendientes(), 0);
      expect(await outbox.leerPendientes(100), isEmpty);
    });

    test('registrarFallo cuenta intentos y manda a dead-letter al llegar al máximo',
        () async {
      await sembrarProducto();
      final ids = (await outbox.leerPendientes(100)).map((e) => e.id).toList();

      await outbox.registrarFallo(ids, 3);
      expect(await outbox.contarPendientes(), ids.length,
          reason: 'con 1 intento sigue pendiente');

      await outbox.registrarFallo(ids, 3);
      await outbox.registrarFallo(ids, 3);
      expect(await outbox.contarPendientes(), 0,
          reason: 'al 3.er intento debía pasar a dead-letter');

      final enError = await db.escalar(
          'SELECT COUNT(*) FROM outbox_sync WHERE estado = ?',
          [EstadoOutbox.error]);
      expect(enError, ids.length);
    });

    test('marcar o fallar una lista vacía es un no-op', () async {
      await outbox.marcarEnviados(const []);
      await outbox.registrarFallo(const [], 3);
    });

    test('el cursor de bajada se guarda y se relee', () async {
      expect(await outbox.leerCursor(), isNull);
      await outbox.guardarCursor('1234');
      expect(await outbox.leerCursor(), '1234');
      await outbox.guardarCursor('5678');
      expect(await outbox.leerCursor(), '5678');
    });
  });

  group('stock derivado del kardex', () {
    test('crearConStockInicial deja el kardex completo y recalculable',
        () async {
      final p = await sembrarProducto(stock: 48);

      expect(await outbox.kardexEsCompleto(p.id), isTrue);
      final n = await outbox.recalcularStockDesdeKardex(productoId: p.id);
      expect(n, 1);
      expect(await stockDe(p.id), 48);
    });

    test('el recálculo reproduce el stock tras ventas y ajustes', () async {
      final caja = await abrirCaja();
      final p = await sembrarProducto(stock: 100);

      await ventas.registrar(Venta(
        cajaId: caja.id,
        total: Dinero.deSoles(10.50),
        detalles: [
          DetalleVenta(
              productoId: p.id,
              cantidad: 3,
              precioUnitario: Dinero.deSoles(3.50),
              importe: Dinero.deSoles(10.50)),
        ],
      ));
      await productos.ajustarStock(
        productoId: p.id,
        cantidad: -2,
        motivo: MotivosKardex.merma,
      );
      await productos.ajustarStock(
        productoId: p.id,
        cantidad: 24,
        motivo: MotivosKardex.compra,
      );

      final esperado = await stockDe(p.id); // 100 - 3 - 2 + 24 = 119
      expect(esperado, 119);

      // Se corrompe el caché a mano y el recálculo lo repara.
      await db.ejecutar(
          'UPDATE productos SET stock_actual = 0 WHERE id = ?', [p.id]);
      await outbox.recalcularStockDesdeKardex(productoId: p.id);
      expect(await stockDe(p.id), esperado);
    });

    test('sin fila de apertura el recálculo NO es confiable, y se puede saber',
        () async {
      // Producto guardado con `guardar` (como hace el escritorio): sin kardex
      // de apertura. Es justo el caso en el que recalcular daría 0.
      final p = Producto(
        codigo: 'PC-VIEJO',
        nombre: 'Producto de una PC vieja',
        stockActual: 25,
      );
      await productos.guardar(p);

      expect(await outbox.kardexEsCompleto(p.id), isFalse);
      await outbox.recalcularStockDesdeKardex(productoId: p.id);
      expect(await stockDe(p.id), 0,
          reason: 'documenta por qué el recálculo NO se llama '
              'automáticamente al sincronizar');
    });
  });

  group('ajuste de stock', () {
    test('escribe kardex + outbox y devuelve el resultante', () async {
      final p = await sembrarProducto(stock: 10);
      final r = await productos.ajustarStock(
        productoId: p.id,
        cantidad: -4,
        motivo: MotivosKardex.merma,
      );
      expect(r, 6);
      expect(await stockDe(p.id), 6);

      final eventos = await filasOutbox(EntidadesSync.inventario);
      expect(eventos, hasLength(2)); // apertura + merma
      final ultimo = EventoSyncLocal.desdeFila(eventos.last).payload;
      expect(ultimo['Cantidad'], -4);
      expect(ultimo['Motivo'], MotivosKardex.merma);
    });

    test('un producto inexistente lanza', () async {
      await expectLater(
        productos.ajustarStock(
            productoId: Uuid.v4(), cantidad: 1, motivo: 'x'),
        throwsA(anything),
      );
    });
  });
}

/// Serializa el payload igual que `OutboxHelper` (sin indentar), para armar
/// los `CambioRemoto` de las pruebas tal como llegarían de la nube.
String _json(Map<String, Object?> m) => jsonEncode(m);
