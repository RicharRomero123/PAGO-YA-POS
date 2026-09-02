/// Tests de la política de red móvil y del planificador.
///
/// Lo que se protege aquí es la batería y el plan de datos del dueño de la
/// bodega, y la promesa de que una venta se sube en cuanto haya por dónde.
library;

import 'dart:async';

import 'package:pagoya_core/nube/nube.dart';
import 'package:test/test.dart';

import 'dobles_sync.dart';

class _SensorFalso implements SensorConectividad {
  _SensorFalso(this.tipo);

  TipoRed tipo;
  final StreamController<TipoRed> _ctrl = StreamController<TipoRed>.broadcast();

  @override
  Future<TipoRed> tipoActual() async => tipo;

  @override
  Stream<TipoRed> get cambios => _ctrl.stream;

  void emitir(TipoRed nueva) {
    tipo = nueva;
    _ctrl.add(nueva);
  }

  Future<void> cerrar() => _ctrl.close();
}

void main() {
  setUp(reiniciarContadorEventos);

  // ===========================================================================
  group('PoliticaRedMovil — intervalo adaptativo', () {
    const politica = PoliticaRedMovil();

    test('caja abierta en primer plano es el único caso de cadencia rápida', () {
      final rapido = politica.intervalo(const ContextoSync(
          modo: ModoApp.primerPlano, red: TipoRed.wifi, cajaAbierta: true));
      final lento = politica.intervalo(const ContextoSync(
          modo: ModoApp.primerPlano, red: TipoRed.wifi, cajaAbierta: false));
      final background = politica.intervalo(const ContextoSync(
          modo: ModoApp.segundoPlano, red: TipoRed.wifi, cajaAbierta: true));

      expect(rapido, const Duration(minutes: 1));
      expect(lento, greaterThan(rapido));
      expect(background, greaterThan(lento));
    });

    test('en background NO se acelera aunque la caja esté abierta', () {
      // Fabricantes agresivos: insistir en background no consigue más sync,
      // solo consigue que MIUI mate el proceso antes.
      final conCaja = politica.intervalo(const ContextoSync(
          modo: ModoApp.segundoPlano, red: TipoRed.wifi, cajaAbierta: true));
      final sinCaja = politica.intervalo(const ContextoSync(
          modo: ModoApp.segundoPlano, red: TipoRed.wifi, cajaAbierta: false));

      expect(conCaja, sinCaja);
    });

    test('el backoff tras fallos crece y se acota a una hora', () {
      const ctx = ContextoSync(
          modo: ModoApp.primerPlano, red: TipoRed.wifi, cajaAbierta: true);

      final uno = politica.intervaloTrasFallo(ctx, 1);
      final tres = politica.intervaloTrasFallo(ctx, 3);
      final muchos = politica.intervaloTrasFallo(ctx, 99);

      expect(uno, const Duration(minutes: 2));
      expect(tres, greaterThan(uno));
      expect(muchos, lessThanOrEqualTo(const Duration(hours: 1)));
    });
  });

  // ===========================================================================
  group('PoliticaRedMovil — decisión', () {
    const politica = PoliticaRedMovil();

    test('sin red no se gasta ni la sonda', () {
      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.primerPlano, red: TipoRed.ninguna, pendientes: 10),
        opcionesDePrueba(),
      );

      expect(d.decision, DecisionSync.esperarRed);
      expect(d.mensaje, contains('Sin conexión'));
    });

    test('lote grande en datos móviles sin permiso: espera al Wi-Fi', () {
      const opciones = OpcionesSync(
        origenCajaId: 'M01',
        permitirDatosMoviles: false,
        maxEventosEnDatosMoviles: 100,
      );

      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.primerPlano, red: TipoRed.movil, pendientes: 342),
        opciones,
      );

      expect(d.decision, DecisionSync.esperarPermisoDatos);
      expect(d.mensaje, contains('342'),
          reason: 'el mensaje tiene que decir cuántas operaciones esperan');
    });

    test('lote pequeño en datos móviles sí sube aunque no haya permiso', () {
      const opciones = OpcionesSync(
        origenCajaId: 'M01',
        permitirDatosMoviles: false,
        maxEventosEnDatosMoviles: 100,
      );

      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.primerPlano, red: TipoRed.movil, pendientes: 3),
        opciones,
      );

      expect(d.procede, isTrue,
          reason: 'tres tickets no justifican dejar la venta sin respaldo');
    });

    test('con permiso explícito, los datos móviles suben cualquier lote', () {
      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.primerPlano, red: TipoRed.movil, pendientes: 5000),
        opcionesDePrueba(), // permitirDatosMoviles: true por defecto
      );

      expect(d.procede, isTrue);
    });

    test('en background sin pendientes no se despierta la radio', () {
      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.segundoPlano, red: TipoRed.wifi, pendientes: 0),
        opcionesDePrueba(),
      );

      expect(d.decision, DecisionSync.nadaQueHacer);
    });

    test('en primer plano sin pendientes SÍ se hace pull (la otra caja vendió)',
        () {
      final d = politica.decidir(
        const ContextoSync(
            modo: ModoApp.primerPlano, red: TipoRed.wifi, pendientes: 0),
        opcionesDePrueba(),
      );

      expect(d.procede, isTrue);
    });
  });

  // ===========================================================================
  group('PlanificadorSync', () {
    late AlmacenOutboxEnMemoria outbox;
    late TransporteSyncEnMemoria transporte;
    late _SensorFalso sensor;
    PlanificadorSync? plan;

    setUp(() {
      outbox = AlmacenOutboxEnMemoria();
      transporte = TransporteSyncEnMemoria();
      sensor = _SensorFalso(TipoRed.wifi);
    });

    tearDown(() async {
      await plan?.detener();
      await sensor.cerrar();
    });

    PlanificadorSync crear(ServicioSync svc, {OpcionesSync? opciones}) =>
        plan = PlanificadorSync(
          servicio: svc,
          opciones: opciones ?? opcionesDePrueba(),
          sensor: sensor,
          sonda: transporte.hayInternet,
        );

    ServicioSyncNube motor({OpcionesSync? opciones}) => ServicioSyncNube(
          outbox: outbox,
          transporte: transporte,
          opciones: opciones ?? opcionesDePrueba(),
        );

    test('"Sincronizar ahora" fuerza el ciclo aunque el sensor diga que no hay red',
        () async {
      outbox.encolar(eventoDePrueba());
      sensor.tipo = TipoRed.ninguna;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora();

      expect(r.exito, isTrue,
          reason: 'el usuario pidió el intento: se intenta de verdad');
      expect(outbox.idsEnviados, hasLength(1));
    });

    test('sin red declarada, un disparo automático no toca la red', () async {
      outbox.encolar(eventoDePrueba());
      sensor.tipo = TipoRed.ninguna;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora(forzar: false);

      expect(r.exito, isFalse);
      expect(transporte.llamadasPush, 0);
      expect(p.ultimoMotivoOmision, contains('Sin conexión'));
    });

    test('hay wifi pero no internet real: no se intenta el ciclo', () async {
      // Portal cautivo del mercado: asocia, pero no enruta.
      outbox.encolar(eventoDePrueba());
      transporte.internet = false;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora(forzar: false);

      expect(r.exito, isFalse);
      expect(r.motivo, MotivoFalloSync.sinRed);
      expect(transporte.llamadasSonda, greaterThan(0));
      expect(transporte.llamadasPush, 0,
          reason: 'connectivity_plus dijo wifi; la sonda dijo la verdad');
    });

    test('lote grande en datos móviles sin permiso: se pospone con mensaje',
        () async {
      outbox.encolarVarios(List.generate(20, (_) => eventoDePrueba()));
      sensor.tipo = TipoRed.movil;
      final svc = motor();
      final p = crear(svc,
          opciones: const OpcionesSync(
            origenCajaId: 'M01',
            permitirDatosMoviles: false,
            maxEventosEnDatosMoviles: 5,
          ));
      await p.iniciar(sincronizarAlArrancar: false);
      await svc.refrescarContadores();

      final r = await p.sincronizarAhora(forzar: false);

      expect(r.motivo, MotivoFalloSync.datosMovilesBloqueados);
      expect(transporte.llamadasPush, 0);
      expect(p.ultimoMotivoOmision, contains('20'));
    });

    test('el Null Object no programa nada ni toca la red', () async {
      final p = crear(ServicioSyncDeshabilitado(pendientesConocidos: 7));

      await p.iniciar();
      final r = await p.sincronizarAhora();

      expect(r.exito, isFalse);
      expect(r.motivo, MotivoFalloSync.sinPermisoCloud);
      expect(transporte.llamadasPush, 0);
      expect(transporte.llamadasPull, 0);
      expect(transporte.llamadasSonda, 0);
    });

    test('la reconexión dispara una sync oportunista (con debounce)', () async {
      outbox.encolar(eventoDePrueba());
      sensor.tipo = TipoRed.ninguna;
      plan = PlanificadorSync(
        servicio: motor(),
        opciones: opcionesDePrueba(),
        sensor: sensor,
        sonda: transporte.hayInternet,
        debounceReconexion: const Duration(milliseconds: 10),
      );
      await plan!.iniciar(sincronizarAlArrancar: false);

      final esperado = plan!.resultados.first;
      sensor.emitir(TipoRed.wifi);
      sensor.emitir(TipoRed.wifi); // ráfaga: Android emite varios seguidos

      final r = await esperado.timeout(const Duration(seconds: 3));

      expect(r.exito, isTrue);
      expect(transporte.llamadasPush, 1,
          reason: 'el debounce colapsa la ráfaga en un solo ciclo');
      expect(outbox.idsEnviados, hasLength(1));
    });

    test('el cierre de caja dispara aunque el intervalo no toque', () async {
      outbox.encolar(eventoDePrueba());
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final esperado = p.resultados.first;
      p.alCerrarCaja();
      final r = await esperado.timeout(const Duration(seconds: 3));

      expect(r.exito, isTrue);
      expect(p.cajaAbierta, isFalse);
      expect(outbox.idsEnviados, hasLength(1));
    });

    test('volver a primer plano dispara y cambia el modo', () async {
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      p.alPasarASegundoPlano();
      expect(p.modo, ModoApp.segundoPlano);

      final esperado = p.resultados.first;
      p.alVolverPrimerPlano();
      await esperado.timeout(const Duration(seconds: 3));

      expect(p.modo, ModoApp.primerPlano);
      expect(transporte.llamadasPull, greaterThan(0));
    });

    test('un 403 detiene los ciclos automáticos (nada de bucle de reintentos)',
        () async {
      outbox.encolar(eventoDePrueba());
      transporte.falloPermanente = TipoFalloSync.sinPermiso;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora();

      expect(r.motivo, MotivoFalloSync.sinPermisoCloud);
      expect(p.bloqueo, MotivoFalloSync.sinPermisoCloud);

      // Un disparo oportunista posterior no vuelve a tocar la red.
      final pushesAntes = transporte.llamadasPush;
      final r2 = await p.sincronizarAhora(forzar: false);

      expect(r2.motivo, MotivoFalloSync.sinPermisoCloud);
      expect(transporte.llamadasPush, pushesAntes,
          reason: 'un 403 no mejora reintentando cada minuto');
    });

    test('el asiento revocado bloquea igual, con su propio mensaje', () async {
      outbox.encolar(eventoDePrueba());
      transporte.falloPermanente = TipoFalloSync.asientoRevocado;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora();

      expect(r.motivo, MotivoFalloSync.dispositivoRevocado);
      expect(r.mensaje, contains('desvinculado'));
      expect(p.bloqueo, MotivoFalloSync.dispositivoRevocado);
    });

    test('la licencia vencida NO bloquea: la renueva otro módulo', () async {
      // `token_expirado` lo arregla `RevalidadorLicencia` con POST /validate,
      // sin que el dueño toque nada. Si bloqueáramos, la nube se quedaría
      // muerta hasta que alguien entrara a la pantalla a pulsar un botón.
      outbox.encolar(eventoDePrueba());
      transporte.falloPermanente = TipoFalloSync.tokenExpirado;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);

      final r = await p.sincronizarAhora();

      expect(r.motivo, MotivoFalloSync.tokenExpirado);
      expect(r.mensaje, contains('venció'));
      expect(p.bloqueo, isNull, reason: 'sigue reintentando con backoff');
      expect(esMotivoBloqueante(MotivoFalloSync.tokenExpirado), isFalse);

      // Renovado el token, el siguiente intento entra solo (el transporte lo
      // lee por ProveedorToken en cada llamada).
      transporte.falloPermanente = null;
      final r2 = await p.sincronizarAhora(forzar: false);

      expect(r2.exito, isTrue);
      expect(outbox.idsEnviados, hasLength(1));
    });

    test('el botón manual desbloquea cuando el problema ya se arregló',
        () async {
      outbox.encolar(eventoDePrueba());
      transporte.falloPermanente = TipoFalloSync.sinPermiso;
      final p = crear(motor());
      await p.iniciar(sincronizarAlArrancar: false);
      await p.sincronizarAhora();
      expect(p.bloqueo, isNotNull);

      // El dueño compró el plan y vuelve a pulsar "Sincronizar ahora".
      transporte.falloPermanente = null;
      final r = await p.sincronizarAhora();

      expect(r.exito, isTrue);
      expect(p.bloqueo, isNull);
      expect(outbox.idsEnviados, hasLength(1));
    });

    test('una sonda que revienta no propaga la excepción', () async {
      outbox.encolar(eventoDePrueba());
      plan = PlanificadorSync(
        servicio: motor(),
        opciones: opcionesDePrueba(),
        sensor: sensor,
        sonda: () async => throw StateError('DNS caído'),
      );
      await plan!.iniciar(sincronizarAlArrancar: false);

      final r = await plan!.sincronizarAhora(forzar: false);

      expect(r.exito, isFalse);
      expect(transporte.llamadasPush, 0);
    });
  });
}
