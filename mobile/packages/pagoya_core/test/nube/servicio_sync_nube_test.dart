/// Tests del ciclo push/pull con transporte simulado.
///
/// Cubren los cinco escenarios que rompen en producción y que el escritorio ya
/// aprendió a la mala: corte a mitad del push, lote duplicado, cursor
/// desfasado, evento venenoso y 403 por licencia sin `cloud_sync`. Más los dos
/// que son exclusivos del móvil: el **eco** (el pull nos devuelve lo que
/// acabamos de subir) y la **regla crítica** de que un fallo de red jamás sale
/// como excepción.
library;

import 'package:pagoya_core/nube/nube.dart';
import 'package:test/test.dart';

import 'dobles_sync.dart';

ServicioSyncNube _servicio(
  AlmacenOutboxEnMemoria outbox,
  TransporteSync transporte, {
  OpcionesSync? opciones,
}) =>
    ServicioSyncNube(
      outbox: outbox,
      transporte: transporte,
      opciones: opciones ?? opcionesDePrueba(),
    );

void main() {
  setUp(reiniciarContadorEventos);

  // ===========================================================================
  group('PUSH — corte a mitad', () {
    test('un corte en el segundo lote no reenvía lo aceptado ni pierde el resto',
        () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      outbox.encolarVarios(List.generate(250, (_) => eventoDePrueba()));

      // El primer push va bien; el segundo se corta (se cayó la señal).
      transporte.fallosPushEncolados.addAll([null, TipoFalloSync.red]);

      final svc = _servicio(outbox, transporte,
          opciones: opcionesDePrueba(tamanoLote: 100, maxIntentos: 3));

      final r1 = await svc.sincronizar();

      expect(r1.exito, isFalse, reason: 'el ciclo debe reportar el fallo');
      expect(r1.motivo, MotivoFalloSync.sinRed);
      expect(r1.enviados, 100, reason: 'solo el primer lote llegó');
      expect(outbox.idsEnviados, hasLength(100));
      expect(outbox.idsPendientes, hasLength(150));
      expect(outbox.idsDeadLetter, isEmpty,
          reason: 'un corte de red no manda nada a dead-letter con 3 intentos');
      // El lote cortado acumuló UN intento, no más.
      expect(outbox.intentosDe(outbox.idsPendientes.first), 1);

      // Vuelve la señal: se reanuda desde donde quedó.
      final r2 = await svc.sincronizar();

      expect(r2.exito, isTrue);
      expect(r2.enviados, 150, reason: 'exactamente lo que faltaba');
      expect(outbox.idsEnviados, hasLength(250));
      expect(outbox.idsPendientes, isEmpty);

      // Y el servidor tiene 250 filas, ni una repetida.
      expect(transporte.registro, hasLength(250));
      expect(transporte.aceptados, hasLength(250));
    });

    test('el ciclo no gasta un pull si el push ya se cayó por red', () async {
      final outbox = AlmacenOutboxEnMemoria()..encolar(eventoDePrueba());
      final transporte = TransporteSyncEnMemoria()
        ..fallosPushEncolados.add(TipoFalloSync.red);

      await _servicio(outbox, transporte).sincronizar();

      expect(transporte.llamadasPull, 0);
    });
  });

  // ===========================================================================
  group('PUSH — lote duplicado (idempotencia)', () {
    test('reenviar un lote ya aceptado no duplica filas en el servidor',
        () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      outbox.encolarVarios(List.generate(5, (_) => eventoDePrueba()));

      // Escenario real: el servidor guardó el lote, pero la respuesta se perdió
      // (túnel, cambio de celda). El cliente no puede marcar nada como enviado.
      transporte.ocultarAceptados = true;
      final svc = _servicio(outbox, transporte,
          opciones: opcionesDePrueba(tamanoLote: 100, maxIntentos: 5));

      final r1 = await svc.sincronizar();
      expect(r1.enviados, 0);
      expect(transporte.registro, hasLength(5),
          reason: 'el servidor SÍ los guardó');
      expect(outbox.idsPendientes, hasLength(5),
          reason: 'localmente siguen pendientes: se reenviarán');

      // Segundo intento con la respuesta completa: el backend deduplica por
      // (licencia, id de evento) y devuelve TODO como aceptado.
      transporte.ocultarAceptados = false;
      final r2 = await svc.sincronizar();

      expect(r2.enviados, 5);
      expect(outbox.idsEnviados, hasLength(5));
      expect(transporte.registro, hasLength(5),
          reason: 'idempotencia: sigue habiendo 5 filas, no 10');
    });

    test('un id repetido dentro del mismo lote se registra una sola vez',
        () async {
      final transporte = TransporteSyncEnMemoria();
      final e = eventoDePrueba();

      final r = await transporte.enviarLote([e, e]);

      expect(r.ok, isTrue);
      expect(r.aceptadosIds, hasLength(2), reason: 'ambos se aceptan');
      expect(transporte.registro, hasLength(1), reason: 'pero solo una fila');
    });
  });

  // ===========================================================================
  group('PULL — cursor', () {
    test('desde cero aplica todos los cambios ajenos y guarda el cursor',
        () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      for (var i = 0; i < 3; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }

      final r = await _servicio(outbox, transporte).sincronizar();

      expect(r.exito, isTrue);
      expect(r.recibidos, 3);
      expect(await outbox.leerCursor(), '3');
      expect(outbox.aplicados, hasLength(3));
    });

    test('cursor desfasado HACIA ATRÁS: se re-baja pero el LWW lo hace inocuo',
        () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      for (var i = 0; i < 3; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }
      final svc = _servicio(outbox, transporte);

      await svc.sincronizar();
      expect(outbox.aplicados, hasLength(3));

      // Simula el corte entre "aplicar" y "guardar cursor": el cursor retrocede.
      await outbox.guardarCursor('0');
      final r = await svc.sincronizar();

      expect(r.exito, isTrue);
      expect(r.recibidos, 0,
          reason: 'el last-write-wins descarta lo ya aplicado');
      expect(outbox.aplicados, hasLength(3), reason: 'nada se duplicó');
    });

    test('cursor desfasado HACIA ADELANTE: el server lo acota y el cliente lo adopta',
        () async {
      // El backend devuelve `min(cursorRecibido, maxSecuencia(licencia))` cuando
      // la ventana sale vacía. El cliente tiene que ADOPTAR ese cursor acotado:
      // si se quedara con el suyo, no volvería a ver un cambio nunca.
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      for (var i = 0; i < 3; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }
      await outbox.guardarCursor('999');

      final svc = _servicio(outbox, transporte);
      final r = await svc.sincronizar();

      expect(r.exito, isTrue);
      expect(transporte.cursoresAcotados, 1, reason: 'el server lo detectó');
      expect(await outbox.leerCursor(), '3',
          reason: 'cursor reparado a la secuencia máxima real');
      expect(r.recibidos, 0);
      expect(outbox.aplicados, isEmpty,
          reason: 'reparar el cursor NO re-entrega el histórico');
      expect(transporte.llamadasPull, 1, reason: 'una llamada, sin bucle');

      // Ya reparado: el siguiente ciclo es un no-op limpio...
      final r2 = await svc.sincronizar();
      expect(r2.exito, isTrue);
      expect(r2.recibidos, 0);
      expect(await outbox.leerCursor(), '3');

      // ...y un cambio nuevo de la otra caja SÍ llega, que es lo que la
      // reparación tenía que devolvernos.
      transporte.sembrarCambioAjeno(_cambioAjeno(9));
      final r3 = await svc.sincronizar();

      expect(r3.recibidos, 1);
      expect(await outbox.leerCursor(), '4');
    });

    test('cursor basura equivale a cursor 0 (el server lo trata así)', () async {
      // `long.TryParse(cursor, out c) && c > 0 ? c : 0L`: no numérico, vacío o
      // negativo => desde el principio. Se re-baja todo y el LWW lo hace inocuo.
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      for (var i = 0; i < 3; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }
      await outbox.guardarCursor('-42');

      final r = await _servicio(outbox, transporte).sincronizar();

      expect(r.recibidos, 3);
      expect(transporte.cursoresAcotados, 0);
      expect(await outbox.leerCursor(), '3');
    });

    test('pagina hasta vaciar cuando el backend corta en maxPorPull', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria()..maxPorPull = 2;
      for (var i = 0; i < 5; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(maxPorPull: 2))
          .sincronizar();

      expect(r.recibidos, 5);
      expect(transporte.llamadasPull, greaterThanOrEqualTo(3));
      expect(await outbox.leerCursor(), '5');
    });

    test('el cursor se guarda DESPUÉS de aplicar cada página', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria()..maxPorPull = 2;
      for (var i = 0; i < 4; i++) {
        transporte.sembrarCambioAjeno(_cambioAjeno(i));
      }

      await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(maxPorPull: 2))
          .sincronizar();

      // Progresión monótona: 2, 4. Nunca un salto que se salte una página.
      expect(outbox.cursoresGuardados.take(2).toList(), ['2', '4']);
    });
  });

  // ===========================================================================
  group('PULL — defensa contra eco', () {
    test('ignora los cambios cuyo origen es este mismo dispositivo', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria(); // sin filtro server-side
      outbox.encolarVarios(
          List.generate(3, (_) => eventoDePrueba(origen: 'M01')));

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(origen: 'M01'))
          .sincronizar();

      expect(r.enviados, 3);
      expect(r.ignoradosPorEco, 3,
          reason: 'el backend de hoy nos devuelve lo que acabamos de subir');
      expect(r.recibidos, 0);
      expect(outbox.aplicados, isEmpty,
          reason: 're-aplicar lo propio puede pisar una edición local más nueva');
      expect(await outbox.leerCursor(), '3',
          reason: 'el cursor avanza igual: el eco se consume, no se re-pide');
    });

    test('mezcla propia + ajena: aplica solo lo ajeno', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      outbox.encolarVarios(
          List.generate(3, (_) => eventoDePrueba(origen: 'M01')));
      transporte.sembrarCambioAjeno(_cambioAjeno(90, origen: 'C01'));
      transporte.sembrarCambioAjeno(_cambioAjeno(91, origen: 'C01'));

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(origen: 'M01'))
          .sincronizar();

      expect(r.recibidos, 2);
      expect(r.ignoradosPorEco, 3);
      expect(outbox.aplicados.every((c) => c.origenCajaId == 'C01'), isTrue);
    });

    test('el filtro es insensible a mayúsculas', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria();
      transporte.sembrarCambioAjeno(_cambioAjeno(1, origen: 'm01'));

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(origen: 'M01'))
          .sincronizar();

      expect(r.ignoradosPorEco, 1);
      expect(r.recibidos, 0);
    });

    test('con el filtro server-side activo el resultado es el mismo', () async {
      // Con `GET /sync/pull?origen=M01`, `ignoradosPorEco` cae a 0 y nada más
      // cambia. Es la prueba de que la defensa local no estorba.
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria(excluirOrigen: 'M01');
      outbox.encolarVarios(
          List.generate(3, (_) => eventoDePrueba(origen: 'M01')));

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(origen: 'M01'))
          .sincronizar();

      expect(r.enviados, 3);
      expect(r.ignoradosPorEco, 0);
      expect(r.recibidos, 0);
      expect(outbox.aplicados, isEmpty);
    });

    test(
        'una página VACÍA por el filtro server-side no corta la paginación',
        () async {
      // Regresión del contrato cerrado: el cursor avanza sobre la ventana SIN
      // filtrar, así que una página puede volver vacía y tener más detrás.
      // Cortar en "cambios vacíos" dejaría los cambios ajenos sin bajar hasta
      // el siguiente ciclo.
      final outbox = AlmacenOutboxEnMemoria();
      final transporte = TransporteSyncEnMemoria(excluirOrigen: 'M01')
        ..maxPorPull = 2;
      // Primera ventana entera nuestra (se filtra completa), segunda ajena.
      transporte.sembrarCambioAjeno(_cambioAjeno(1, origen: 'M01'));
      transporte.sembrarCambioAjeno(_cambioAjeno(2, origen: 'M01'));
      transporte.sembrarCambioAjeno(_cambioAjeno(3, origen: 'C01'));
      transporte.sembrarCambioAjeno(_cambioAjeno(4, origen: 'C01'));

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(origen: 'M01', maxPorPull: 2))
          .sincronizar();

      expect(r.recibidos, 2,
          reason: 'los cambios de la otra caja llegan en ESTE ciclo');
      expect(transporte.llamadasPull, 3);
      expect(await outbox.leerCursor(), '4');
    });
  });

  // ===========================================================================
  group('PUSH — evento venenoso', () {
    test('se aísla por bisección y no bloquea a los inocentes del lote',
        () async {
      final outbox = AlmacenOutboxEnMemoria();
      final eventos = List.generate(5, (_) => eventoDePrueba());
      outbox.encolarVarios(eventos);

      final venenoso = eventos[2].id;
      final transporte = TransporteSyncEnMemoria()..venenosos.add(venenoso);

      final svc = _servicio(outbox, transporte,
          opciones: opcionesDePrueba(tamanoLote: 5, maxIntentos: 2));

      final r1 = await svc.sincronizar();

      expect(r1.enviados, 4, reason: 'los 4 sanos suben en el MISMO ciclo');
      expect(outbox.idsEnviados, hasLength(4));
      expect(outbox.idsPendientes, [venenoso]);
      expect(outbox.intentosDe(venenoso), 1);
      expect(outbox.idsDeadLetter, isEmpty);
    });

    test('tras maxIntentos va a dead-letter y la cola queda libre', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final eventos = List.generate(3, (_) => eventoDePrueba());
      outbox.encolarVarios(eventos);

      final venenoso = eventos[0].id;
      final transporte = TransporteSyncEnMemoria()..venenosos.add(venenoso);

      final svc = _servicio(outbox, transporte,
          opciones: opcionesDePrueba(tamanoLote: 10, maxIntentos: 2));

      await svc.sincronizar(); // intento 1
      final r2 = await svc.sincronizar(); // intento 2 -> dead-letter

      expect(r2.enviadosADeadLetter, 1);
      expect(outbox.idsDeadLetter, [venenoso]);
      expect(outbox.idsPendientes, isEmpty,
          reason: 'la cola drena: un evento venenoso no la bloquea');

      // Y a partir de aquí una venta nueva sube sin arrastrar el problema.
      final nueva = eventoDePrueba();
      outbox.encolar(nueva);
      final r3 = await svc.sincronizar();

      expect(r3.exito, isTrue);
      expect(r3.enviados, 1);
      expect(outbox.idsEnviados, contains(nueva.id));
    });

    test('un solo ciclo no se cuelga leyendo el mismo lote una y otra vez',
        () async {
      // Sin el registro de "ya intentados en este ciclo", el evento venenoso
      // sigue pendiente y `leerPendientes` lo devolvería para siempre.
      final outbox = AlmacenOutboxEnMemoria();
      final e = eventoDePrueba();
      outbox.encolar(e);
      final transporte = TransporteSyncEnMemoria()..venenosos.add(e.id);

      final r = await _servicio(outbox, transporte,
              opciones: opcionesDePrueba(tamanoLote: 1, maxIntentos: 10))
          .sincronizar()
          .timeout(const Duration(seconds: 5));

      expect(r.enviados, 0);
      expect(transporte.llamadasPush, 1);
    });
  });

  // ===========================================================================
  group('403 — licencia sin flag cloud_sync', () {
    test('aborta el ciclo sin castigar el outbox', () async {
      final outbox = AlmacenOutboxEnMemoria();
      outbox.encolarVarios(List.generate(4, (_) => eventoDePrueba()));
      final transporte = TransporteSyncEnMemoria()
        ..falloPermanente = TipoFalloSync.sinPermiso;

      final r = await _servicio(outbox, transporte).sincronizar();

      expect(r.exito, isFalse);
      expect(r.motivo, MotivoFalloSync.sinPermisoCloud);
      expect(r.mensaje, contains('PagoYa Cloud'));
      expect(transporte.llamadasPull, 0, reason: 'ni se intenta el pull');
      expect(outbox.idsDeadLetter, isEmpty);
      expect(outbox.idsPendientes, hasLength(4),
          reason: 'la cola se conserva intacta para el día que compre el tier');
      expect(outbox.intentosDe(outbox.idsPendientes.first), 0,
          reason: 'no es culpa del evento: no gasta intentos');
    });

    test('401 marca token inválido, tampoco quema intentos', () async {
      final outbox = AlmacenOutboxEnMemoria()..encolar(eventoDePrueba());
      final transporte = TransporteSyncEnMemoria()
        ..falloPermanente = TipoFalloSync.autenticacion;

      final r = await _servicio(outbox, transporte).sincronizar();

      expect(r.motivo, MotivoFalloSync.tokenInvalido);
      expect(outbox.intentosDe(outbox.idsPendientes.first), 0);
    });

    test('sin el flag, la fábrica devuelve el Null Object y no toca la red',
        () async {
      final outbox = AlmacenOutboxEnMemoria()..encolar(eventoDePrueba());
      final transporte = TransporteSyncEnMemoria();

      final svc = FabricaSync.crear(
        featuresVerificadas: {'invoicing'}, // sin cloud_sync
        outbox: outbox,
        opciones: opcionesDePrueba(),
        transporte: transporte,
      );

      expect(svc, isA<ServicioSyncDeshabilitado>());
      expect(svc.sincronizacionHabilitada, isFalse);

      final r = await svc.sincronizar();

      expect(r.exito, isFalse);
      expect(r.motivo, MotivoFalloSync.sinPermisoCloud);
      expect(transporte.llamadasPush, 0);
      expect(transporte.llamadasPull, 0);
      expect(outbox.idsPendientes, hasLength(1),
          reason: 'el outbox se sigue llenando: al comprar Cloud sube todo');
    });

    test('403 por asiento revocado es OTRO problema y OTRO mensaje', () async {
      // `DELETE /devices/{id}` desde el panel admin. El token sigue siendo
      // criptográficamente válido hasta `exp`: esto SOLO se sabe por la
      // respuesta del server.
      final outbox = AlmacenOutboxEnMemoria();
      outbox.encolarVarios(List.generate(3, (_) => eventoDePrueba()));
      final avisos = <String>[];
      final transporte = TransporteSyncEnMemoria()
        ..falloPermanente = TipoFalloSync.asientoRevocado;

      final svc = ServicioSyncNube(
        outbox: outbox,
        transporte: transporte,
        opciones: opcionesDePrueba(),
        registrador: avisos.add,
      );

      final r = await svc.sincronizar();

      expect(r.motivo, MotivoFalloSync.dispositivoRevocado);
      expect(r.mensaje, contains('desvinculado'));
      expect(r.mensaje, isNot(contains('PagoYa Cloud')),
          reason: 'no es un problema de plan: no se le vende nada al dueño');
      expect(transporte.llamadasPull, 0);
      expect(outbox.idsPendientes, hasLength(3));
      expect(outbox.intentosDe(outbox.idsPendientes.first), 0);
      expect(avisos.any((a) => a.contains('revocado')), isTrue);
      expect(esMotivoBloqueante(r.motivo), isTrue);
    });

    test('con el flag, la fábrica devuelve el motor real', () {
      final svc = FabricaSync.crear(
        featuresVerificadas: {'cloud_sync', 'multi_site'},
        outbox: AlmacenOutboxEnMemoria(),
        opciones: opcionesDePrueba(),
        transporte: TransporteSyncEnMemoria(),
      );

      expect(svc, isA<ServicioSyncNube>());
      expect(svc.sincronizacionHabilitada, isTrue);
    });
  });

  // ===========================================================================
  group('Catálogo de entidades', () {
    test('es el mismo contrato cerrado que el backend', () {
      // `PagoYa.Api.Servicios.EntidadesSync.Catalogo`. Si esto cambia sin
      // cambiar los otros dos lados, los eventos viajan y no los aplica nadie.
      expect(EntidadesSync.catalogo, {
        'producto',
        'venta',
        'caja',
        'movimiento_caja',
        'inventario',
        'mesa',
        'pedido',
        'pedido_linea',
        'habitacion',
        'estadia_habitacion',
      });
      expect(EntidadesSync.esConocida('pedido_linea'), isTrue);
      expect(EntidadesSync.esConocida('pedidos'), isFalse);
      expect(EntidadesSync.esConocida(null), isFalse);
    });

    test('entidadesDesconocidas del push se registra como alarma', () async {
      final outbox = AlmacenOutboxEnMemoria()
        ..encolar(eventoDePrueba(entidad: 'venta'))
        ..encolar(eventoDePrueba(entidad: 'comanda_v2')); // nombre divergente
      final avisos = <String>[];

      final svc = ServicioSyncNube(
        outbox: outbox,
        transporte: TransporteSyncEnMemoria(),
        opciones: opcionesDePrueba(),
        registrador: avisos.add,
      );

      final r = await svc.sincronizar();

      // El server los guarda igual: no se pierden datos del cliente.
      expect(r.exito, isTrue);
      expect(r.enviados, 2);
      expect(r.entidadesDesconocidas, contains('comanda_v2'));
      expect(svc.estadoActual.entidadesDesconocidas, contains('comanda_v2'));
      expect(avisos.any((a) => a.contains('comanda_v2')), isTrue,
          reason: 'sin log visible, la divergencia se descubre en producción');
    });
  });

  // ===========================================================================
  group('REGLA CRÍTICA — nunca propaga excepción', () {
    test('un transporte que revienta se convierte en ResultadoSync fallido',
        () async {
      final outbox = AlmacenOutboxEnMemoria()..encolar(eventoDePrueba());

      final r = await _servicio(outbox, TransporteQueLanza()).sincronizar();

      expect(r.exito, isFalse);
      expect(r.motivo, MotivoFalloSync.desconocido);
      expect(r.mensaje, isNotNull);
    });

    test('el pull que revienta tampoco escapa', () async {
      final outbox = AlmacenOutboxEnMemoria(); // sin pendientes: va directo al pull

      final r = await _servicio(outbox, TransporteQueLanza()).sincronizar();

      expect(r.exito, isFalse);
    });
  });

  // ===========================================================================
  group('Estado y single-flight', () {
    test('dos disparos simultáneos comparten un solo ciclo', () async {
      final outbox = AlmacenOutboxEnMemoria();
      outbox.encolarVarios(List.generate(3, (_) => eventoDePrueba()));
      final transporte = TransporteSyncEnMemoria();
      final svc = _servicio(outbox, transporte);

      final futuros = await Future.wait([svc.sincronizar(), svc.sincronizar()]);

      expect(transporte.llamadasPush, 1,
          reason: 'abrir la app y reconectar a la vez no duplica tráfico');
      expect(futuros[0].enviados, futuros[1].enviados);
    });

    test('el estado publica pendientes, dead-letter y última sync', () async {
      final outbox = AlmacenOutboxEnMemoria();
      final eventos = List.generate(3, (_) => eventoDePrueba());
      outbox.encolarVarios(eventos);
      final transporte = TransporteSyncEnMemoria()..venenosos.add(eventos[1].id);

      final svc = _servicio(outbox, transporte,
          opciones: opcionesDePrueba(tamanoLote: 10, maxIntentos: 1));

      await svc.sincronizar();

      expect(svc.estadoActual.habilitada, isTrue);
      expect(svc.estadoActual.sincronizando, isFalse);
      expect(svc.estadoActual.ultimaSyncExitosa, isTrue);
      expect(svc.estadoActual.ultimaSyncUtc, isNotNull);
      expect(svc.estadoActual.pendientes, 0);
      expect(svc.estadoActual.enDeadLetter, 1);
      expect(svc.estadoActual.alDia, isTrue);
    });

    test('tras un fallo de red el estado no marca "al día"', () async {
      final outbox = AlmacenOutboxEnMemoria()..encolar(eventoDePrueba());
      final transporte = TransporteSyncEnMemoria()
        ..fallosPushEncolados.add(TipoFalloSync.red);
      final svc = _servicio(outbox, transporte);

      await svc.sincronizar();

      expect(svc.estadoActual.ultimaSyncExitosa, isFalse);
      expect(svc.estadoActual.pendientes, 1);
      expect(svc.estadoActual.alDia, isFalse);
    });
  });
}

// =============================================================================

CambioRemoto _cambioAjeno(int i, {String origen = 'C01'}) => CambioRemoto(
      entidad: 'venta',
      entidadId: 'ajena-$i',
      operacion: 'INSERT',
      payloadJson: '{"Id":"ajena-$i"}',
      actualizadoUtc: DateTime.utc(2026, 2, 1).add(Duration(minutes: i)),
      origenCajaId: origen,
    );
