/// Composición del módulo de nube: decide, **a partir del token firmado**, si
/// se instancia el motor real o el Null Object.
///
/// Es el equivalente Dart del registro de DI del escritorio: allí
/// `SyncServiceDeshabilitado` se inyecta cuando la licencia no trae el flag.
/// Aquí lo hace [FabricaSync].
///
/// REGLA (CLAUDE.md + `docs/MOBILE-ARQUITECTURA.md` §5.2): el gating es por
/// **flag firmado**, nunca por tier ni por bandera local. Esta fábrica solo
/// acepta el conjunto de features que ya salió del validador RSA
/// (`flutter-licencia`); no lo deduce del `tier` ni de nada guardado en claro.
library;

import 'contratos_sync.dart';
import 'puerto_outbox.dart';
import 'servicio_sync_deshabilitado.dart';
import 'servicio_sync_nube.dart';
import 'transporte_http_sync.dart';

/// Nombre canónico del flag. Mismo string que `Flags.CloudSync` de C# y que
/// `docs/LICENSE-TOKEN.md` §5. NO renombrar sin coordinar backend y escritorio.
const String flagCloudSync = 'cloud_sync';

class FabricaSync {
  const FabricaSync._();

  /// `true` si el conjunto de features verificado habilita la nube.
  static bool habilitada(Set<String> featuresVerificadas) =>
      featuresVerificadas.contains(flagCloudSync);

  /// Construye el servicio adecuado.
  ///
  /// - Con `cloud_sync` → [ServicioSyncNube] sobre [TransporteHttpSync].
  /// - Sin `cloud_sync` → [ServicioSyncDeshabilitado] (no-op + upsell).
  ///
  /// [proveedorToken] permite rotar el token (renovación silenciosa por
  /// `/validate`) sin reconstruir nada.
  static ServicioSync crear({
    required Set<String> featuresVerificadas,
    required AlmacenOutbox outbox,
    required OpcionesSync opciones,
    ProveedorToken? proveedorToken,
    TransporteSync? transporte,
    RegistradorSync? registrador,
    int pendientesConocidos = 0,
  }) {
    if (!habilitada(featuresVerificadas)) {
      // Ojo: el outbox SIGUE llenándose aunque la nube esté apagada. El día que
      // el dueño compre el tier Cloud, su historial sube completo.
      return ServicioSyncDeshabilitado(pendientesConocidos: pendientesConocidos);
    }

    assert(
      opciones.origenCajaId.trim().isNotEmpty,
      'origenCajaId vacío: es el device_prefix que asigna el server en '
      'POST /devices (claim device_prefix). Sin él no hay filtro de eco ni '
      'correlativos únicos entre la PC y el móvil. Persístelo, no lo generes.',
    );

    return ServicioSyncNube(
      outbox: outbox,
      transporte: transporte ??
          TransporteHttpSync(opciones: opciones, proveedorToken: proveedorToken),
      opciones: opciones,
      registrador: registrador,
    );
  }
}
