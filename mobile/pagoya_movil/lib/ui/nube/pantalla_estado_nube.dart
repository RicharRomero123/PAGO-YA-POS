/// Pantalla de estado de la nube.
///
/// Su única razón de existir: que el dueño pueda responder **"¿ya se subió mi
/// venta?"** sin llamar a soporte. Todo lo demás es secundario.
///
/// Muestra, en este orden de importancia:
///   1. Un veredicto en una línea ("Todo respaldado" / "3 operaciones sin subir").
///   2. Cuándo fue la última sincronización y qué la disparó.
///   3. Cuántas operaciones esperan y cuántas quedaron apartadas (dead-letter).
///   4. El botón "Sincronizar ahora".
///
/// Sin el flag `cloud_sync` la pantalla es el upsell del tier Cloud.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/nube/nube.dart';

import 'proveedores_nube.dart';
import 'tarjeta_upsell_cloud.dart';

class PantallaEstadoNube extends ConsumerStatefulWidget {
  const PantallaEstadoNube({
    super.key,
    this.onQuieroCloud,
    this.onRevincularEquipo,
    this.onRenovarLicencia,
  });

  /// Compra del tier Cloud (`sin_flag_cloud_sync`). Dueño: `flutter-licencia`.
  final VoidCallback? onQuieroCloud;

  /// Re-vinculación del asiento vía `POST /devices` (`asiento_revocado`).
  /// No es una compra: la licencia ya está pagada.
  final VoidCallback? onRevincularEquipo;

  /// Renovación de la suscripción (`token_expirado`). Tampoco es re-activar.
  final VoidCallback? onRenovarLicencia;

  @override
  ConsumerState<PantallaEstadoNube> createState() => _PantallaEstadoNubeState();
}

class _PantallaEstadoNubeState extends ConsumerState<PantallaEstadoNube> {
  bool _sincronizandoManual = false;

  @override
  void initState() {
    super.initState();
    // Contadores frescos al entrar, sin tocar la red.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(servicioSyncProvider).refrescarContadores());
  }

  @override
  Widget build(BuildContext context) {
    final servicio = ref.watch(servicioSyncProvider);
    // El stream puede no haber emitido todavía: caemos al último estado
    // conocido para no mostrar nunca un spinner vacío.
    final estado =
        ref.watch(estadoNubeProvider).valueOrNull ?? servicio.estadoActual;

    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo en la nube')),
      body: RefreshIndicator(
        onRefresh: _sincronizar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: estado.habilitada
              ? _contenidoActivo(context, estado)
              : _contenidoBloqueado(estado),
        ),
      ),
    );
  }

  // ===========================================================================
  //  Sin flag cloud_sync
  // ===========================================================================

  List<Widget> _contenidoBloqueado(EstadoNube estado) => [
        TarjetaUpsellCloud(
          pendientes: estado.pendientes,
          onQuieroCloud: widget.onQuieroCloud,
        ),
        const SizedBox(height: 16),
        const _NotaAlPie(
          'Tus ventas se siguen guardando en este equipo con normalidad. '
          'El plan Cloud solo agrega la copia en internet.',
        ),
      ];

  // ===========================================================================
  //  Con flag cloud_sync
  // ===========================================================================

  List<Widget> _contenidoActivo(BuildContext context, EstadoNube estado) {
    final plan = ref.read(planificadorSyncProvider);

    return [
      _Veredicto(estado: estado, sincronizando: _sincronizandoManual),
      const SizedBox(height: 16),

      Card(
        child: Column(
          children: [
            _Fila(
              icono: Icons.schedule,
              titulo: 'Última sincronización',
              valor: _formatearHace(estado.ultimaSyncUtc),
              detalle: plan.ultimoDisparo == null
                  ? null
                  : 'por ${plan.ultimoDisparo}',
            ),
            const Divider(height: 1),
            _Fila(
              icono: Icons.upload_outlined,
              titulo: 'Esperando subir',
              valor: '${estado.pendientes}',
              detalle: estado.pendientes == 0
                  ? 'No hay nada pendiente'
                  : 'Se subirán solas en cuanto haya internet',
            ),
            if (estado.enDeadLetter > 0) ...[
              const Divider(height: 1),
              _Fila(
                icono: Icons.error_outline,
                titulo: 'Con problemas',
                valor: '${estado.enDeadLetter}',
                detalle: 'Apartadas para que no bloqueen al resto',
                acento: true,
                accion: TextButton(
                  onPressed: _reintentarFallidas,
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ],
        ),
      ),

      if (estado.mensaje != null && !estado.ultimaSyncExitosa) ...[
        const SizedBox(height: 12),
        _Aviso(mensaje: estado.mensaje!, motivo: estado.motivo),
      ],

      // Tres problemas de licencia, tres salidas distintas. El backend los
      // distingue por `codigo` (§10) y aquí no se mezclan: ofrecerle un upsell
      // a quien ya pagó, o mandar a re-activar a quien solo tenía que renovar,
      // es como se pierde un cliente que no tenía ningún problema real.
      if (estado.motivo == MotivoFalloSync.dispositivoRevocado) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onRevincularEquipo ?? widget.onQuieroCloud,
            icon: const Icon(Icons.link),
            label: const Text('Volver a vincular este equipo'),
          ),
        ),
      ] else if (estado.motivo == MotivoFalloSync.tokenExpirado) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onRenovarLicencia ?? widget.onQuieroCloud,
            icon: const Icon(Icons.autorenew),
            label: const Text('Renovar mi licencia'),
          ),
        ),
      ] else if (estado.motivo == MotivoFalloSync.sinPermisoCloud) ...[
        const SizedBox(height: 12),
        TarjetaUpsellCloud(
          pendientes: estado.pendientes,
          onQuieroCloud: widget.onQuieroCloud,
        ),
      ],
      if (plan.ultimoMotivoOmision != null) ...[
        const SizedBox(height: 12),
        _Aviso(
            mensaje: plan.ultimoMotivoOmision!,
            motivo: MotivoFalloSync.datosMovilesBloqueados),
      ],

      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _sincronizandoManual || estado.sincronizando
              ? null
              : _sincronizar,
          icon: _sincronizandoManual || estado.sincronizando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          label: Text(_sincronizandoManual || estado.sincronizando
              ? 'Sincronizando…'
              : 'Sincronizar ahora'),
        ),
      ),

      const SizedBox(height: 20),
      Card(
        child: SwitchListTile(
          value: ref.watch(preferenciaDatosMovilesProvider),
          onChanged: (v) => ref
              .read(preferenciaDatosMovilesProvider.notifier)
              .establecer(v),
          secondary: const Icon(Icons.signal_cellular_alt),
          title: const Text('Usar datos móviles'),
          subtitle: const Text(
              'Si lo desactivas, los respaldos grandes esperan a una red Wi-Fi.'),
        ),
      ),

      const SizedBox(height: 16),
      const _NotaAlPie(
        'Tus ventas se guardan primero en este equipo y después se copian a la '
        'nube. Aunque no haya internet, puedes seguir cobrando: nada se pierde.',
      ),
    ];
  }

  // ===========================================================================
  //  Acciones
  // ===========================================================================

  Future<void> _sincronizar() async {
    if (_sincronizandoManual) return;
    setState(() => _sincronizandoManual = true);

    // `sincronizarAhora` NUNCA lanza (regla crítica del módulo): devuelve un
    // ResultadoSync con el motivo. Aun así, catch por si el día de mañana
    // alguien cambia esa garantía sin querer.
    ResultadoSync resultado;
    try {
      resultado = await ref.read(planificadorSyncProvider).sincronizarAhora();
    } catch (ex) {
      resultado = ResultadoSync(
          exito: false, mensaje: 'No se pudo sincronizar: $ex');
    }

    if (!mounted) return;
    setState(() => _sincronizandoManual = false);
    _mostrar(resultado.exito
        ? (resultado.enviados == 0 && resultado.recibidos == 0
            ? 'Ya estaba todo al día.'
            : 'Listo: ${resultado.enviados} subidas, ${resultado.recibidos} recibidas.')
        : (resultado.mensaje ?? 'No se pudo sincronizar.'));
  }

  Future<void> _reintentarFallidas() async {
    final n = await ref.read(almacenOutboxProvider).reencolarDeadLetter();
    await ref.read(servicioSyncProvider).refrescarContadores();
    if (!mounted) return;
    _mostrar(n == 0
        ? 'No hay operaciones que reintentar.'
        : '$n operaciones vuelven a la cola.');
    await _sincronizar();
  }

  void _mostrar(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }
}

// =============================================================================
//  Piezas
// =============================================================================

class _Veredicto extends StatelessWidget {
  const _Veredicto({required this.estado, required this.sincronizando});

  final EstadoNube estado;
  final bool sincronizando;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    final (IconData icono, String titulo, String detalle, Color fondo, Color tinta) =
        switch (estado) {
      _ when sincronizando || estado.sincronizando => (
          Icons.sync,
          'Sincronizando…',
          'Subiendo tus operaciones a la nube.',
          colores.secondaryContainer,
          colores.onSecondaryContainer,
        ),
      _ when estado.pendientes == 0 && estado.ultimaSyncExitosa => (
          Icons.cloud_done,
          'Todo respaldado',
          'No queda ninguna operación por subir.',
          colores.primaryContainer,
          colores.onPrimaryContainer,
        ),
      _ when estado.pendientes == 0 => (
          Icons.cloud_queue,
          'Sin nada por subir',
          'Aún no se ha confirmado una sincronización.',
          colores.surfaceContainerHighest,
          colores.onSurface,
        ),
      _ => (
          Icons.cloud_upload_outlined,
          '${estado.pendientes} ${estado.pendientes == 1 ? "operación sin subir" : "operaciones sin subir"}',
          'Están guardadas en este equipo. Se subirán solas.',
          colores.tertiaryContainer,
          colores.onTertiaryContainer,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration:
          BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 34, color: tinta),
          const SizedBox(height: 12),
          Text(titulo,
              style: tema.textTheme.headlineSmall
                  ?.copyWith(color: tinta, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(detalle, style: tema.textTheme.bodyMedium?.copyWith(color: tinta)),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.detalle,
    this.acento = false,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final String? detalle;
  final bool acento;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = acento ? tema.colorScheme.error : tema.colorScheme.primary;

    return ListTile(
      leading: Icon(icono, color: color),
      title: Text(titulo),
      subtitle: detalle == null ? null : Text(detalle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valor,
              style: tema.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          if (accion != null) ...[const SizedBox(width: 4), accion!],
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, required this.motivo});

  final String mensaje;
  final MotivoFalloSync motivo;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    // Sin red no es un error del negocio: es lo normal en una bodega, y se
    // avisa en tono neutro. Se pintan en rojo los motivos que piden una acción
    // del dueño: los bloqueantes y la licencia vencida (que no bloquea el
    // ciclo, porque se renueva sola, pero sí hay que pagarla).
    final grave =
        esMotivoBloqueante(motivo) || motivo == MotivoFalloSync.tokenExpirado;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: grave ? colores.errorContainer : colores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(grave ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: grave ? colores.onErrorContainer : colores.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensaje,
                style: TextStyle(
                    color: grave
                        ? colores.onErrorContainer
                        : colores.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _NotaAlPie extends StatelessWidget {
  const _NotaAlPie(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(texto,
          style: tema.textTheme.bodySmall
              ?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
    );
  }
}

// =============================================================================

/// "hace 3 min", "ayer", "nunca". Sin `intl`: son cuatro casos y no justifica
/// una dependencia más en el APK.
String _formatearHace(DateTime? utc) {
  if (utc == null) return 'Nunca';
  final d = DateTime.now().toUtc().difference(utc);
  if (d.isNegative) return 'Recién';
  if (d.inSeconds < 60) return 'Recién';
  if (d.inMinutes < 60) return 'Hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'Hace ${d.inHours} h';
  if (d.inDays == 1) return 'Ayer';
  return 'Hace ${d.inDays} días';
}
