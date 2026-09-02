@Timeout(Duration(minutes: 5))

/// Tests del reloj auditado (`ultimo_visto_utc` monotónico en `meta`).
///
/// ⚠ NO EJECUTADOS: el entorno donde se escribieron no tiene shell disponible.
library;

import 'package:pagoya_core/licencia/licencia.dart';
import 'package:test/test.dart';

import 'dobles.dart';
import 'vectores.dart';

void main() {
  late MetaLicenciaEnMemoria meta;

  RelojAuditadoMeta relojEn(DateTime ahora) =>
      RelojAuditadoMeta(meta, ahoraDelSistema: () => ahora);

  setUp(() => meta = MetaLicenciaEnMemoria());

  group('RelojAuditadoMeta', () {
    test('primer arranque: sin marca previa, nada sospechoso', () async {
      final RelojAuditadoMeta reloj = relojEn(ahoraFija);
      await reloj.registrarVisto();

      expect(await reloj.detectoRetroceso(), isFalse);
      expect(await reloj.ahoraUtc(), ahoraFija);
      expect(
        meta.datos[ClavesMetaLicencia.ultimoVistoUtc],
        ahoraFija.toIso8601String(),
      );
    });

    test('la marca es monotónica: no baja al retroceder el reloj', () async {
      await relojEn(ahoraFija).registrarVisto();
      await relojEn(ahoraFija.subtract(const Duration(days: 5)))
          .registrarVisto();

      expect(
        meta.datos[ClavesMetaLicencia.ultimoVistoUtc],
        ahoraFija.toIso8601String(),
        reason: 'ultimo_visto_utc solo avanza',
      );
    });

    test('un cambio de huso horario (hasta 26 h atrás) NO es sospechoso',
        () async {
      await relojEn(ahoraFija).registrarVisto();

      // El peor caso real es cruzar de UTC+14 a UTC-12: 26 h.
      for (final Duration atraso in <Duration>[
        Duration(hours: 1),
        Duration(hours: 14),
        Duration(hours: 26),
      ]) {
        final RelojAuditadoMeta reloj = relojEn(ahoraFija.subtract(atraso));
        expect(await reloj.detectoRetroceso(), isFalse,
            reason: 'atraso de $atraso');
        expect(await reloj.ahoraUtc(), ahoraFija.subtract(atraso),
            reason: 'sin piso: se respeta el reloj del usuario');
      }
    });

    test('retroceder meses SÍ es sospechoso y activa el piso', () async {
      await relojEn(ahoraFija).registrarVisto();

      final DateTime muyAtras = ahoraFija.subtract(const Duration(days: 90));
      final RelojAuditadoMeta reloj = relojEn(muyAtras);

      expect(await reloj.detectoRetroceso(), isTrue);
      expect(await reloj.ahoraUtc(), ahoraFija,
          reason: 'la expiración se evalúa con el piso, no con el reloj falso');

      await reloj.registrarVisto();
      expect(meta.datos[ClavesMetaLicencia.ultimoRetrocesoUtc], isNotNull);
      expect(meta.datos[ClavesMetaLicencia.ultimoVistoUtc],
          ahoraFija.toIso8601String(),
          reason: 'el retroceso no baja la marca');
    });

    test('la marca no se envenena con un salto absurdo hacia adelante',
        () async {
      await relojEn(ahoraFija).registrarVisto();

      // El usuario pone el reloj en 2099 y luego lo devuelve a la normalidad.
      await relojEn(DateTime.utc(2099)).registrarVisto();

      expect(
        DateTime.parse(meta.datos[ClavesMetaLicencia.ultimoVistoUtc]!),
        ahoraFija.add(RelojAuditadoMeta.maxSaltoAdelante),
        reason: 'la marca se topa en +400 días, no salta a 2099',
      );
    });

    test('RelojAuditadoSimple nunca marca retroceso', () async {
      final RelojAuditadoSimple reloj = RelojAuditadoSimple(() => ahoraFija);
      await reloj.registrarVisto();

      expect(await reloj.detectoRetroceso(), isFalse);
      expect(await reloj.ahoraUtc(), ahoraFija);
    });
  });

  group('Reloj manipulado + licencia', () {
    ServicioLicencia servicioEn(String token, DateTime ahora) =>
        ServicioLicencia(
          validador: validadorDePruebas(),
          identidad: const IdentidadFalsa(idDispositivoPropio),
          almacen: AlmacenLicenciaSegura(
            AlmacenSeguroEnMemoria.conToken(token),
          ),
          reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahora),
          meta: meta,
        );

    test('retrasar el reloj NO resucita una licencia fuera de gracia',
        () async {
      final String token = firmarToken(payloadCloudFueraDeGracia);

      // 1) Con la hora real: expirada y fuera de gracia.
      final EstadoLicencia real =
          await servicioEn(token, ahoraFija).cargarLicenciaLocal();
      expect(real.estaActivada, isFalse);

      // 2) El usuario retrasa el reloj a antes de `exp`.
      final EstadoLicencia trucado =
          await servicioEn(token, DateTime.utc(2026, 2)).cargarLicenciaLocal();

      expect(trucado.estaActivada, isFalse,
          reason: 'la marca ultimo_visto_utc impide revivir el token');
      expect(trucado.relojSospechoso, isTrue);
    });

    test('sospechoso NO degrada por sí solo: solo pide revalidar', () async {
      final String token = firmarToken(payloadFacturadorVigente);

      await servicioEn(token, ahoraFija).cargarLicenciaLocal();

      final EstadoLicencia tz = await servicioEn(
        token,
        ahoraFija.subtract(const Duration(hours: 12)),
      ).cargarLicenciaLocal();
      expect(tz.estaActivada, isTrue);
      expect(tz.relojSospechoso, isFalse,
          reason: 'un cambio de huso horario no es un ataque');

      final EstadoLicencia raro = await servicioEn(
        token,
        ahoraFija.subtract(const Duration(days: 200)),
      ).cargarLicenciaLocal();
      expect(raro.estaActivada, isTrue,
          reason: 'la licencia sigue vigente; solo se marca el estado');
      expect(raro.relojSospechoso, isTrue);
      expect(raro.motivo, contains('fecha'));
    });
  });
}
