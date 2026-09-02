import 'package:pagoya_core/pagoya_core.dart' show IdentidadDispositivo;

import 'contrato_identidad.dart';
import 'identidad_segura.dart';

/// Implementación **falsa** de [IdentidadDispositivo], en memoria.
///
/// Los tests de `flutter-licencia` la usan para fijar un id conocido y así
/// verificar la vinculación de asientos sin Keychain ni Keystore:
///
/// ```dart
/// final identidad = IdentidadDispositivoFalsa(
///   id: '11111111-1111-4111-8111-111111111111',
/// );
/// ```
///
/// Sin [id] genera un UUID v4 real en la primera llamada, igual que la
/// implementación de verdad.
class IdentidadDispositivoFalsa
    implements IdentidadDispositivo, IdentidadDispositivoExtendida {
  IdentidadDispositivoFalsa({
    String? id,
    this.nombre = 'Emulador de pruebas',
    this.modelo = 'sdk_gphone64_x86_64',
    this.fabricante = 'Google',
    this.plataforma = 'android',
    this.versionSistema = '14',
    this.esFisico = false,
    this.fallar = false,
  }) : _id = id;

  String? _id;

  final String nombre;
  final String modelo;
  final String fabricante;
  final String plataforma;
  final String versionSistema;
  final bool esFisico;

  /// Si es `true`, [obtenerIdDispositivo] lanza: simula el almacén seguro
  /// inaccesible. `pagoya_core` trata ese caso como fallo transitorio y NO
  /// degrada la licencia — este interruptor existe para probarlo.
  final bool fallar;

  /// Cuántas veces se regeneró el id. Sirve para el assert de "no regeneres
  /// solo ante un error de lectura".
  int regeneraciones = 0;

  @override
  Future<String> obtenerIdDispositivo() async {
    if (fallar) throw StateError('almacén seguro no disponible');
    return _id ??= IdentidadDispositivoSegura.generarUuidV4();
  }

  @override
  Future<String> obtenerNombreDispositivo() async => nombre;

  @override
  Future<String> obtenerPlataforma() async => plataforma;

  @override
  Future<bool> yaExiste() async => _id != null;

  @override
  Future<String> regenerar() async {
    regeneraciones++;
    return _id = IdentidadDispositivoSegura.generarUuidV4();
  }

  @override
  Future<InfoDispositivo> obtenerInfo() async => InfoDispositivo(
        id: await obtenerIdDispositivo(),
        nombre: nombre,
        modelo: modelo,
        fabricante: fabricante,
        plataforma: plataforma,
        versionSistema: versionSistema,
        esFisico: esFisico,
      );
}