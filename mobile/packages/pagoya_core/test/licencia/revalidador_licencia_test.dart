@Timeout(Duration(minutes: 5))

/// Tests de la revalidación silenciosa contra `POST /devices`.
///
/// ⚠ NO EJECUTADOS: el entorno donde se escribieron no tiene shell disponible.
library;

import 'package:pagoya_core/licencia/licencia.dart';
import 'package:test/test.dart';

import 'dobles.dart';
import 'vectores.dart';

EstadoLicencia estadoDe({
  bool activada = true,
  DateTime? expira,
  bool gracia = false,
  bool relojSospechoso = false,
}) =>
    EstadoLicencia(
      esValida: true,
      estaActivada: activada,
      tier: TierLicencia.cloud,
      featuresHabilitadas: const <String>['cloud_sync'],
      expiraUtc: expira,
      enPeriodoGracia: gracia,
      relojSospechoso: relojSospechoso,
    );

void main() {
  group('debeRevalidar (puro, sin red)', () {
    test('sin licencia activada no revalida: eso lo resuelve el gate', () {
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(activada: false),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: null,
        ),
        isFalse,
      );
    });

    test('suscripción lejos de expirar: no molesta al server', () {
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(expira: ahoraFija.add(const Duration(days: 20))),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: null,
        ),
        isFalse,
      );
    });

    test('dentro de los 3 días previos a exp: sí revalida', () {
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(expira: ahoraFija.add(const Duration(days: 2))),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: null,
        ),
        isTrue,
      );
    });

    test('respeta el throttling de 6 h antes de expirar', () {
      final EstadoLicencia e =
          estadoDe(expira: ahoraFija.add(const Duration(days: 2)));

      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: e,
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(hours: 2)),
        ),
        isFalse,
      );
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: e,
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(hours: 7)),
        ),
        isTrue,
      );
    });

    test('en periodo de gracia el intervalo baja a 1 h', () {
      final EstadoLicencia e = estadoDe(
        expira: ahoraFija.subtract(const Duration(days: 2)),
        gracia: true,
      );

      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: e,
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(minutes: 30)),
        ),
        isFalse,
      );
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: e,
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('el reloj sospechoso fuerza revalidación aunque sea perpetua', () {
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(relojSospechoso: true),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('perpetua tranquila: como mucho una vez cada 30 días', () {
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(days: 10)),
        ),
        isFalse,
      );
      expect(
        RevalidadorLicencia.debeRevalidar(
          estado: estadoDe(),
          ahoraUtc: ahoraFija,
          ultimoIntentoUtc: ahoraFija.subtract(const Duration(days: 31)),
        ),
        isTrue,
      );
    });
  });

  group('revalidarSiCorresponde', () {
    late AlmacenSeguroEnMemoria seguro;
    late MetaLicenciaEnMemoria meta;
    late ServicioLicencia servicio;

    RevalidadorLicencia revalidadorCon(ServicioDispositivosFalso api) =>
        RevalidadorLicencia(
          servicio: servicio,
          dispositivos: api,
          identidad: const IdentidadFalsa(idDispositivoPropio),
          almacen: AlmacenLicenciaSegura(seguro),
          meta: meta,
          reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        );

    setUp(() async {
      meta = MetaLicenciaEnMemoria();
      seguro = AlmacenSeguroEnMemoria.conToken(
        firmarToken(payloadCloudEnGracia),
        clave: 'PAGOYA-AAAA-BBBB-CCCC-DDDD',
      );
      servicio = ServicioLicencia(
        validador: validadorDePruebas(),
        identidad: const IdentidadFalsa(idDispositivoPropio),
        almacen: AlmacenLicenciaSegura(seguro),
        reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        meta: meta,
      );
      await servicio.cargarLicenciaLocal();
    });

    test('renueva y persiste el token nuevo', () async {
      expect(servicio.estadoActual.enPeriodoGracia, isTrue);

      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar: firmarToken(payloadFacturadorVigente),
      );

      final ResultadoRevalidacion r =
          await revalidadorCon(api).revalidarSiCorresponde();

      expect(r, ResultadoRevalidacion.renovada);
      expect(api.llamadasVincular, 1,
          reason: 'POST /devices es idempotente por deviceId');
      expect(api.ultimaClaveRecibida, 'PAGOYA-AAAA-BBBB-CCCC-DDDD');
      expect(api.ultimoIdRecibido, idDispositivoPropio);
      expect(servicio.estadoActual.enPeriodoGracia, isFalse);
      expect(servicio.estadoActual.tier, TierLicencia.facturadorPro);
      expect(meta.datos[ClavesMetaLicencia.ultimaRevalidacionUtc], isNotNull);
    });

    test('un token corrupto devuelto por el server NO se persiste', () async {
      final String tokenBueno = seguro.datos[ClavesSeguras.tokenLicencia]!;

      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar:
            manipularUnByteDelPayload(firmarToken(payloadFacturadorVigente)),
      );

      await revalidadorCon(api).revalidarSiCorresponde();

      expect(seguro.datos[ClavesSeguras.tokenLicencia], tokenBueno,
          reason: 'activarLicencia revalida la firma antes de guardar');
      expect(servicio.estadoActual.estaActivada, isFalse);
    });

    test('sin red no degrada nada: el token local sigue mandando', () async {
      final EstadoLicencia antes = servicio.estadoActual;

      final ResultadoRevalidacion r = await revalidadorCon(
        ServicioDispositivosFalso(lanzaError: true),
      ).revalidarSiCorresponde();

      expect(r, ResultadoRevalidacion.falloTransitorio);
      expect(servicio.estadoActual.estaActivada, antes.estaActivada);
      expect(servicio.estadoActual.tier, antes.tier);
    });

    test('un rechazo del backend tampoco degrada en caliente', () async {
      final ResultadoRevalidacion r = await revalidadorCon(
        ServicioDispositivosFalso(mensajeDeFallo: 'Licencia suspendida.'),
      ).revalidarSiCorresponde();

      expect(r, ResultadoRevalidacion.rechazada);
      expect(servicio.estadoActual.estaActivada, isTrue,
          reason: 'un asiento revocado sigue validando offline hasta su exp; '
              'el corte real lo aplica /sync/* con 403');
    });

    test('sin clave de licencia guardada no puede renovar', () async {
      await seguro.borrar(ClavesSeguras.claveLicencia);

      final ServicioDispositivosFalso api = ServicioDispositivosFalso();
      final ResultadoRevalidacion r =
          await revalidadorCon(api).revalidarSiCorresponde();

      expect(r, ResultadoRevalidacion.sinClaveLicencia);
      expect(api.llamadasVincular, 0);
    });

    test('el throttling evita el segundo intento seguido', () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar: firmarToken(payloadCloudEnGracia),
      );
      final RevalidadorLicencia rev = revalidadorCon(api);

      await rev.revalidarSiCorresponde();
      final ResultadoRevalidacion segunda = await rev.revalidarSiCorresponde();

      expect(segunda, ResultadoRevalidacion.omitida);
      expect(api.llamadasVincular, 1);
    });

    test('forzar salta el throttling (botón "Revalidar ahora")', () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar: firmarToken(payloadCloudEnGracia),
      );
      final RevalidadorLicencia rev = revalidadorCon(api);

      await rev.revalidarSiCorresponde();
      await rev.revalidarSiCorresponde(forzar: true);

      expect(api.llamadasVincular, 2);
    });
  });

  group('VinculadorAsiento', () {
    late AlmacenSeguroEnMemoria seguro;
    late MetaLicenciaEnMemoria meta;
    late ServicioLicencia servicio;

    setUp(() {
      meta = MetaLicenciaEnMemoria();
      seguro = AlmacenSeguroEnMemoria();
      servicio = ServicioLicencia(
        validador: validadorDePruebas(),
        identidad: const IdentidadFalsa(idDispositivoPropio),
        almacen: AlmacenLicenciaSegura(seguro),
        reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        meta: meta,
      );
    });

    VinculadorAsiento vinculadorCon(ServicioDispositivosFalso api) =>
        VinculadorAsiento(
          licencia: servicio,
          dispositivos: api,
          identidad: const IdentidadFalsa(idDispositivoPropio),
          almacen: AlmacenLicenciaSegura(seguro),
          meta: meta,
        );

    test('vincular con clave activa el POS y guarda la clave para renovar',
        () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar: firmarToken(payloadFacturadorVigente),
      );

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('PAGOYA-AAAA-BBBB-CCCC-DDDD');

      expect(r.exito, isTrue);
      expect(r.estado.estaActivada, isTrue);
      expect(seguro.datos[ClavesSeguras.claveLicencia],
          'PAGOYA-AAAA-BBBB-CCCC-DDDD');
      expect(meta.datos[ClavesMetaLicencia.prefijoDispositivo], prefijoAsiento);
    });

    test('cupo de dispositivos agotado → mensaje claro y salida a soporte',
        () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        mensajeDeFallo: 'Ya usaste tus 3 dispositivos.',
      );

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('PAGOYA-AAAA');

      expect(r.exito, isFalse);
      expect(r.mensaje, contains('dispositivos'));
      expect(r.requiereSoporte, isTrue,
          reason: 'es un caso de venta: subir de plan o liberar un asiento');
      expect(seguro.datos[ClavesSeguras.claveLicencia], isNull,
          reason: 'no se guarda la clave si la vinculación falló');
    });

    test('si el server emite un token para otro dispositivo, NO se activa',
        () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        tokenARetornar: firmarToken(payloadOtroDispositivo),
      );

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('PAGOYA-AAAA');

      expect(r.exito, isFalse);
      expect(r.estado.estaActivada, isFalse,
          reason: 'no se confía en el servidor sin verificar la firma y el hwid');
    });

    test('sin red, se ofrece la ruta offline de pegar el token', () async {
      final ResultadoActivacionAsiento r =
          await vinculadorCon(ServicioDispositivosFalso(lanzaError: true))
              .vincularConClave('PAGOYA-AAAA');

      expect(r.exito, isFalse);
      expect(r.mensaje, contains('sin internet'));
    });

    test('clave vacía se rechaza sin llamar al backend', () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso();
      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('   ');

      expect(r.exito, isFalse);
      expect(api.llamadasVincular, 0);
    });

    test('el CÓDIGO manda de punta a punta, aunque el texto diga otra cosa',
        () async {
      // El backend manda `token_expirado` pero con una redacción que habla de
      // dispositivos. Sin el código, la ruta por texto habría dicho "cupo
      // lleno" y habría mandado al dueño a soporte en vez de a renovar.
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        codigoDeFallo: CodigosErrorLicencia.tokenExpirado,
        mensajeDeFallo: 'Tu dispositivo no puede usar esta licencia.',
      );

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('PAGOYA-AAAA');

      expect(r.motivoFallo, MotivoFalloVinculacion.tokenExpirado);
      expect(r.requiereRenovacion, isTrue);
      expect(r.requiereSoporte, isFalse);
    });

    test('cupo lleno por código → soporte', () async {
      final ServicioDispositivosFalso api = ServicioDispositivosFalso(
        codigoDeFallo: CodigosErrorLicencia.cupoDispositivosLleno,
        mensajeDeFallo: 'Límite alcanzado (3/3).',
      );

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).vincularConClave('PAGOYA-AAAA');

      expect(r.motivoFallo, MotivoFalloVinculacion.cupoDispositivosLleno);
      expect(r.requiereSoporte, isTrue);
      expect(r.mensaje, 'Límite alcanzado (3/3).',
          reason: 'el texto del backend gana; soporte lo reescribe sin desplegar');
    });

    test('la red LANZA y se traduce a `red`, nunca a un problema de licencia',
        () async {
      final ResultadoActivacionAsiento r =
          await vinculadorCon(ServicioDispositivosFalso(lanzaError: true))
              .vincularConClave('PAGOYA-AAAA');

      expect(r.motivoFallo, MotivoFalloVinculacion.red);
      expect(r.esTransitorio, isTrue);
      expect(r.requiereSoporte, isFalse,
          reason: 'un dueño sin señal no debe ver un problema de licencia');
    });
  });

  group('Revocación del asiento', () {
    late AlmacenSeguroEnMemoria seguro;
    late MetaLicenciaEnMemoria meta;
    late ServicioLicencia servicio;

    VinculadorAsiento vinculadorCon(ServicioDispositivosFalso api) =>
        VinculadorAsiento(
          licencia: servicio,
          dispositivos: api,
          identidad: const IdentidadFalsa(idDispositivoPropio),
          almacen: AlmacenLicenciaSegura(seguro),
          meta: meta,
        );

    setUp(() async {
      meta = MetaLicenciaEnMemoria();
      seguro = AlmacenSeguroEnMemoria.conToken(
        firmarToken(payloadFacturadorVigente),
        clave: 'PAGOYA-AAAA-BBBB-CCCC-DDDD',
      );
      servicio = ServicioLicencia(
        validador: validadorDePruebas(),
        identidad: const IdentidadFalsa(idDispositivoPropio),
        almacen: AlmacenLicenciaSegura(seguro),
        reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        meta: meta,
      );
      await servicio.cargarLicenciaLocal();
    });

    test('manda el GUID del ASIENTO, no la huella del dispositivo', () async {
      // `DELETE /devices/{id}` espera el id de la fila `Devices`, que llega
      // firmado en el claim `device_id`. Pasarle el UUID local daría 404.
      final ServicioDispositivosFalso api = ServicioDispositivosFalso();

      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).revocarEsteDispositivo();

      expect(r.exito, isTrue);
      expect(api.ultimoIdRevocado, idAsiento);
      expect(api.ultimoIdRevocado, isNot(idDispositivoPropio),
          reason: 'son dos valores distintos: asiento vs. huella del equipo');
      expect(servicio.estadoActual.estaActivada, isFalse);
    });

    test('sin red NO se desactiva la licencia local', () async {
      // Desactivar aquí dejaría al dueño fuera del POS con el asiento todavía
      // ocupado en el servidor: lo peor de los dos mundos.
      final ResultadoActivacionAsiento r =
          await vinculadorCon(ServicioDispositivosFalso(lanzaError: true))
              .revocarEsteDispositivo();

      expect(r.exito, isFalse);
      expect(r.motivoFallo, MotivoFalloVinculacion.red);
      expect(servicio.estadoActual.estaActivada, isTrue);
      expect(seguro.datos[ClavesSeguras.tokenLicencia], isNotNull);
    });

    test('un token sin `device_id` limpia lo local y deriva a soporte',
        () async {
      // Licencia anterior al modelo de asientos: no hay nada que revocar por
      // API, pero el dueño igual quiere salir de este celular.
      seguro = AlmacenSeguroEnMemoria.conToken(
        firmarToken(payloadBasePerpetua),
        clave: 'PAGOYA-AAAA',
      );
      meta = MetaLicenciaEnMemoria();
      servicio = ServicioLicencia(
        validador: validadorDePruebas(),
        identidad: const IdentidadFalsa(idDispositivoPropio),
        almacen: AlmacenLicenciaSegura(seguro),
        reloj: RelojAuditadoMeta(meta, ahoraDelSistema: () => ahoraFija),
        meta: meta,
      );
      await servicio.cargarLicenciaLocal();

      final ServicioDispositivosFalso api = ServicioDispositivosFalso();
      final ResultadoActivacionAsiento r =
          await vinculadorCon(api).revocarEsteDispositivo();

      expect(api.llamadasRevocar, 0);
      expect(r.exito, isTrue);
      expect(r.mensaje, contains('WhatsApp'));
      expect(servicio.estadoActual.estaActivada, isFalse);
    });
  });
}
