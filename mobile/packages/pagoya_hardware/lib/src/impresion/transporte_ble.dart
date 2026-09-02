import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../modelo/resultados.dart';
import '../permisos/permisos_hardware.dart';
import 'contrato_impresora.dart';
import 'transporte.dart';

/// Transporte **Bluetooth LE (GATT)** vía `flutter_blue_plus`.
///
/// Es el **respaldo** de `TransporteSpp`, no la opción principal: se usa para
/// las térmicas modernas que solo exponen GATT (varias Munbyn, Xprinter 2023+,
/// algunas Phomemo) y es la **única** opción en iOS, donde Apple no deja usar
/// SPP clásico sin certificación MFi.
///
/// ## Detalles que hacen que funcione en la calle
///
/// - No se hardcodea un UUID de servicio: se recorren todos los servicios y se
///   toma la primera característica **escribible**, prefiriendo las conocidas
///   de impresoras térmicas (ver [_caracteristicasPreferidas]). Los clones
///   chinos cambian de UUID entre lotes del mismo modelo.
/// - Se pide MTU alto y se **trocea** el flujo ESC/POS: si mandas 4 KB de golpe
///   por BLE, la impresora imprime a medias o se cuelga.
/// - Entre trozos va una pausa corta. Sin ella, los buffers pequeños de estas
///   impresoras se desbordan y salen líneas cortadas.
class TransporteBle implements TransporteImpresora {
  TransporteBle({PermisosHardware? permisos})
      : _permisos = permisos ?? const PermisosHardware();

  final PermisosHardware _permisos;

  BluetoothDevice? _dispositivo;
  BluetoothCharacteristic? _escritura;
  StreamSubscription<BluetoothConnectionState>? _subEstado;

  /// Tamaño de trozo si no se pudo negociar MTU. 20 bytes es el mínimo BLE
  /// garantizado (ATT_MTU 23 - 3 de cabecera).
  static const int _trozoMinimo = 20;

  /// Pausa entre trozos. Empírico: por debajo de ~15 ms varias térmicas
  /// baratas pierden datos.
  static const Duration _pausaEntreTrozos = Duration(milliseconds: 20);

  /// Servicios/características habituales de impresoras térmicas BLE. Se
  /// prueban en este orden antes de caer al "cualquier característica
  /// escribible".
  static const List<String> _caracteristicasPreferidas = <String>[
    '0000ff02-0000-1000-8000-00805f9b34fb', // clones chinos genéricos
    '00002af1-0000-1000-8000-00805f9b34fb', // servicio 18f0 (impresión)
    '49535343-8841-43f4-a8d4-ecbe34729bb3', // ISSC / Microchip transparent UART
    '0000ffe1-0000-1000-8000-00805f9b34fb', // HM-10 y derivados
  ];

  @override
  TipoConexionImpresora get tipo => TipoConexionImpresora.ble;

  @override
  Future<bool> get soportado async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get adaptadorEncendido async {
    try {
      if (!await FlutterBluePlus.isSupported) return false;
      final estado = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      return estado == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get conectado async {
    final d = _dispositivo;
    if (d == null || _escritura == null) return false;
    try {
      return d.isConnected;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ImpresoraDisponible>> buscar({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final permiso = await _permisos.asegurarBluetooth();
      if (!permiso.concedidoOk) return const [];
      if (!await adaptadorEncendido) return const [];

      final encontrados = <String, ImpresoraDisponible>{};

      // Dispositivos ya conectados al sistema (p. ej. reconectados por Android
      // tras un corte). No aparecen en el escaneo.
      try {
        for (final d in await FlutterBluePlus.systemDevices(const <Guid>[])) {
          final nombre = d.platformName.trim();
          if (nombre.isEmpty) continue;
          encontrados[d.remoteId.str] = ImpresoraDisponible(
            id: d.remoteId.str,
            nombre: nombre,
            tipo: TipoConexionImpresora.ble,
            emparejada: true,
          );
        }
      } catch (_) {
        // No es crítico.
      }

      final sub = FlutterBluePlus.onScanResults.listen((resultados) {
        for (final r in resultados) {
          final nombre = r.device.platformName.trim().isEmpty
              ? r.advertisementData.advName.trim()
              : r.device.platformName.trim();
          // Sin nombre no hay forma de que el usuario la reconozca en la lista.
          if (nombre.isEmpty) continue;
          encontrados[r.device.remoteId.str] = ImpresoraDisponible(
            id: r.device.remoteId.str,
            nombre: nombre,
            tipo: TipoConexionImpresora.ble,
            intensidadSenal: r.rssi,
          );
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await Future<void>.delayed(timeout);
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      final lista = encontrados.values.toList()
        ..sort((a, b) =>
            (b.intensidadSenal ?? -999).compareTo(a.intensidadSenal ?? -999));
      return lista;
    } catch (_) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      return const [];
    }
  }

  @override
  Future<ResultadoImpresion> conectar(ImpresoraDisponible impresora) async {
    try {
      final permiso = await _permisos.asegurarBluetooth();
      if (!permiso.concedidoOk) {
        return ResultadoImpresion.fallo(
          'PagoYa necesita permiso de Bluetooth para hablar con la impresora. '
          '${permiso.explicacion}',
          CausaFalloImpresion.permisoDenegado,
        );
      }
      if (!await adaptadorEncendido) {
        return ResultadoImpresion.fallo(
          'El Bluetooth del teléfono está apagado. Actívalo e intenta de nuevo.',
          CausaFalloImpresion.bluetoothApagado,
        );
      }

      await desconectar();

      final device = BluetoothDevice.fromId(impresora.id);
      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );

      // MTU alto = menos trozos = impresión más rápida. En iOS no se negocia
      // (lo hace el sistema); el intento falla silenciosamente y seguimos.
      try {
        await device.requestMtu(512);
      } catch (_) {}

      final caracteristica = await _buscarCaracteristicaEscritura(device);
      if (caracteristica == null) {
        await device.disconnect();
        return ResultadoImpresion.fallo(
          '"${impresora.nombre}" se conectó pero no parece ser una impresora '
          'compatible.',
          CausaFalloImpresion.noSoportado,
        );
      }

      _dispositivo = device;
      _escritura = caracteristica;

      // Si el enlace se cae (batería, distancia), limpiamos para que el
      // siguiente ticket reconecte en vez de escribir a un canal muerto.
      await _subEstado?.cancel();
      _subEstado = device.connectionState.listen((estado) {
        if (estado == BluetoothConnectionState.disconnected) {
          _escritura = null;
        }
      });

      return ResultadoImpresion.ok();
    } catch (_) {
      return ResultadoImpresion.fallo(
        'No se pudo conectar con "${impresora.nombre}". Revisa que esté '
        'encendida y cerca del teléfono.',
        CausaFalloImpresion.sinConexion,
      );
    }
  }

  Future<BluetoothCharacteristic?> _buscarCaracteristicaEscritura(
    BluetoothDevice device,
  ) async {
    final servicios = await device.discoverServices();
    final escribibles = <BluetoothCharacteristic>[];
    for (final s in servicios) {
      for (final c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          escribibles.add(c);
        }
      }
    }
    if (escribibles.isEmpty) return null;

    for (final uuid in _caracteristicasPreferidas) {
      for (final c in escribibles) {
        if (c.uuid.str128.toLowerCase() == uuid) return c;
      }
    }
    // Ninguna conocida: la primera escribible suele ser la correcta.
    return escribibles.first;
  }

  @override
  Future<ResultadoImpresion> escribir(List<int> bytes) async {
    final c = _escritura;
    final d = _dispositivo;
    if (c == null || d == null) {
      return ResultadoImpresion.fallo(
        'La impresora no está conectada.',
        CausaFalloImpresion.sinConexion,
      );
    }
    try {
      final mtu = d.mtuNow;
      // -3 por la cabecera ATT. Nunca por debajo del mínimo garantizado.
      final trozo = mtu > _trozoMinimo + 3 ? mtu - 3 : _trozoMinimo;
      final sinRespuesta = c.properties.writeWithoutResponse;

      for (var i = 0; i < bytes.length; i += trozo) {
        final fin = (i + trozo < bytes.length) ? i + trozo : bytes.length;
        await c.write(bytes.sublist(i, fin), withoutResponse: sinRespuesta);
        if (fin < bytes.length) {
          await Future<void>.delayed(_pausaEntreTrozos);
        }
      }
      return ResultadoImpresion.ok();
    } catch (_) {
      _escritura = null;
      return ResultadoImpresion.fallo(
        'Se cortó la conexión con la impresora mientras se imprimía.',
        CausaFalloImpresion.escrituraFallida,
      );
    }
  }

  @override
  Future<void> desconectar() async {
    await _subEstado?.cancel();
    _subEstado = null;
    _escritura = null;
    final d = _dispositivo;
    _dispositivo = null;
    if (d == null) return;
    try {
      await d.disconnect();
    } catch (_) {}
  }

  @override
  Future<void> liberar() => desconectar();
}