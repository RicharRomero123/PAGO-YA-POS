/// Tarjeta de upsell del tier **PagoYa Cloud**.
///
/// Se muestra cuando el token no trae el flag `cloud_sync` — el mismo caso en
/// que se inyecta el Null Object [ServicioSyncDeshabilitado] y en que el backend
/// responde 403.
///
/// El argumento de venta no es técnico: el dueño ya tiene sus ventas guardadas
/// en el teléfono y quiere que no se pierdan si el teléfono se pierde. Por eso
/// la tarjeta dice cuántas operaciones hay listas para respaldar: es su propio
/// dato, no una promesa abstracta.
library;

import 'package:flutter/material.dart';

class TarjetaUpsellCloud extends StatelessWidget {
  const TarjetaUpsellCloud({
    super.key,
    this.pendientes = 0,
    this.onQuieroCloud,
  });

  /// Operaciones acumuladas en el outbox local esperando un plan Cloud.
  final int pendientes;

  /// Lleva a la pantalla de activación/compra (dueño: `flutter-licencia`).
  final VoidCallback? onQuieroCloud;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colores.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lock_outline,
                      color: colores.onSecondaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Respaldo en la nube',
                          style: tema.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Incluido en el plan PagoYa Cloud',
                          style: tema.textTheme.bodySmall
                              ?.copyWith(color: colores.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (pendientes > 0) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colores.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tienes $pendientes ${pendientes == 1 ? "operación guardada" : "operaciones guardadas"} '
                  'en este equipo. Al activar Cloud se suben todas, sin perder ninguna.',
                  style: tema.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
            ],

            const _Beneficio(
              icono: Icons.cloud_done_outlined,
              texto: 'Copia de seguridad automática de tus ventas',
            ),
            const _Beneficio(
              icono: Icons.point_of_sale_outlined,
              texto: 'Varias cajas y sedes trabajando con el mismo inventario',
            ),
            const _Beneficio(
              icono: Icons.phone_iphone_outlined,
              texto: 'Reportes desde el celular, aunque no estés en el local',
            ),
            const _Beneficio(
              icono: Icons.restore_outlined,
              texto: 'Si pierdes o cambias el equipo, recuperas todo',
            ),

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onQuieroCloud,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Activar PagoYa Cloud'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Desde S/ 25 al mes',
                  style: tema.textTheme.bodySmall
                      ?.copyWith(color: colores.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Beneficio extends StatelessWidget {
  const _Beneficio({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: tema.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: tema.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
