/// Configuración local del negocio: lo que el dueño elige una vez y la app
/// recuerda.
///
/// Espejo de `ConfiguracionNegocio` / `IConfiguracionStore` de
/// `src/PagoYa.Desktop/Servicios/ConfiguracionStore.cs`. Dueño de ESTE archivo:
/// `mobile-lead`. Lo implementa `flutter-datos` sobre la tabla `meta` de SQLite
/// (no un JSON suelto: así entra en el mismo respaldo que el resto de datos).
///
/// **No confundir con la licencia.** Esto es preferencia del usuario y se puede
/// editar libremente; lo que habilita features caras es el token firmado.
library;

import 'package:meta/meta.dart';

import '../dominio/enums.dart';

/// Preferencias persistentes del negocio en este dispositivo.
@immutable
final class ConfiguracionNegocio {
  /// Crea la configuración del negocio.
  const ConfiguracionNegocio({
    this.nombreNegocio = 'Mi Negocio',
    this.rubro = RubroNegocio.bodega,
    this.categoriasPersonalizadas = const <String>[],
    this.ruc = '',
    this.direccion = '',
    this.telefono = '',
    this.pieTicket = '¡Gracias por su compra!',
    this.macImpresora,
    this.anchoPapelMm = 58,
    this.abrirCajonEnEfectivo = false,
    this.syncUrlBase,
    this.prefijoDispositivo = 'M01',
    this.onboardingCompletado = false,
  });

  /// Nombre comercial. Encabeza el ticket.
  final String nombreNegocio;

  /// Rubro elegido en el onboarding. Determina módulos y plantilla.
  final RubroNegocio rubro;

  /// Categorías creadas a mano por el dueño, además de las del rubro.
  /// En orden de creación, sin duplicados.
  final List<String> categoriasPersonalizadas;

  /// RUC del negocio.
  final String ruc;

  /// Dirección impresa en el ticket.
  final String direccion;

  /// Teléfono de contacto.
  final String telefono;

  /// Línea de cortesía al pie del ticket.
  final String pieTicket;

  /// MAC de la impresora térmica emparejada. `null` = sin impresora.
  final String? macImpresora;

  /// Ancho del papel: 58 u 80 mm. Por defecto **58** en móvil (las portátiles
  /// de bolsillo lo son casi siempre), al revés que el escritorio.
  final int anchoPapelMm;

  /// Pulsar el cajón portamonedas al cobrar en efectivo.
  final bool abrirCajonEnEfectivo;

  /// URL base del backend de sync. Vacía = modo offline puro.
  final String? syncUrlBase;

  /// Prefijo del correlativo de esta caja (`M01`, `M02`…).
  ///
  /// Con el móvil como segunda caja, `ventas.numero` colisiona con el de la PC.
  /// Formato acordado en MOBILE-ARQUITECTURA §6:
  /// `<prefijo-dispositivo>-<correlativo>`, p. ej. `M01-000123` en el móvil y
  /// `C01-000123` en la PC.
  final String prefijoDispositivo;

  /// `true` cuando el usuario ya eligió rubro y la app precargó la plantilla.
  /// Lo consulta el gate de arranque.
  final bool onboardingCompletado;

  /// Columnas de texto del ticket según el ancho de papel (58 mm ≈ 32,
  /// 80 mm ≈ 42). Misma fórmula que el escritorio.
  int get columnasTicket => anchoPapelMm <= 58 ? 32 : 42;

  /// Copia con cambios. Devuelve una instancia nueva: la configuración es
  /// inmutable a propósito, para que un provider de Riverpod pueda comparar por
  /// identidad y no repintar de más.
  ConfiguracionNegocio copiarCon({
    String? nombreNegocio,
    RubroNegocio? rubro,
    List<String>? categoriasPersonalizadas,
    String? ruc,
    String? direccion,
    String? telefono,
    String? pieTicket,
    String? macImpresora,
    int? anchoPapelMm,
    bool? abrirCajonEnEfectivo,
    String? syncUrlBase,
    String? prefijoDispositivo,
    bool? onboardingCompletado,
  }) =>
      ConfiguracionNegocio(
        nombreNegocio: nombreNegocio ?? this.nombreNegocio,
        rubro: rubro ?? this.rubro,
        categoriasPersonalizadas:
            categoriasPersonalizadas ?? this.categoriasPersonalizadas,
        ruc: ruc ?? this.ruc,
        direccion: direccion ?? this.direccion,
        telefono: telefono ?? this.telefono,
        pieTicket: pieTicket ?? this.pieTicket,
        macImpresora: macImpresora ?? this.macImpresora,
        anchoPapelMm: anchoPapelMm ?? this.anchoPapelMm,
        abrirCajonEnEfectivo: abrirCajonEnEfectivo ?? this.abrirCajonEnEfectivo,
        syncUrlBase: syncUrlBase ?? this.syncUrlBase,
        prefijoDispositivo: prefijoDispositivo ?? this.prefijoDispositivo,
        onboardingCompletado: onboardingCompletado ?? this.onboardingCompletado,
      );
}

/// Lee y persiste la [ConfiguracionNegocio]. Espejo de `IConfiguracionStore`.
///
/// Implementa: `flutter-datos`.
abstract interface class AlmacenConfiguracion {
  /// Configuración guardada, o `null` si es el primer arranque.
  Future<ConfiguracionNegocio?> leer();

  /// Persiste la configuración (sobrescribe).
  Future<void> guardar(ConfiguracionNegocio config);

  /// Observa los cambios para que el ticket y los módulos visibles se
  /// actualicen sin reiniciar la app.
  Stream<ConfiguracionNegocio> observar();
}
