@Timeout(Duration(minutes: 5))

/// Tests del orden de validación completo (firma → dispositivo → expiración
/// con gracia) y del gate de arranque.
///
/// ⚠ NO EJECUTADOS: el entorno donde se escribieron no tiene shell disponible
/// (`docs/MOBILE-ARQUITECTURA.md` §9). Correr con `dart test test/licencia`
/// desde `mobile/packages/pagoya_core`.
library;

import 'package:pagoya_core/licencia/licencia.dart';
import 'package:test/test.dart';

import 'dobles.dart';
import 'vectores.dart';

void main() {
  late AlmacenSeguroEnMemoria seguro;
  late MetaLicenciaEnMemoria meta;

  ServicioLicencia crearServicio({
    String? tokenGuardado,
    String? claveGuardada,
    String idDispositivo = idDispositivoPropio,
    DateTime? ahora,
    bool identidadRota = false,
  }) {
    seguro = tokenGuardado == null
        ? AlmacenSeguroEnMemoria()
        : AlmacenSeguroEnMemoria.conToken(tokenGuardado, clave: claveGuardada);

    return ServicioLicencia(
      validador: validadorDePruebas(),
      identidad: IdentidadFalsa(idDispositivo, falla: identidadRota),
      almacen: AlmacenLicenciaSegura(seguro),
      reloj: RelojAuditadoMeta(
        meta,
        ahoraDelSistema: () => ahora ?? ahoraFija,
      ),
      meta: meta,
    );
  }

  setUp(() => meta = MetaLicenciaEnMemoria());

  group('Gate de arranque', () {
    test('sin token instalado NO entra al POS, ni siquiera en Base', () async {
      final EstadoLicencia e = await crearServicio().cargarLicenciaLocal();

      expect(e.estaActivada, isFalse,
          reason: 'CLAUDE.md: todas las tiers exigen activación');
      expect(e.tier, TierLicencia.base);
      expect(e.featuresHabilitadas, isEmpty);
      expect(e.motivoDegradacion, MotivoDegradacion.sinToken);
    });

    test('con token Base perpetuo auténtico SÍ entra al POS, sin premium',
        () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadBasePerpetua),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.esValida, isTrue);
      expect(e.tier, TierLicencia.base);
      expect(e.expiraUtc, isNull);
      for (final CaracteristicaLicencia c in CaracteristicaLicencia.values) {
        expect(e.tieneCaracteristica(c), isFalse);
      }
    });

    test('un Keystore ilegible manda al gate en vez de reventar', () async {
      final ServicioLicencia s = ServicioLicencia(
        validador: validadorDePruebas(),
        identidad: const IdentidadFalsa(idDispositivoPropio),
        almacen: AlmacenLicenciaSegura(const AlmacenSeguroRoto()),
        reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        meta: meta,
      );

      final EstadoLicencia e = await s.cargarLicenciaLocal();
      expect(e.estaActivada, isFalse);
      expect(e.motivoDegradacion, MotivoDegradacion.sinToken);
    });
  });

  group('1) Firma', () {
    test('token manipulado degrada a Base seguro', () async {
      final String malo =
          manipularUnByteDelPayload(firmarToken(payloadFacturadorVigente));
      final EstadoLicencia e =
          await crearServicio(tokenGuardado: malo).cargarLicenciaLocal();

      expect(e.estaActivada, isFalse);
      expect(e.motivoDegradacion, MotivoDegradacion.firmaInvalida);
      expect(e.featuresHabilitadas, isEmpty,
          reason: 'nunca habilitar premium por defecto');
    });

    test('basura en el almacén degrada a Base sin lanzar', () async {
      for (final String basura in <String>['   ', 'no-es-un-token', 'a.b']) {
        final EstadoLicencia e =
            await crearServicio(tokenGuardado: basura).cargarLicenciaLocal();
        expect(e.estaActivada, isFalse, reason: 'entrada: "$basura"');
      }
    });
  });

  group('2) Dispositivo', () {
    test('token emitido para OTRO dispositivo degrada a Base', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadOtroDispositivo),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isFalse);
      expect(e.motivoDegradacion, MotivoDegradacion.otroDispositivo);
      expect(e.motivo, contains('otro dispositivo'));
    });

    test('hwid vacío = licencia no atada: valida en cualquier dispositivo',
        () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadSinVinculo),
        idDispositivo: idDispositivoAjeno,
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.tieneCaracteristica(CaracteristicaLicencia.cloudSync), isTrue);
      expect(e.idDispositivoVinculado, isNull);
    });

    test('la comparación ignora mayúsculas (paridad con el OrdinalIgnoreCase '
        'del escritorio)', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadFacturadorVigente),
        idDispositivo: idDispositivoPropio.toUpperCase(),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
    });

    test('si no se puede leer la identidad local, degrada a Base', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadFacturadorVigente),
        identidadRota: true,
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isFalse);
      expect(e.motivoDegradacion, MotivoDegradacion.otroDispositivo);
    });
  });

  group('3) Expiración y grace period de 7 días', () {
    test('vigente: activa, sin gracia', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadFacturadorVigente),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.enPeriodoGracia, isFalse);
      expect(e.tier, TierLicencia.facturadorPro);
      expect(e.tieneCaracteristica(CaracteristicaLicencia.invoicing), isTrue);
      expect(e.diasParaExpirar(ahoraFija), 30);
    });

    test('expirada hace 3 días: sigue operando DENTRO de la gracia', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadCloudEnGracia),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue,
          reason: 'no se corta al negocio en caliente');
      expect(e.enPeriodoGracia, isTrue);
      expect(e.tier, TierLicencia.cloud);
      expect(e.tieneCaracteristica(CaracteristicaLicencia.cloudSync), isTrue);
      expect(e.motivo, contains('gracia'));
    });

    test('borde: 7 días exactos sigue en gracia, 7 días + 1 s no', () async {
      final DateTime expira = DateTime.fromMillisecondsSinceEpoch(
        epochExpiradoEnGracia * 1000,
        isUtc: true,
      );
      final String token = firmarToken(payloadCloudEnGracia);

      meta = MetaLicenciaEnMemoria();
      final EstadoLicencia dentro = await crearServicio(
        tokenGuardado: token,
        ahora: expira.add(const Duration(days: 7)),
      ).cargarLicenciaLocal();
      expect(dentro.estaActivada, isTrue);
      expect(dentro.enPeriodoGracia, isTrue);

      meta = MetaLicenciaEnMemoria();
      final EstadoLicencia fuera = await crearServicio(
        tokenGuardado: token,
        ahora: expira.add(const Duration(days: 7, seconds: 1)),
      ).cargarLicenciaLocal();
      expect(fuera.estaActivada, isFalse);
      expect(fuera.motivoDegradacion, MotivoDegradacion.expirada);
    });

    test('expirada hace 10 días: gracia vencida, degrada a Base', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadCloudFueraDeGracia),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isFalse);
      expect(e.motivoDegradacion, MotivoDegradacion.expirada);
      expect(e.featuresHabilitadas, isEmpty);
      expect(e.tier, TierLicencia.base);
    });

    test('perpetua nunca expira, por muy adelantado que vaya el reloj',
        () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadBasePerpetua),
        ahora: DateTime.utc(2099),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.enPeriodoGracia, isFalse);
    });
  });

  group('Orden de validación', () {
    test('manipulado Y de otro dispositivo → falla por FIRMA primero', () async {
      final String malo =
          manipularUnByteDelPayload(firmarToken(payloadOtroDispositivo));
      final EstadoLicencia e =
          await crearServicio(tokenGuardado: malo).cargarLicenciaLocal();

      expect(e.motivoDegradacion, MotivoDegradacion.firmaInvalida,
          reason: 'firma → dispositivo → expiración, igual que LicenseService');
    });

    test('expirado Y de otro dispositivo → falla por DISPOSITIVO primero',
        () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadOtroDispositivo),
        ahora: DateTime.utc(2099),
      ).cargarLicenciaLocal();

      expect(e.motivoDegradacion, MotivoDegradacion.otroDispositivo);
    });
  });

  group('Claims de asiento (docs/LICENSE-TOKEN.md §4.1)', () {
    test('device_id y device_prefix se leen y se persisten en `meta`',
        () async {
      final ServicioLicencia s = crearServicio();
      final EstadoLicencia e =
          await s.activarLicencia(firmarToken(payloadFacturadorVigente));

      expect(e.estaActivada, isTrue);
      expect(e.idAsiento, idAsiento);
      expect(e.prefijoDispositivo, prefijoAsiento);
      expect(
        meta.datos[ClavesMetaLicencia.prefijoDispositivo],
        prefijoAsiento,
        reason: 'flutter-datos lo necesita para los correlativos M01-000123',
      );
      expect(meta.datos[ClavesMetaLicencia.idAsiento], idAsiento);
    });

    test('un token SIN esos claims sigue siendo válido (compatibilidad)',
        () async {
      // Regla dura: los claims aditivos son enriquecimiento, no requisito.
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadBasePerpetua),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.idAsiento, isNull);
      expect(e.prefijoDispositivo, isNull);
      expect(meta.datos[ClavesMetaLicencia.prefijoDispositivo], isNull,
          reason: 'nunca se inventa un prefijo: lo asigna el server');
    });

    test('un claim desconocido no rompe el parseo', () async {
      final EstadoLicencia e = await crearServicio(
        tokenGuardado: firmarToken(payloadConClaimFuturo),
      ).cargarLicenciaLocal();

      expect(e.estaActivada, isTrue);
      expect(e.tieneCaracteristica(CaracteristicaLicencia.cloudSync), isTrue);
    });
  });

  group('activarLicencia / desactivar', () {
    test('persiste solo si el token es auténtico', () async {
      final ServicioLicencia s = crearServicio();
      final EstadoLicencia ok =
          await s.activarLicencia(firmarToken(payloadFacturadorVigente));

      expect(ok.estaActivada, isTrue);
      expect(seguro.datos[ClavesSeguras.tokenLicencia], isNotNull);
    });

    test('una activación fallida NO sobrescribe una licencia buena', () async {
      final String bueno = firmarToken(payloadFacturadorVigente);
      final ServicioLicencia s = crearServicio(tokenGuardado: bueno);

      final EstadoLicencia e =
          await s.activarLicencia(manipularUnByteDelPayload(bueno));

      expect(e.estaActivada, isFalse);
      expect(seguro.datos[ClavesSeguras.tokenLicencia], bueno,
          reason: 'el token bueno sigue ahí');
    });

    test('desactivar borra token, clave y datos de asiento', () async {
      final ServicioLicencia s = crearServicio(
        tokenGuardado: firmarToken(payloadFacturadorVigente),
        claveGuardada: 'PAGOYA-AAAA-BBBB-CCCC-DDDD',
      );
      await s.cargarLicenciaLocal();
      await s.activarLicencia(firmarToken(payloadFacturadorVigente));
      expect(meta.datos[ClavesMetaLicencia.prefijoDispositivo], isNotNull);

      await s.desactivar();

      expect(s.estadoActual.estaActivada, isFalse);
      expect(seguro.datos[ClavesSeguras.tokenLicencia], isNull);
      expect(seguro.datos[ClavesSeguras.claveLicencia], isNull);
      expect(meta.datos[ClavesMetaLicencia.prefijoDispositivo], isNull);
    });

    test('el stream `cambios` publica cada transición', () async {
      final ServicioLicencia s = crearServicio();
      final List<bool> activaciones = <bool>[];
      final sub = s.cambios.listen((EstadoLicencia e) {
        activaciones.add(e.estaActivada);
      });

      await s.cargarLicenciaLocal(); // false
      await s.activarLicencia(firmarToken(payloadBasePerpetua)); // true
      await s.desactivar(); // false
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(activaciones, <bool>[false, true, false]);
    });
  });

  group('Feature gating', () {
    test('los flags canónicos coinciden con los del token', () {
      expect(Flags.invoicing, 'invoicing');
      expect(Flags.cloudSync, 'cloud_sync');
      expect(Flags.multiSite, 'multi_site');
      expect(CaracteristicaLicencia.cloudSync.flag, 'cloud_sync');
    });

    test('el estado Base seguro no habilita ninguna característica', () {
      final EstadoLicencia e = EstadoLicencia.baseSegura();
      for (final CaracteristicaLicencia c in CaracteristicaLicencia.values) {
        expect(e.tieneCaracteristica(c), isFalse);
      }
    });

    test('mapearTier degrada a Base ante un tier desconocido', () {
      expect(mapearTier('cloud'), TierLicencia.cloud);
      expect(mapearTier('facturador'), TierLicencia.facturadorPro);
      expect(mapearTier('facturador_pro'), TierLicencia.facturadorPro);
      expect(mapearTier('FACTURADOR'), TierLicencia.facturadorPro);
      expect(mapearTier('enterprise'), TierLicencia.base);
      expect(mapearTier(null), TierLicencia.base);
    });
  });
}
