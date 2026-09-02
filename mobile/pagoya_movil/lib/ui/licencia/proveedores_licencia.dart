/// Providers del licenciamiento en la capa de UI.
///
/// Los puertos de plataforma y el `ServicioLicencia` ya los provee
/// `composicion.dart` (dueño: `mobile-lead`). Aquí solo se derivan las piezas
/// que necesitan las pantallas de este módulo: el vinculador de asientos, el
/// revalidador silencioso, el id del dispositivo y el feature-gating.
///
/// **No se duplica `estadoLicenciaProvider`**: la única fuente de verdad del
/// gating es la de `composicion.dart`, alimentada por el stream
/// `ServicioLicencia.cambios`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import '../../composicion.dart';

/// Vinculación de este teléfono como asiento secundario (`POST /devices`).
final Provider<VinculadorAsiento> vinculadorAsientoProvider =
    Provider<VinculadorAsiento>(
  (Ref ref) => crearVinculadorAsiento(
    servicio: ref.watch(servicioLicenciaProvider),
    dispositivos: ref.watch(servicioDispositivosProvider),
    identidad: ref.watch(identidadDispositivoProvider),
    almacenSeguro: ref.watch(almacenSeguroProvider),
    baseDatos: ref.watch(baseDatosProvider),
  ),
);

/// Revalidación silenciosa. La dispara el arranque y el botón "Revalidar ahora"
/// de Ajustes.
final Provider<RevalidadorLicencia> revalidadorLicenciaProvider =
    Provider<RevalidadorLicencia>(
  (Ref ref) => crearRevalidadorLicencia(
    servicio: ref.watch(servicioLicenciaProvider),
    dispositivos: ref.watch(servicioDispositivosProvider),
    identidad: ref.watch(identidadDispositivoProvider),
    almacenSeguro: ref.watch(almacenSeguroProvider),
    baseDatos: ref.watch(baseDatosProvider),
  ),
);

/// Id de este dispositivo (el asiento), para mostrarlo en la pantalla de
/// activación y que el dueño lo envíe por WhatsApp. Es el equivalente móvil del
/// HWID que muestra `ActivacionViewModel` en la PC.
final FutureProvider<String> idDispositivoProvider =
    FutureProvider<String>((Ref ref) async {
  try {
    return await ref.watch(identidadDispositivoProvider).obtenerIdDispositivo();
  } catch (_) {
    return '(no disponible)';
  }
});

/// `true` si la característica está habilitada por un flag **firmado**.
///
/// Nunca por tier ni por bandera local (MOBILE-ARQUITECTURA §5.2). Es el único
/// provider que deben consultar las pantallas para decidir candado vs. módulo.
final caracteristicaProvider = Provider.family<bool, CaracteristicaLicencia>(
  (Ref ref, CaracteristicaLicencia caracteristica) =>
      ref.watch(estadoLicenciaProvider).tieneCaracteristica(caracteristica),
);

/// Selector de archivos para importar un `.lic`/`.txt` recibido por WhatsApp o
/// por USB-OTG — el equivalente móvil de `ImportarLicenciaArchivo` del
/// escritorio, pensado para cajas sin datos móviles.
///
/// ⚠ PENDIENTE (`flutter-hardware` / `mobile-lead`): no hay puerto de selección
/// de archivos en `dispositivo/contratos.dart` y `file_picker` no está en las
/// dependencias decididas (§4). Mientras este provider devuelva `null`, la
/// pantalla de activación **oculta** el botón "Desde archivo" — las otras dos
/// rutas offline (pegar y QR) siguen funcionando.
abstract interface class SelectorArchivoLicencia {
  /// Abre el selector y devuelve el contenido del archivo elegido, o `null` si
  /// el usuario cancela.
  Future<String?> elegirYLeer();
}

/// `null` mientras nadie lo sobrescriba en el `ProviderScope` raíz.
final Provider<SelectorArchivoLicencia?> selectorArchivoLicenciaProvider =
    Provider<SelectorArchivoLicencia?>((Ref ref) => null);
