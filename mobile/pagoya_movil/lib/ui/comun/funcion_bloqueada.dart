import 'package:flutter/material.dart';

import '../tema/tema.dart';
import 'botones_pagoya.dart';
import 'chips_estado.dart';

/// Estados visuales de las funciones que dependen de un flag firmado del token
/// de licencia (`invoicing`, `cloud_sync`, `multi_site`).
///
/// **Regla de producto:** una función sin flag **nunca se oculta**. Se muestra
/// con candado y un upsell claro, porque convertir Base → Cloud → Facturador es
/// el modelo de negocio (`CLAUDE.md`). Ocultarla mata la conversión; mostrarla
/// rota y sin explicación mata la confianza.
///
/// Nada aquí lee el token ni decide si hay flag: eso es de `flutter-licencia`.
/// Estos widgets solo pintan el estado que se les pasa.

/// Copy del upsell de un módulo bloqueado — port de `UpsellViewModel.Mostrar`,
/// **mismos textos** que el escritorio para que la promesa comercial no
/// diverja entre la PC y el celular.
@immutable
class ContenidoUpsell {
  const ContenidoUpsell({
    required this.clave,
    required this.emoji,
    required this.titulo,
    required this.tierRequerido,
    required this.precio,
    required this.gancho,
    required this.beneficios,
  });

  /// `facturacion` · `cloud` · `multisede`.
  final String clave;

  /// Emoji grande de la cabecera (🧾 / ☁ / 🏪).
  final String emoji;

  final String titulo;

  /// Nombre comercial del tier necesario.
  final String tierRequerido;

  final String precio;

  /// Frase de gancho, una línea.
  final String gancho;

  /// Tres beneficios con check verde.
  final List<String> beneficios;

  /// Facturación electrónica → Facturador Pro (flag `invoicing`).
  static const ContenidoUpsell facturacion = ContenidoUpsell(
    clave: 'facturacion',
    emoji: '🧾',
    titulo: 'Emite Boletas y Facturas electrónicas',
    tierRequerido: 'PagoYa Facturador Pro',
    precio: 'Desde S/ 50 / mes',
    gancho:
        'Vende formal y gana clientes empresa. Envío directo a SUNAT, sin '
        'certificados que configurar.',
    beneficios: <String>[
      'Boletas y Facturas ilimitadas, válidas ante SUNAT.',
      'PDF del comprobante enviado por WhatsApp al instante.',
      'Incluye todo lo de Cloud (respaldo + multisede).',
    ],
  );

  /// Respaldo en la nube → Cloud (flag `cloud_sync`).
  static const ContenidoUpsell cloud = ContenidoUpsell(
    clave: 'cloud',
    emoji: '☁',
    titulo: 'Respalda tu negocio en la nube',
    tierRequerido: 'PagoYa Cloud',
    precio: 'Desde S/ 25 / mes',
    gancho:
        'Nunca pierdas tus ventas ni tu inventario. Consulta tu negocio desde '
        'el celular, estés donde estés.',
    beneficios: <String>[
      'Respaldo automático: si se malogra el equipo, tus datos están seguros.',
      'Reportes en tu celular, en tiempo real.',
      'Base para operar varias cajas o sedes.',
    ],
  );

  /// Multi-caja / multisede → Cloud (flag `multi_site`).
  static const ContenidoUpsell multisede = ContenidoUpsell(
    clave: 'multisede',
    emoji: '🏪',
    titulo: 'Controla varias cajas y sedes',
    tierRequerido: 'PagoYa Cloud',
    precio: 'Desde S/ 25 / mes',
    gancho:
        'Crece sin perder el control. Consolida las ventas de todas tus '
        'tiendas en un solo lugar.',
    beneficios: <String>[
      'Multi-caja y multisede sincronizadas.',
      'Inventario y ventas consolidados por sede.',
      'Incluye respaldo en la nube.',
    ],
  );

  /// Genérico, por si aparece un módulo nuevo sin copy propio.
  static const ContenidoUpsell generico = ContenidoUpsell(
    clave: 'generico',
    emoji: '🔒',
    titulo: 'Función premium',
    tierRequerido: 'un plan superior',
    precio: '',
    gancho: 'Mejora tu plan para desbloquear esta función.',
    beneficios: <String>[],
  );

  /// Resuelve el copy por clave de módulo, con el mismo `switch` del escritorio.
  static ContenidoUpsell porClave(String? clave) {
    switch ((clave ?? '').toLowerCase()) {
      case 'facturacion':
        return facturacion;
      case 'cloud':
      case 'nube':
        return cloud;
      case 'multisede':
        return multisede;
      default:
        return generico;
    }
  }
}

/// **Tarjeta de función bloqueada.** El componente que se pone en el lugar
/// donde iría el módulo: candado, nombre de la función, gancho y "Mejora tu
/// plan".
///
/// Se usa en la grilla de módulos del inicio y como cuerpo completo de una
/// pantalla a la que el usuario navegó sin tener el flag.
class TarjetaFuncionBloqueada extends StatelessWidget {
  const TarjetaFuncionBloqueada({
    super.key,
    required this.contenido,
    this.onMejorarPlan,
    this.compacta = false,
  });

  final ContenidoUpsell contenido;

  /// Lleva a la pantalla de activación / licencia. Lo cablea `flutter-ui`.
  final VoidCallback? onMejorarPlan;

  /// `true` = versión de una fila para grillas y listas de módulos.
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    if (compacta) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onMejorarPlan,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: Espacios.lg,
            vertical: Espacios.md,
          ),
          decoration: BoxDecoration(
            color: t.blanco,
            border: Border.all(color: t.borde, width: 1.5),
            borderRadius: BorderRadius.circular(t.radioTarjeta),
          ),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: 0.45,
                child: Text(
                  contenido.emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
              const SizedBox(width: Espacios.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      contenido.titulo,
                      style: tipos.cuerpoFuerte.copyWith(color: t.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    ChipEstado(
                      'Requiere ${contenido.tierRequerido}',
                      tono: TonoChip.marca,
                      iconoAsset: IconosPos.candado,
                      emoji: '🔒',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espacios.sm),
              IconoPos(
                IconosPos.candado,
                tamano: 22,
                color: t.muted,
                respaldoEmoji: '🔒',
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(Espacios.xl),
      decoration: BoxDecoration(
        color: t.blanco,
        border: Border.all(color: t.borde, width: 1.5),
        borderRadius: BorderRadius.circular(t.radioTarjeta),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                color: t.primarioTinte,
                child: IconoPos(
                  IconosPos.candado,
                  tamano: 30,
                  color: t.primarioPresionado,
                  respaldoEmoji: '🔒',
                  semantica: 'Función bloqueada',
                ),
              ),
              const SizedBox(width: Espacios.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ChipEstado(
                      contenido.tierRequerido,
                      tono: TonoChip.marca,
                    ),
                    if (contenido.precio.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(contenido.precio, style: tipos.muted),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espacios.lg),
          Text(contenido.titulo, style: tipos.h2),
          const SizedBox(height: Espacios.sm),
          Text(contenido.gancho, style: tipos.muted),
          if (contenido.beneficios.isNotEmpty) ...<Widget>[
            const SizedBox(height: Espacios.lg),
            ...contenido.beneficios.map((b) => _Beneficio(b)),
          ],
          const SizedBox(height: Espacios.xl),
          BotonPrimario(
            texto: 'Mejora tu plan',
            onPressed: onMejorarPlan,
          ),
        ],
      ),
    );
  }
}

/// **Panel de upsell** en hoja inferior — equivalente móvil del overlay modal
/// `UpsellView.xaml`.
///
/// Sale desde abajo (no desde el centro): así las dos acciones quedan en la
/// zona del pulgar y el usuario puede cerrarlo deslizando, sin buscar una X
/// diminuta arriba a la derecha.
class PanelUpsell extends StatelessWidget {
  const PanelUpsell({
    super.key,
    required this.contenido,
    this.onMejorarPlan,
    this.onAhoraNo,
  });

  final ContenidoUpsell contenido;
  final VoidCallback? onMejorarPlan;
  final VoidCallback? onAhoraNo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Cabecera naranja de marca (degradado primario → presionado),
          // igual que el header de UpsellView.xaml.
          Container(
            padding: const EdgeInsets.all(Espacios.xl),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[t.primario, t.primarioPresionado],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      contenido.emoji,
                      style: const TextStyle(fontSize: 34),
                    ),
                    const SizedBox(width: Espacios.md),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Espacios.md,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: t.blanco.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(t.radioChip),
                        ),
                        child: Text(
                          '🔒 Requiere ${contenido.tierRequerido}',
                          style: tipos.chip.copyWith(color: t.blanco),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espacios.lg),
                Text(
                  contenido.titulo,
                  style: tipos.h1.copyWith(fontSize: 26, color: t.blanco),
                ),
                if (contenido.precio.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Espacios.xs),
                  Text(
                    contenido.precio,
                    style: tipos.cuerpoFuerte.copyWith(
                      color: t.primarioTinte,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Cuerpo
          Padding(
            padding: const EdgeInsets.all(Espacios.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(contenido.gancho, style: tipos.cuerpo),
                if (contenido.beneficios.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Espacios.lg),
                  ...contenido.beneficios.map((b) => _Beneficio(b)),
                ],
                const SizedBox(height: Espacios.xl),
                // CTA principal ARRIBA de la secundaria y a todo el ancho:
                // en móvil la fila "Ahora no | Mejora tu plan" del escritorio
                // deja la acción cara al borde derecho, el punto más incómodo
                // de alcanzar con el pulgar.
                BotonPrimario(
                  texto: 'Mejora tu plan',
                  onPressed: onMejorarPlan,
                ),
                const SizedBox(height: Espacios.sm),
                BotonFantasma(
                  texto: 'Ahora no',
                  color: t.muted,
                  expandido: true,
                  onPressed: onAhoraNo ?? () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre [PanelUpsell] como hoja inferior modal. Devuelve `true` si el usuario
/// pulsó "Mejora tu plan".
Future<bool> mostrarPanelUpsell(
  BuildContext context,
  ContenidoUpsell contenido, {
  VoidCallback? onMejorarPlan,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.tokens.blanco,
    builder: (ctx) => SingleChildScrollView(
      child: PanelUpsell(
        contenido: contenido,
        onMejorarPlan: () {
          Navigator.of(ctx).pop(true);
          onMejorarPlan?.call();
        },
        onAhoraNo: () => Navigator.of(ctx).pop(false),
      ),
    ),
  );
  return r ?? false;
}

/// Envuelve un widget para mostrarlo **deshabilitado con candado** sin sacarlo
/// de la pantalla: se ve atenuado, no responde y al tocarlo abre el upsell.
///
/// Es la traducción visual del Null Object deshabilitado de
/// `MOBILE-ARQUITECTURA.md` §5.2.
class CandadoSobre extends StatelessWidget {
  const CandadoSobre({
    super.key,
    required this.child,
    required this.bloqueado,
    this.contenido = ContenidoUpsell.generico,
    this.onMejorarPlan,
  });

  final Widget child;
  final bool bloqueado;
  final ContenidoUpsell contenido;
  final VoidCallback? onMejorarPlan;

  @override
  Widget build(BuildContext context) {
    if (!bloqueado) return child;
    final t = context.tokens;

    return Stack(
      children: <Widget>[
        Opacity(opacity: 0.4, child: IgnorePointer(child: child)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => mostrarPanelUpsell(
              context,
              contenido,
              onMejorarPlan: onMejorarPlan,
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.all(Espacios.sm),
                padding: const EdgeInsets.all(6),
                color: t.primarioTinte,
                child: IconoPos(
                  IconosPos.candado,
                  tamano: 18,
                  color: t.primarioPresionado,
                  respaldoEmoji: '🔒',
                  semantica: 'Bloqueado: requiere ${contenido.tierRequerido}',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Severidad del aviso de licencia.
enum AvisoLicenciaTipo {
  /// Vence pronto: informar sin alarmar (ámbar, no bloquea).
  porVencer,

  /// Dentro de los 7 días de gracia (`MOBILE-ARQUITECTURA.md` §5.4): la app
  /// sigue funcionando completa, pero se avisa todos los días.
  gracia,

  /// Vencida: las funciones premium ya cayeron a Base. Rojo, con salida clara.
  vencida,

  /// Reloj del dispositivo retrocedido (§5.5): sospechoso, no se degrada de
  /// golpe, pero se marca.
  relojSospechoso,
}

/// Franja de aviso de licencia. Va **arriba** del contenido, no tapa acciones,
/// y su botón queda al alcance del pulgar por ser una fila corta.
///
/// Tono deliberado: en gracia se avisa sin asustar (el negocio está vendiendo,
/// no es momento de un modal); vencida sí bloquea, pero con "Renovar" a un
/// toque.
class AvisoLicencia extends StatelessWidget {
  const AvisoLicencia({
    super.key,
    required this.tipo,
    required this.mensaje,
    this.textoAccion,
    this.onAccion,
    this.onCerrar,
  });

  final AvisoLicenciaTipo tipo;

  /// Mensaje ya redactado por `flutter-licencia` (incluye días restantes).
  final String mensaje;

  final String? textoAccion;
  final VoidCallback? onAccion;

  /// Si se pasa, muestra una X para descartar el aviso por hoy.
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;

    final (Color fondo, Color acento, String emoji) = switch (tipo) {
      AvisoLicenciaTipo.porVencer => (t.advertenciaTinte, t.advertencia, '⏳'),
      AvisoLicenciaTipo.gracia => (t.advertenciaTinte, t.advertencia, '⏳'),
      AvisoLicenciaTipo.vencida => (t.errorTinte, t.error, '🔒'),
      AvisoLicenciaTipo.relojSospechoso => (t.fondo, t.muted, '🕒'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Espacios.lg,
        vertical: Espacios.md,
      ),
      decoration: BoxDecoration(
        color: fondo,
        border: Border(left: BorderSide(color: acento, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: Espacios.md),
          Expanded(
            child: Text(
              mensaje,
              style: tipos.cuerpo.copyWith(fontSize: 15, color: t.navy),
            ),
          ),
          if (textoAccion != null) ...<Widget>[
            const SizedBox(width: Espacios.sm),
            BotonFantasma(
              texto: textoAccion!,
              color: acento,
              onPressed: onAccion,
            ),
          ],
          if (onCerrar != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCerrar,
              child: SizedBox(
                width: Toques.minimo,
                height: Toques.minimo,
                child: Center(
                  child: IconoPos(
                    IconosPos.cerrar,
                    tamano: 16,
                    color: t.muted,
                    semantica: 'Descartar aviso',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Beneficio extends StatelessWidget {
  const _Beneficio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacios.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '✓',
            style: context.tipos.cuerpoFuerte.copyWith(
              color: t.exito,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: Espacios.sm),
          Expanded(child: Text(texto, style: context.tipos.cuerpo)),
        ],
      ),
    );
  }
}
