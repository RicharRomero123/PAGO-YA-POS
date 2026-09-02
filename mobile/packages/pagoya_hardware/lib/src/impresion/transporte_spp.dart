import 'dart:io';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../modelo/resultados.dart';
import '../permisos/permisos_hardware.dart';
import 'contrato_impresora.dart';
import 'transporte.dart';

/// Transporte **Bluetooth clásico (SPP / RFCOMM)** vía `print_bluetooth_thermal`.
///
/// Es el transporte **prioritario**: la enorme mayoría de las térmicas baratas
/// que se compran en Perú (clones "POS-58", Xprinter XP-58IIH / XP-P323B,
/// Goojprt PT-210 y MTP-II, Bixolon SPP-R200III, Epson TM-P20) hablan SPP, no
/// BLE.
///
/// ## Dos cosas que hay que saber sí o sí
///
/// 1. **SPP no descubre dispositivos desde la app.** Solo lista los que ya
///    están emparejados en *Ajustes > Bluetooth* de Android. Si la impresora
///    no aparece, la solución es emparejarla ahí (PIN habitual `0000` o
///    `1234`), no reintentar en la app. La UI debe decirlo con esas palabras y
///    ofrecer un botón que abra los ajustes de Bluetooth.
/// 2. **iOS no soporta SPP** para apps de terceros sin certificación MFi de
///    Apple. Es una restricción de la plataforma. En iOS este transporte
///    reporta [soportado] `false` y la impresión cae al transporte BLE.
class TransporteSpp implements TransporteImpresora {
  TransporteSpp({PermisosHardware? permisos})
      : _permisos = permisos ?? const PermisosHardware();

  final PermisosHardware _permisos;

  ImpresoraDisponible? _actual;

  @override
  TipoConexionImpresora get tipo => TipoConexionImpresora.sppClasico;

  @override
  Future<bool> get soportado async => Platform.isAndroid;

  @override
  Future<bool> get adaptadorEncendido async {
    if (!Platform.isAndroid) return false;
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get conectado async {
    if (!Platform.isAndroid) return false;
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ImpresoraDisponible>> buscar({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!Platform.isAndroid) return const [];
    try {
      final permiso = await _permisos.asegurarBluetooth();
      if (!permiso.concedidoOk) return const [];
      if (!await adaptadorEncendido) return const [];

      // `pairedBluetooths` devuelve SOLO dispositivos emparejados desde los
      // ajustes del sistema. No es un escaneo.
      final emparejados = await PrintBluetoothThermal.pairedBluetooths;
      return emparejados
          .map(
            // Ojo: el campo del plugin se llama `macAdress` (sic, con la
            // errata). No es un typo nuestro.
            (b) => ImpresoraDisponible(
              id: b.macAdress,
              nombre: b.name.trim().isEmpty ? b.macAdress : b.name.trim(),
              tipo: TipoConexionImpresora.sppClasico,
              emparejada: true,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ResultadoImpresion> conectar(ImpresoraDisponible impresora) async {
    if (!Platform.isAndroid) {
      return ResultadoImpresion.fallo(
        'En iPhone no se puede usar una impresora Bluetooth clásica. '
        'Necesitas una impresora Bluetooth LE.',
        CausaFalloImpresion.noSoportado,
      );
    }
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

      // Si ya hay un canal abierto a OTRA impresora, hay que cerrarlo: el
      // plugin mantiene una sola conexión.
      if (_actual != null && _actual != impresora && await conectado) {
        await desconectar();
      }

      final ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: impresora.id,
      );
      if (!ok) {
        return ResultadoImpresion.fallo(
          'No se pudo conectar con "${impresora.nombre}". Revisa que esté '
          'encendida, con papel y cerca del teléfono.',
          CausaFalloImpresion.sinConexion,
        );
      }
      _actual = impresora;
      return ResultadoImpresion.ok();
    } catch (_) {
      return ResultadoImpresion.fallo(
        'No se pudo conectar con la impresora. Apágala y vuelve a encenderla.',
        CausaFalloImpresion.sinConexion,
      );
    }
  }

  @override
  Future<ResultadoImpresion> escribir(List<int> bytes) async {
    if (!Platform.isAndroid) {
      return ResultadoImpresion.fallo(
        'Impresión Bluetooth clásica no disponible en este dispositivo.',
        CausaFalloImpresion.noSoportado,
      );
    }
    try {
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) {
        return ResultadoImpresion.fallo(
          'La impresora no recibió el ticket. Puede haberse quedado sin papel '
          'o sin batería.',
          CausaFalloImpresion.escrituraFallida,
        );
      }
      return ResultadoImpresion.ok();
    } catch (_) {
      return ResultadoImpresion.fallo(
        'Se cortó la conexión con la impresora mientras se imprimía.',
        CausaFalloImpresion.escrituraFallida,
      );
    }
  }

  @override
  Future<void> desconectar() async {
    if (!Platform.isAndroid) return;
    try {
      // `disconnect` es un getter que devuelve Future<bool> en este plugin.
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Desconectar nunca debe fallar hacia arriba.
    }
    _actual = null;
  }

  @override
  Future<void> liberar() => desconectar();
}