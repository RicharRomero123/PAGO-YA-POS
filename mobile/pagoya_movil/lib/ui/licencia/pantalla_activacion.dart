/// Pantalla de activación — equivalente móvil de `ActivacionViewModel` +
/// `VentanaActivacion` del escritorio.
///
/// Tres caminos, y **los tres terminan en `ServicioLicencia.activarLicencia`**,
/// que vuelve a verificar la firma RSA y el `hwid` antes de persistir nada:
///
/// 1. **Con mi clave** (`PAGOYA-XXXX-…`) → `POST /devices`: vincula este móvil
///    como *asiento secundario* y baja el token firmado. Es el camino normal y
///    el único que deja la app lista para revalidar sola.
/// 2. **Sin internet — pegar o escanear el token**: activación 100 % offline,
///    igual que pegar el token en la PC.
/// 3. **Sin internet — importar `.lic`/`.txt`**: el equivalente móvil del flujo
///    USB, para negocios sin datos móviles.
///
/// Se muestra el **id del dispositivo** para que el dueño lo mande por WhatsApp
/// y soporte le emita la licencia: el mismo guion que el HWID en la PC.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import '../../composicion.dart';
import 'proveedores_licencia.dart';

/// Gate de arranque: sin licencia válida, esto es lo único que ve el usuario.
class PantallaActivacion extends ConsumerStatefulWidget {
  const PantallaActivacion({this.motivo, super.key});

  /// Motivo por el que no hay licencia válida (`EstadoLicencia.motivo`).
  final String? motivo;

  @override
  ConsumerState<PantallaActivacion> createState() => _PantallaActivacionState();
}

enum _Modo { clave, token }

class _PantallaActivacionState extends ConsumerState<PantallaActivacion> {
  final TextEditingController _clave = TextEditingController();
  final TextEditingController _token = TextEditingController();

  _Modo _modo = _Modo.clave;
  bool _ocupado = false;
  String? _error;
  String? _aviso;
  bool _mostrarSoporte = false;

  @override
  void dispose() {
    _clave.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<String> id = ref.watch(idDispositivoProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _encabezado(context),
                  const SizedBox(height: 24),
                  if (widget.motivo != null) ...<Widget>[
                    _Nota(texto: widget.motivo!),
                    const SizedBox(height: 16),
                  ],
                  _selectorDeModo(),
                  const SizedBox(height: 16),
                  if (_modo == _Modo.clave)
                    _formularioClave(context)
                  else
                    _formularioToken(context),
                  const SizedBox(height: 16),
                  if (_error != null) _Mensaje(texto: _error!, esError: true),
                  if (_aviso != null) _Mensaje(texto: _aviso!, esError: false),
                  if (_mostrarSoporte) ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _copiarDatosParaSoporte,
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Copiar datos para soporte'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  _bloqueIdDispositivo(context, id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- secciones

  Widget _encabezado(BuildContext context) => Column(
        children: <Widget>[
          Text(
            'PagoYa',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Activa tu licencia para empezar a vender',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );

  Widget _selectorDeModo() => SegmentedButton<_Modo>(
        segments: const <ButtonSegment<_Modo>>[
          ButtonSegment<_Modo>(
            value: _Modo.clave,
            label: Text('Con mi clave'),
            icon: Icon(Icons.vpn_key_outlined),
          ),
          ButtonSegment<_Modo>(
            value: _Modo.token,
            label: Text('Sin internet'),
            icon: Icon(Icons.wifi_off_outlined),
          ),
        ],
        selected: <_Modo>{_modo},
        onSelectionChanged: _ocupado ? null : _cambiarModo,
      );

  void _cambiarModo(Set<_Modo> seleccion) => setState(() {
        _modo = seleccion.first;
        _error = null;
        _aviso = null;
        _mostrarSoporte = false;
      });

  Widget _formularioClave(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _clave,
            enabled: !_ocupado,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Clave de licencia',
              hintText: 'PAGOYA-XXXX-XXXX-XXXX-XXXX',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _activarConClave(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ocupado ? null : _activarConClave,
            icon: _ocupado
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Activar este dispositivo'),
          ),
          const SizedBox(height: 8),
          Text(
            'Activar aquí no desconecta tu PC: el celular se registra como un '
            'dispositivo adicional de la misma licencia.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );

  Widget _formularioToken(BuildContext context) {
    final SelectorArchivoLicencia? selector =
        ref.watch(selectorArchivoLicenciaProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _token,
          enabled: !_ocupado,
          maxLines: 4,
          minLines: 2,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'Token de licencia',
            hintText: 'Pega aquí el texto largo que te enviamos',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _pegarDelPortapapeles,
              icon: const Icon(Icons.content_paste),
              label: const Text('Pegar'),
            ),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _escanearQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear QR'),
            ),
            if (selector != null)
              OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _importarArchivo(selector),
                icon: const Icon(Icons.folder_open),
                label: const Text('Desde archivo'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _ocupado ? null : _activarConToken,
          icon: const Icon(Icons.check),
          label: const Text('Activar'),
        ),
      ],
    );
  }

  Widget _bloqueIdDispositivo(BuildContext context, AsyncValue<String> id) {
    final String texto = id.maybeWhen(
      data: (String v) => v,
      orElse: () => '…',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '¿No tienes clave todavía?',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Envíanos este código por WhatsApp y te generamos tu licencia.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: SelectableText(
                texto,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Copiar código',
              icon: const Icon(Icons.copy),
              onPressed: id.hasValue ? () => _copiarTexto(texto) : null,
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- acciones

  Future<void> _activarConClave() async {
    setState(() {
      _ocupado = true;
      _error = null;
      _aviso = null;
      _mostrarSoporte = false;
    });

    final ResultadoActivacionAsiento r = await ref
        .read(vinculadorAsientoProvider)
        .vincularConClave(_clave.text);

    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _error = r.exito ? null : r.mensaje;
      _mostrarSoporte = r.requiereSoporte;
    });
    // Si salió bien, `GateLicencia` ya observa el estado nuevo y reemplaza esta
    // pantalla por el POS. No hace falta navegar desde aquí.
  }

  Future<void> _activarConToken() async {
    final String token = _token.text.trim();
    if (token.isEmpty) {
      setState(() {
        _aviso = null;
        _error = 'Pega el token de licencia que recibiste.';
      });
      return;
    }

    setState(() {
      _ocupado = true;
      _error = null;
      _aviso = null;
      _mostrarSoporte = false;
    });

    String? error;
    try {
      final EstadoLicencia estado =
          await ref.read(servicioLicenciaProvider).activarLicencia(token);
      if (!estado.estaActivada) {
        error = 'No se pudo activar: ${estado.motivo ?? 'token inválido'}';
      }
    } catch (e) {
      error = 'No se pudo activar la licencia: $e';
    }

    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _error = error;
      _mostrarSoporte = error != null;
    });
  }

  Future<void> _pegarDelPortapapeles() async {
    final ClipboardData? datos = await Clipboard.getData(Clipboard.kTextPlain);
    final String? texto = datos?.text?.trim();
    if (!mounted) return;

    if (texto == null || texto.isEmpty) {
      setState(() {
        _aviso = null;
        _error = 'No hay nada copiado.';
      });
      return;
    }

    setState(() {
      _token.text = texto;
      _error = null;
      _aviso = null;
    });
  }

  /// Escanea el token desde un QR. El escáner vive en `pagoya_hardware` y abre
  /// su propia pantalla con el navigator raíz, así que aquí no hay cámara.
  Future<void> _escanearQr() async {
    String? leido;
    try {
      leido = await ref.read(escanerCodigosProvider).escanearUnCodigo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aviso = null;
        _error = 'No se pudo usar la cámara: $e';
      });
      return;
    }

    if (!mounted || leido == null || leido.trim().isEmpty) return;
    setState(() {
      _token.text = leido!.trim();
      _error = null;
      _aviso = null;
    });
    await _activarConToken();
  }

  /// Importa el token desde un `.lic`/`.txt` — el equivalente móvil del flujo
  /// USB del escritorio, para cajas sin datos móviles.
  Future<void> _importarArchivo(SelectorArchivoLicencia selector) async {
    String? contenido;
    try {
      contenido = await selector.elegirYLeer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aviso = null;
        _error = 'No se pudo leer el archivo: $e';
      });
      return;
    }

    if (!mounted || contenido == null) return; // cancelado
    if (contenido.trim().isEmpty) {
      setState(() {
        _aviso = null;
        _error = 'El archivo está vacío.';
      });
      return;
    }

    setState(() {
      _token.text = contenido!.trim();
      _error = null;
      _aviso = null;
    });
    await _activarConToken();
  }

  Future<void> _copiarTexto(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    setState(() {
      _error = null;
      _aviso = 'Código copiado. Envíalo por WhatsApp para recibir tu licencia.';
    });
  }

  /// Copia id de dispositivo + motivo del fallo, para pegarlo en WhatsApp.
  /// Un cupo de dispositivos agotado es un caso de venta, no un callejón sin
  /// salida: hay que dejarle al dueño una acción concreta.
  Future<void> _copiarDatosParaSoporte() async {
    final String id = ref.read(idDispositivoProvider).valueOrNull ?? 'desconocido';
    await Clipboard.setData(
      ClipboardData(
        text: 'PagoYa — no puedo activar mi celular.\n'
            'Código de dispositivo: $id\n'
            'Mensaje: ${_error ?? 'sin detalle'}',
      ),
    );
    if (!mounted) return;
    setState(() {
      _aviso = 'Datos copiados. Pégalos en WhatsApp y te ayudamos.';
    });
  }
}

class _Nota extends StatelessWidget {
  const _Nota({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, required this.esError});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          esError ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: esError ? c.error : c.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: esError ? c.error : null),
          ),
        ),
      ],
    );
  }
}
