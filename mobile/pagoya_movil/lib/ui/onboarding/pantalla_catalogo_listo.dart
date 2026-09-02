import 'package:flutter/material.dart';

import '../comun/comun.dart';
import '../tema/tema.dart';
import 'contrato_onboarding.dart';
import 'rubros_ui.dart';

/// Segundo paso del onboarding: **el catálogo ya está cargado**.
///
/// Es la pantalla que cumple la promesa del anuncio: el usuario eligió su rubro
/// hace dos segundos y ya ve sus categorías y sus productos con precio, sin
/// haber tecleado nada. Si aquí le mostráramos un formulario vacío, abandona.
///
/// Todo lo que se pinta viene en [resumen]; esta pantalla no consulta la base.
class PantallaCatalogoListo extends StatelessWidget {
  const PantallaCatalogoListo({
    super.key,
    required this.rubro,
    required this.resumen,
    required this.onEmpezar,
    this.onCambiarRubro,
  });

  final RubroUi rubro;
  final ResumenCatalogoRubro resumen;

  /// Entra al POS.
  final VoidCallback onEmpezar;

  /// Vuelve a la grilla (por si se equivocó de rubro). Sin esta salida el
  /// usuario se siente atrapado y desinstala.
  final VoidCallback? onCambiarRubro;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tipos = context.tipos;
    final vacio = resumen.productos.isEmpty;

    return Scaffold(
      backgroundColor: t.fondo,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacios.lg,
                  Espacios.xl,
                  Espacios.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        rubro.tieneIcono
                            ? IconoPos(
                                rubro.iconoImagen,
                                tamano: 40,
                                respaldoEmoji: rubro.emoji,
                              )
                            : Text(
                                rubro.emoji,
                                style: const TextStyle(fontSize: 34),
                              ),
                        const SizedBox(width: Espacios.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(rubro.nombre, style: tipos.cuerpoFuerte),
                              const SizedBox(height: 4),
                              ChipEstado.exito(
                                vacio
                                    ? 'Catálogo vacío, listo para llenar'
                                    : '${resumen.cantidadProductos} productos '
                                        'cargados',
                                iconoAsset: IconosPos.listo,
                                emoji: '✓',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espacios.lg),
                    Text(
                      vacio
                          ? 'Tu POS está listo'
                          : 'Tu catálogo ya está cargado',
                      style: tipos.h1,
                    ),
                    const SizedBox(height: Espacios.sm),
                    Text(
                      vacio
                          ? 'Elegiste empezar de cero: agrega tus productos '
                              'desde Inventario cuando quieras.'
                          : 'Puedes vender ahora mismo. Cambia precios, agrega '
                              'productos o borra los de ejemplo cuando quieras.',
                      style: tipos.muted,
                    ),

                    // Módulos que el rubro habilita (Mesas, Habitaciones,
                    // Vencimientos…). Es el momento de contarlo: explica por
                    // qué su app se ve distinta a la del vecino.
                    if (resumen.modulosExtra.isNotEmpty) ...<Widget>[
                      const TituloSeccion('Se activó para tu rubro'),
                      Wrap(
                        spacing: Espacios.sm,
                        runSpacing: Espacios.sm,
                        children: resumen.modulosExtra
                            .map(
                              (m) => ChipEstado(m, tono: TonoChip.marca),
                            )
                            .toList(),
                      ),
                    ],

                    if (resumen.categorias.isNotEmpty) ...<Widget>[
                      TituloSeccion(
                        'Categorías (${resumen.categorias.length})',
                      ),
                      Wrap(
                        spacing: Espacios.sm,
                        runSpacing: Espacios.sm,
                        children: resumen.categorias
                            .map((c) => ChipEstado(c))
                            .toList(),
                      ),
                    ],

                    if (!vacio) const TituloSeccion('Tus productos'),
                  ],
                ),
              ),
            ),

            if (vacio)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EstadoVacio(
                  titulo: 'Sin productos todavía',
                  detalle: 'Empieza a vender y agrega productos sobre la '
                      'marcha, o escanéalos con la cámara.',
                  iconoAsset: IconosPos.inventario,
                  emoji: '📦',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Espacios.lg,
                  0,
                  Espacios.lg,
                  Espacios.colchonBarraInferior,
                ),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: Espacios.md,
                    crossAxisSpacing: Espacios.md,
                    mainAxisExtent: Toques.tarjetaProducto,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final p = resumen.productos[i];
                      return TarjetaProducto(
                        nombre: p.nombre,
                        precio: p.precio,
                        categoria: p.categoria,
                        emoji: p.emoji,
                      );
                    },
                    childCount: resumen.productos.length,
                  ),
                ),
              ),
          ],
        ),
      ),

      // Acción primaria abajo, a todo el ancho: el pulgar ya está ahí.
      bottomNavigationBar: BarraAccionInferior(
        accionPrimaria: BotonCobrar(
          texto: 'Empezar a vender',
          onPressed: onEmpezar,
        ),
        accionSecundaria: onCambiarRubro == null
            ? null
            : BotonSecundario(
                texto: 'Cambiar',
                onPressed: onCambiarRubro,
              ),
      ),
    );
  }
}
