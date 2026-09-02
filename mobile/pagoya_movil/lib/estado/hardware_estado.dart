/// Puertos de hardware, publicados como providers para las pantallas.
///
/// Dueño: `flutter-ui`. Se declaran **aquí** y no en `composicion.dart` por la
/// regla de §4.3: *un provider lo declara un solo archivo, y lo declara quien lo
/// consume*. Los consumidores son las pantallas de cobro (escáner), de venta
/// completada (impresora, WhatsApp) y de configuración de impresión.
///
/// ## Por qué el valor por defecto es el hardware FALSO y no un `throw`
///
/// `composicion.dart` usa `_faltaOverride` (lanza) para lo que sin lo cual la
/// app no tiene sentido: base de datos, licencia, identidad. El hardware **no
/// es de esa clase**: una venta se cobra igual sin impresora, sin cámara y sin
/// WhatsApp — así lo exige el contrato de `ImpresoraTickets` ("ningún método
/// lanza; la venta ya está guardada antes de llegar aquí").
///
/// Si esto lanzara, un teléfono sin Bluetooth tumbaría la pantalla de cobro
/// entera. Con el falso por defecto, el POS abre y el botón de imprimir informa
/// que no hay impresora, que es la verdad.
///
/// **PENDIENTE (`mobile-lead`)**: `main.dart` ya construye
/// `HardwarePagoYa.real()` / `.falso()` para el licenciamiento, pero **no lo
/// sobreescribe aquí**. Falta una línea en el `ProviderScope`:
///
/// ```dart
/// import 'estado/estado.dart' as ui;
/// ...
/// ui.hardwarePagoYaProvider.overrideWithValue(hardware),
/// ```
///
/// Sin ella, en un teléfono real el escáner abre el panel simulado en vez de la
/// cámara. Es visible de inmediato (el falso se anuncia como tal), no silencioso.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_hardware/pagoya_hardware.dart';

/// Fachada de plataforma. La sobreescribe `main.dart` con `HardwarePagoYa.real()`.
final Provider<HardwarePagoYa> hardwarePagoYaProvider =
    Provider<HardwarePagoYa>((Ref ref) {
  final hardware = HardwarePagoYa.falso();
  ref.onDispose(() {
    unawaited(hardware.liberar());
  });
  return hardware;
});

/// Cámara como lector de códigos de barras.
final Provider<EscanerCodigos> escanerProvider = Provider<EscanerCodigos>(
  (Ref ref) => ref.watch(hardwarePagoYaProvider).escaner,
);

/// Impresora térmica Bluetooth (ESC/POS).
final Provider<ImpresoraTickets> impresoraProvider = Provider<ImpresoraTickets>(
  (Ref ref) => ref.watch(hardwarePagoYaProvider).impresora,
);

/// Compartir el comprobante (WhatsApp).
final Provider<CompartirArchivo> compartirProvider = Provider<CompartirArchivo>(
  (Ref ref) => ref.watch(hardwarePagoYaProvider).compartir,
);

/// `true` si hay WhatsApp instalado. Decide si el botón dice "Enviar por
/// WhatsApp" o "Compartir". Ante cualquier fallo asume que **sí** lo hay: el
/// mercado objetivo es Perú, donde WhatsApp está en prácticamente todos los
/// teléfonos, y equivocarse hacia "Compartir" solo cambia una etiqueta.
final FutureProvider<bool> whatsappDisponibleProvider =
    FutureProvider<bool>((Ref ref) async {
  try {
    return await ref.watch(compartirProvider).whatsappDisponible;
  } on Object {
    return true;
  }
});

/// Estado vivo de la impresora, para el indicador de la barra superior.
final StreamProvider<EstadoImpresora> estadoImpresoraProvider =
    StreamProvider<EstadoImpresora>(
  (Ref ref) => ref.watch(impresoraProvider).estado,
);
