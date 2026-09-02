// PagoYa Móvil — datos/almacen_configuracion.dart
//
// Implementación de `AlmacenConfiguracion` (configuracion/contratos.dart) sobre
// la tabla `meta` de SQLite.
//
// POR QUÉ EN `meta` Y NO EN UN JSON SUELTO (decisión §4.1): en el escritorio la
// configuración vive en un `config.json` aparte, que se queda fuera de
// cualquier respaldo o restauración de la base. En un celular que se pierde o se
// cambia cada dos años, eso significa recuperar las ventas pero no el nombre del
// negocio ni el pie del ticket. Guardándola en `meta` entra en el mismo archivo
// `.db` que todo lo demás.
//
// Cada campo es una fila clave/valor, no un blob JSON: así una versión futura
// que añada un campo lee las claves viejas sin migración, y una versión vieja
// que encuentre claves nuevas las ignora.

library;

import '../configuracion/contratos.dart';
import '../dominio/enums.dart';
import 'ejecutor_sql.dart';
import 'notificador_tablas.dart';
import 'sentencias.dart';

/// Claves de `meta` que componen la [ConfiguracionNegocio].
///
/// El prefijo `cfg_` las separa de las claves de infraestructura
/// (`schema_version`, `sync_cursor`, `prefijo_dispositivo`…). Sin prefijo, un
/// campo de configuración llamado igual que una clave interna la pisaría.
abstract final class ClavesConfig {
  static const String prefijo = 'cfg_';

  static const String nombreNegocio = '${prefijo}nombre_negocio';
  static const String rubro = '${prefijo}rubro';
  static const String categoriasPersonalizadas =
      '${prefijo}categorias_personalizadas';
  static const String ruc = '${prefijo}ruc';
  static const String direccion = '${prefijo}direccion';
  static const String telefono = '${prefijo}telefono';
  static const String pieTicket = '${prefijo}pie_ticket';
  static const String macImpresora = '${prefijo}mac_impresora';
  static const String anchoPapelMm = '${prefijo}ancho_papel_mm';
  static const String abrirCajonEnEfectivo = '${prefijo}abrir_cajon_efectivo';
  static const String syncUrlBase = '${prefijo}sync_url_base';
  static const String prefijoDispositivo = '${prefijo}prefijo_dispositivo';
  static const String onboardingCompletado = '${prefijo}onboarding_completado';

  /// Separador de la lista de categorías personalizadas.
  ///
  /// Se usa `|` y no una coma porque una categoría bien puede llamarse
  /// "Bebidas, gaseosas y aguas"; el mismo separador que usa
  /// `habitaciones.comodidades` en el esquema compartido.
  static const String separadorLista = '|';
}

/// Configuración del negocio persistida en `meta`.
final class AlmacenConfiguracionMeta implements AlmacenConfiguracion {
  final EjecutorSql _db;
  final FuenteDeCambios _cambios;

  AlmacenConfiguracionMeta(this._db)
      : _cambios = _db is FuenteDeCambios ? _db : const SinCambios();

  /// Devuelve `null` en el primer arranque (nada guardado todavía), que es lo
  /// que el gate de arranque interpreta como "hay que hacer onboarding".
  @override
  Future<ConfiguracionNegocio?> leer() async {
    final filas = await _db.consultar(
      'SELECT clave, valor FROM meta WHERE clave LIKE ?',
      ['${ClavesConfig.prefijo}%'],
    );
    if (filas.isEmpty) return null;

    final m = <String, String>{
      for (final f in filas)
        (f['clave'] ?? '').toString(): (f['valor'] ?? '').toString(),
    };

    // Los valores por defecto salen del constructor de ConfiguracionNegocio, no
    // se repiten aquí: una constante duplicada es una constante que diverge.
    const pd = ConfiguracionNegocio();

    return ConfiguracionNegocio(
      nombreNegocio: m[ClavesConfig.nombreNegocio] ?? pd.nombreNegocio,
      rubro: RubroNegocio.desdeClave(m[ClavesConfig.rubro]),
      categoriasPersonalizadas: _leerLista(m[ClavesConfig.categoriasPersonalizadas]),
      ruc: m[ClavesConfig.ruc] ?? pd.ruc,
      direccion: m[ClavesConfig.direccion] ?? pd.direccion,
      telefono: m[ClavesConfig.telefono] ?? pd.telefono,
      pieTicket: m[ClavesConfig.pieTicket] ?? pd.pieTicket,
      macImpresora: _vacioComoNulo(m[ClavesConfig.macImpresora]),
      anchoPapelMm:
          int.tryParse(m[ClavesConfig.anchoPapelMm] ?? '') ?? pd.anchoPapelMm,
      abrirCajonEnEfectivo: _leerBool(
          m[ClavesConfig.abrirCajonEnEfectivo], pd.abrirCajonEnEfectivo),
      syncUrlBase: _vacioComoNulo(m[ClavesConfig.syncUrlBase]),
      prefijoDispositivo:
          m[ClavesConfig.prefijoDispositivo] ?? pd.prefijoDispositivo,
      onboardingCompletado: _leerBool(
          m[ClavesConfig.onboardingCompletado], pd.onboardingCompletado),
    );
  }

  /// Persiste la configuración completa en una sola transacción.
  ///
  /// Todo o nada a propósito: si se guardara clave por clave y la app muriera a
  /// la mitad, quedaría un negocio con el rubro nuevo y el pie de ticket viejo.
  @override
  Future<void> guardar(ConfiguracionNegocio config) async {
    final valores = <String, String?>{
      ClavesConfig.nombreNegocio: config.nombreNegocio,
      // Se guarda la CLAVE del rubro (`bodega`), no el índice del enum: es el
      // mismo texto que usa el escritorio y sobrevive a que se reordene el enum.
      ClavesConfig.rubro: config.rubro.clave,
      ClavesConfig.categoriasPersonalizadas:
          config.categoriasPersonalizadas.join(ClavesConfig.separadorLista),
      ClavesConfig.ruc: config.ruc,
      ClavesConfig.direccion: config.direccion,
      ClavesConfig.telefono: config.telefono,
      ClavesConfig.pieTicket: config.pieTicket,
      ClavesConfig.macImpresora: config.macImpresora ?? '',
      ClavesConfig.anchoPapelMm: config.anchoPapelMm.toString(),
      ClavesConfig.abrirCajonEnEfectivo: config.abrirCajonEnEfectivo ? '1' : '0',
      ClavesConfig.syncUrlBase: config.syncUrlBase ?? '',
      ClavesConfig.prefijoDispositivo: config.prefijoDispositivo,
      ClavesConfig.onboardingCompletado: config.onboardingCompletado ? '1' : '0',
    };

    await _db.transaccion((tx) async {
      for (final e in valores.entries) {
        final s = Sql.insertar('meta', {'clave': e.key, 'valor': e.value ?? ''});
        await tx.ejecutar(
          '${s.sql}\nON CONFLICT(clave) DO UPDATE SET valor = excluded.valor',
          s.args,
        );
      }
    });

    _cambios.notificarCambio({Tablas.meta});
  }

  /// Observa la configuración para que el ticket y los módulos visibles se
  /// actualicen sin reiniciar la app.
  ///
  /// Emite solo cuando hay configuración guardada: antes del onboarding no hay
  /// nada que observar y un `null` en el stream obligaría a cada consumidor a
  /// manejarlo.
  @override
  Stream<ConfiguracionNegocio> observar() async* {
    final inicial = await leer();
    if (inicial != null) yield inicial;

    await for (final _ in _cambios.cambiosEn({Tablas.meta})) {
      final actual = await leer();
      if (actual != null) yield actual;
    }
  }

  static List<String> _leerLista(String? valor) {
    if (valor == null || valor.trim().isEmpty) return const <String>[];
    return valor
        .split(ClavesConfig.separadorLista)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  /// `meta.valor` es `TEXT NOT NULL`, así que un opcional ausente se guarda
  /// como cadena vacía y se recupera como `null`.
  static String? _vacioComoNulo(String? valor) =>
      (valor == null || valor.isEmpty) ? null : valor;

  static bool _leerBool(String? valor, bool porDefecto) {
    if (valor == null || valor.isEmpty) return porDefecto;
    return valor == '1' || valor.toLowerCase() == 'true';
  }
}
