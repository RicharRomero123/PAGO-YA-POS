import 'package:flutter_test/flutter_test.dart';
import 'package:pagoya_hardware/pagoya_hardware.dart';

/// Tests de las implementaciones falsas y de las reglas de negocio que
/// dependen de ellas.
///
/// La más importante: **un fallo de impresión nunca bloquea la venta**
/// (`docs/MOBILE-ARQUITECTURA.md` §5.3 y `CLAUDE.md`). Se verifica aquí, en la
/// capa de hardware, para que `flutter-ui` pueda apoyarse en el contrato.
void main() {
  TicketVenta ticket() => TicketVenta(
        numero: 'M01-000001',
        fechaHora: DateTime(2026, 9, 2, 10, 0),
        metodoPago: MetodoPagoTicket.efectivo,
        subTotal: 8.47,
        igv: 1.53,
        total: 10.00,
        montoRecibido: 20,
        negocio: const DatosNegocioTicket(nombre: 'Bodega Doña Rosa'),
        lineas: const [
          LineaVentaTicket(
            descripcion: 'Arroz Costeño 1kg',
            cantidad: 1,
            precioUnitario: 10,
            importe: 10,
          ),
        ],
      );

  group('ImpresoraTicketsFalsa', () {
    test('un fallo de impresión devuelve resultado, NUNCA lanza', () async {
      final impresora = ImpresoraTicketsFalsa(
        fallarSiempre: true,
        demora: Duration.zero,
      );
      addTearDown(impresora.liberar);

      // Si esto lanzara, la venta se caería con él.
      final r = await impresora.imprimirTicket(ticket());

      expect(r.exito, isFalse);
      expect(r.mensaje, isNotNull);
      expect(r.mensaje, isNot(contains('Exception')));
      expect(r.codigo, CausaFalloImpresion.escrituraFallida);
      expect(r.vaLaPenaReintentar, isTrue);
    });

    test('el último ticket se guarda aunque la impresión falle', () async {
      final impresora = ImpresoraTicketsFalsa(
        fallarSiempre: true,
        demora: Duration.zero,
      );
      addTearDown(impresora.liberar);

      await impresora.imprimirTicket(ticket());
      expect(impresora.ultimoTicket, isNotNull);

      // "Imprimir de nuevo" tiene que estar disponible tras el fallo: es el
      // caso real (se acabó el papel, la impresora estaba apagada).
      impresora.fallarSiempre = false;
      final r = await impresora.reimprimirUltimo();
      expect(r.exito, isTrue);
      expect(impresora.ticketsImpresos.single, contains('** REIMPRESION **'));
    });

    test('sin impresora seleccionada no se puede conectar', () async {
      final impresora = ImpresoraTicketsFalsa(demora: Duration.zero);
      addTearDown(impresora.liberar);

      final r = await impresora.conectar();
      expect(r.exito, isFalse);
      expect(r.codigo, CausaFalloImpresion.sinImpresoraConfigurada);
      expect(impresora.estadoActual, EstadoImpresora.sinConfigurar);
    });

    test('imprime el ticket con el formato del renderizador', () async {
      final impresora = ImpresoraTicketsFalsa(demora: Duration.zero);
      addTearDown(impresora.liberar);

      await impresora.seleccionarImpresora(
        (await impresora.buscarImpresoras()).first,
      );
      final r = await impresora.imprimirTicket(ticket());

      expect(r.exito, isTrue);
      expect(impresora.ticketsImpresos.single, contains('Bodega Doña Rosa'));
      expect(impresora.ticketsImpresos.single, contains('S/ 10.00'));
      expect(impresora.ticketsImpresos.single, contains('Vuelto:'));
    });
  });

  group('IdentidadDispositivoFalsa', () {
    test('el id es estable entre llamadas', () async {
      final identidad = IdentidadDispositivoFalsa();
      final a = await identidad.obtenerIdDispositivo();
      final b = await identidad.obtenerIdDispositivo();
      expect(a, b);
    });

    test('el id generado es un UUID v4 válido', () async {
      final id = await IdentidadDispositivoFalsa().obtenerIdDispositivo();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('regenerar cambia el id (y por eso solo es para soporte)', () async {
      final identidad = IdentidadDispositivoFalsa();
      final antes = await identidad.obtenerIdDispositivo();
      final despues = await identidad.regenerar();
      expect(despues, isNot(antes));
      expect(identidad.regeneraciones, 1);
    });

    test('se puede fijar un id conocido para los tests de licencia', () async {
      const fijo = '11111111-1111-4111-8111-111111111111';
      final identidad = IdentidadDispositivoFalsa(id: fijo);
      expect(await identidad.obtenerIdDispositivo(), fijo);
      expect((await identidad.obtenerInfo()).id, fijo);
      expect(await identidad.obtenerPlataforma(), 'android');
    });

    test('un almacén seguro inaccesible lanza, no devuelve un id nuevo', () {
      // `pagoya_core` traduce esta excepción a fallo transitorio. Si en vez de
      // lanzar devolviéramos un UUID nuevo, el cliente perdería su activación
      // en silencio.
      final identidad = IdentidadDispositivoFalsa(fallar: true);
      expect(identidad.obtenerIdDispositivo(), throwsStateError);
    });
  });

  group('AlmacenSeguroFalso', () {
    test('guarda, lee y borra', () async {
      final almacen = AlmacenSeguroFalso();

      expect(await almacen.leer('token'), isNull);

      await almacen.escribir('token', 'abc.def');
      expect(await almacen.leer('token'), 'abc.def');

      await almacen.escribir('token', 'nuevo');
      expect(await almacen.leer('token'), 'nuevo');

      await almacen.borrar('token');
      expect(await almacen.leer('token'), isNull);
    });

    test('borrar algo que no existe no falla', () async {
      final almacen = AlmacenSeguroFalso();
      await expectLater(almacen.borrar('no-existe'), completes);
    });

    test('un almacén ilegible devuelve null, no lanza', () async {
      // Contrato de `AlmacenSeguro.leer`: degradar a "sin licencia" es el fallo
      // seguro; lanzar solo daría un stack trace al bodeguero.
      final almacen = AlmacenSeguroFalso(inicial: {'token': 'abc'})
        ..fallarLectura = true;
      expect(await almacen.leer('token'), isNull);
    });

    test('un fallo de escritura SÍ se propaga', () async {
      // Tragárselo sería el peor bug del producto: el cliente activa, ve
      // "listo", y al reabrir la app vuelve a estar bloqueado.
      final almacen = AlmacenSeguroFalso()..fallarEscritura = true;
      await expectLater(
        almacen.escribir('token', 'abc'),
        throwsA(isA<StateError>()),
      );
    });

    test('se puede sembrar con un token ya activado', () async {
      final almacen = AlmacenSeguroFalso(inicial: {'licencia': 'token-firmado'});
      expect(await almacen.leer('licencia'), 'token-firmado');
      expect(almacen.contenido, {'licencia': 'token-firmado'});
    });
  });

  group('CompartirArchivoFalso', () {
    test('registra el comprobante compartido', () async {
      final compartir = CompartirArchivoFalso();
      final r = await compartir.compartirComprobante(ticket());

      expect(r.exito, isTrue);
      expect(compartir.compartidos.single.nombreArchivo,
          'PagoYa-M01-000001.png');
      expect(compartir.compartidos.single.mimeType, 'image/png');
    });

    test('la cancelación del usuario no es un error', () async {
      final compartir = CompartirArchivoFalso(simularCancelacion: true);
      final r = await compartir.compartirComprobante(ticket());
      expect(r.exito, isFalse);
      expect(r.cancelado, isTrue);
      expect(r.mensaje, isNull); // no hay nada que mostrarle al usuario
    });
  });

  group('normalización de teléfono peruano', () {
    test('celular de 9 dígitos recibe el prefijo 51', () {
      expect(
        CompartirArchivoSharePlus.normalizarTelefonoPeru('987 654 321'),
        '51987654321',
      );
    });

    test('acepta formato internacional', () {
      expect(
        CompartirArchivoSharePlus.normalizarTelefonoPeru('+51 987654321'),
        '51987654321',
      );
    });

    test('rechaza lo que no parece un número', () {
      expect(CompartirArchivoSharePlus.normalizarTelefonoPeru('123'), isNull);
      expect(CompartirArchivoSharePlus.normalizarTelefonoPeru(''), isNull);
    });
  });

  group('EscanerFalso', () {
    test('emite las lecturas simuladas', () async {
      final escaner = EscanerFalso();
      final sesion =
          await escaner.abrirSesion(modo: ModoEscaneo.continuo)
              as SesionEscaneoFalsa;
      addTearDown(sesion.cerrar);

      final recibidos = <String>[];
      sesion.lecturas.listen((c) => recibidos.add(c.valor));

      sesion.simularLectura('7501055');
      sesion.simularLectura('7502001');
      await Future<void>.delayed(Duration.zero);

      expect(recibidos, ['7501055', '7502001']);
    });

    test('en modo único deja de emitir tras la primera lectura', () async {
      final escaner = EscanerFalso();
      final sesion = await escaner.abrirSesion() as SesionEscaneoFalsa;
      addTearDown(sesion.cerrar);

      final recibidos = <String>[];
      sesion.lecturas.listen((c) => recibidos.add(c.valor));

      sesion.simularLectura('7501055');
      sesion.simularLectura('7501056');
      await Future<void>.delayed(Duration.zero);

      expect(recibidos, ['7501055']);
    });
  });

  group('HardwarePagoYa.falso', () {
    test('modo "todo falla" para probar que la venta no se bloquea', () async {
      final hardware = HardwarePagoYa.falso(todoFalla: true);
      addTearDown(hardware.liberar);

      final impresion = await hardware.impresora.imprimirTicket(ticket());
      final envio = await hardware.compartir.compartirComprobante(ticket());

      expect(impresion.exito, isFalse);
      expect(envio.exito, isFalse);
      // Y aun así el licenciamiento sigue funcionando: el gate no depende de
      // la impresora ni de WhatsApp.
      expect(await hardware.identidad.obtenerIdDispositivo(), isNotEmpty);
      await hardware.almacenSeguro.escribir('licencia', 'token');
      expect(await hardware.almacenSeguro.leer('licencia'), 'token');
    });

    test('expone las cinco capacidades, real y falsa', () {
      final falso = HardwarePagoYa.falso();
      addTearDown(falso.liberar);

      // Si alguna de estas deja de existir, el composition root no arranca.
      expect(falso.impresora, isA<ImpresoraTickets>());
      expect(falso.escaner, isA<EscanerCodigos>());
      expect(falso.identidad, isA<IdentidadDispositivo>());
      expect(falso.almacenSeguro, isA<AlmacenSeguro>());
      expect(falso.compartir, isA<CompartirArchivo>());
    });
  });
}