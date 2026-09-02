/// Gate de arranque del modelo "**todas** las tiers exigen activación".
///
/// Regla de negocio (CLAUDE.md y MOBILE-ARQUITECTURA §5.1): sin un token
/// auténtico instalado —firma RSA válida + dispositivo vinculado + dentro de la
/// ventana de expiración/gracia— la app **no entra al POS**, ni siquiera en el
/// plan Base. El instalador por sí solo es un cascarón.
///
/// `composicion.dart` ya expone `gateArranqueProvider`, que resuelve licencia →
/// onboarding → login. Este widget cubre **solo el primer escalón**, para que
/// `flutter-ui` pueda envolver su shell sin duplicar la regla:
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => GateLicencia(child: child ?? const SizedBox()),
/// )
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import '../../composicion.dart';
import '../comun/funcion_bloqueada.dart';
import 'pantalla_activacion.dart';
import 'proveedores_licencia.dart';

/// Muestra [child] solo si hay licencia activada; si no, la pantalla de
/// activación.
class GateLicencia extends ConsumerStatefulWidget {
  const GateLicencia({required this.child, super.key});

  /// El POS. Solo se construye con licencia válida.
  final Widget child;

  @override
  ConsumerState<GateLicencia> createState() => _GateLicenciaState();
}

class _GateLicenciaState extends ConsumerState<GateLicencia> {
  bool _avisoDescartado = false;

  @override
  void initState() {
    super.initState();
    // Revalidación silenciosa al abrir la app. No bloquea el arranque, no
    // muestra spinner y no puede tumbar el POS si el server no responde.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidar());
  }

  Future<void> _revalidar() async {
    try {
      await ref.read(revalidadorLicenciaProvider).revalidarSiCorresponde();
    } catch (_) {
      // Best-effort: la licencia local sigue mandando.
    }
  }

  @override
  Widget build(BuildContext context) {
    final EstadoLicencia licencia = ref.watch(estadoLicenciaProvider);

    if (!licencia.estaActivada) {
      return PantallaActivacion(motivo: licencia.motivo);
    }

    final AvisoLicencia? aviso = _avisoDescartado ? null : _construirAviso(licencia);
    if (aviso == null) return widget.child;

    return Column(
      children: <Widget>[
        SafeArea(bottom: false, child: aviso),
        Expanded(child: widget.child),
      ],
    );
  }

  /// Traduce el estado a la franja de aviso de `mobile-ux`. Nunca bloquea: en
  /// gracia el negocio está vendiendo y no es momento de un modal.
  AvisoLicencia? _construirAviso(EstadoLicencia licencia) {
    if (licencia.enPeriodoGracia) {
      return AvisoLicencia(
        tipo: AvisoLicenciaTipo.gracia,
        mensaje: _mensajeGracia(licencia),
        textoAccion: 'Renovar',
        onAccion: _irARenovar,
      );
    }

    if (licencia.relojSospechoso) {
      return AvisoLicencia(
        tipo: AvisoLicenciaTipo.relojSospechoso,
        mensaje: 'La fecha del equipo cambió bruscamente. Conéctate a internet '
            'para revalidar tu licencia.',
        textoAccion: 'Revalidar',
        onAccion: _revalidarAhora,
        onCerrar: _descartarAviso,
      );
    }

    final int? dias = licencia.diasParaExpirar(DateTime.now().toUtc());
    if (dias != null && dias >= 0 && dias <= 7) {
      return AvisoLicencia(
        tipo: AvisoLicenciaTipo.porVencer,
        mensaje: dias == 0
            ? 'Tu plan vence hoy. Renueva para no perder la nube ni la '
                'facturación.'
            : 'Tu plan vence en $dias ${dias == 1 ? 'día' : 'días'}.',
        textoAccion: 'Renovar',
        onAccion: _irARenovar,
        onCerrar: _descartarAviso,
      );
    }

    return null;
  }

  String _mensajeGracia(EstadoLicencia licencia) {
    final DateTime? expira = licencia.expiraUtc;
    if (expira == null) return 'Tu plan venció. Renueva para no perder tus datos.';

    final int diasUsados =
        DateTime.now().toUtc().difference(expira).inDays.clamp(0, 7);
    final int restantes = 7 - diasUsados;
    return 'Tu plan venció. Te ${restantes == 1 ? 'queda' : 'quedan'} '
        '$restantes ${restantes == 1 ? 'día' : 'días'} de cortesía — renueva '
        'para no perder la nube ni la facturación.';
  }

  void _descartarAviso() => setState(() => _avisoDescartado = true);

  void _revalidarAhora() {
    unawaited(
      ref.read(revalidadorLicenciaProvider).revalidarSiCorresponde(forzar: true),
    );
  }

  /// Lleva a la pantalla de licencia. `flutter-ui` es quien tiene el router y el
  /// número de WhatsApp de soporte; mientras no cablee la ruta, se abre la
  /// pantalla de activación, que ya explica cómo renovar.
  void _irARenovar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const PantallaActivacion(
          motivo: 'Renueva o cambia tu plan escribiendo tu nueva clave.',
        ),
      ),
    );
  }
}
