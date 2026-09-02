/// Resultados compartidos por las operaciones de hardware.
///
/// **Regla del paquete:** ninguna operación de hardware lanza excepciones hacia
/// la UI. Todas devuelven un resultado con un mensaje escrito para el dueño de
/// una bodega, no un stack trace. Si el hardware falla, la venta ya está
/// guardada y el flujo sigue.
library;

/// Causa de un fallo de impresión. La UI usa el código para decidir qué botón
/// ofrecer (reintentar, elegir impresora, activar Bluetooth, compartir por
/// WhatsApp); el [ResultadoImpresion.mensaje] es lo que se muestra.
enum CausaFalloImpresion {
  /// Todo bien.
  ninguna,

  /// El usuario nunca eligió impresora.
  sinImpresoraConfigurada,

  /// El Bluetooth del teléfono está apagado.
  bluetoothApagado,

  /// Faltan permisos de Bluetooth (Android 12+) o el usuario los denegó.
  permisoDenegado,

  /// No se pudo conectar / la impresora está apagada o fuera de alcance.
  sinConexion,

  /// Se conectó pero la escritura falló a mitad de camino.
  escrituraFallida,

  /// La plataforma no soporta el transporte (p. ej. SPP clásico en iOS).
  noSoportado,

  /// Cualquier otra cosa.
  desconocida,
}

/// Resultado de un intento de impresión.
///
/// Portado de `ResultadoImpresion` del escritorio
/// (`src/PagoYa.Desktop/Servicios/Impresion/ITicketPrinter.cs`), con un
/// [codigo] extra porque en móvil hay más modos de fallo (Bluetooth apagado,
/// permisos, fuera de alcance).
class ResultadoImpresion {
  const ResultadoImpresion({
    required this.exito,
    this.mensaje,
    this.codigo = CausaFalloImpresion.ninguna,
  });

  /// Éxito.
  factory ResultadoImpresion.ok([String? mensaje]) =>
      ResultadoImpresion(exito: true, mensaje: mensaje);

  /// Fallo con mensaje entendible por el usuario final.
  factory ResultadoImpresion.fallo(
    String mensaje, [
    CausaFalloImpresion codigo = CausaFalloImpresion.desconocida,
  ]) =>
      ResultadoImpresion(exito: false, mensaje: mensaje, codigo: codigo);

  final bool exito;

  /// Texto listo para mostrar. Nunca contiene una excepción cruda.
  final String? mensaje;

  final CausaFalloImpresion codigo;

  /// `true` si reintentar tiene sentido (la impresora podría volver).
  bool get vaLaPenaReintentar =>
      !exito &&
      (codigo == CausaFalloImpresion.sinConexion ||
          codigo == CausaFalloImpresion.escrituraFallida);

  @override
  String toString() =>
      'ResultadoImpresion(exito: $exito, codigo: $codigo, mensaje: $mensaje)';
}

/// Resultado de compartir un comprobante.
class ResultadoCompartir {
  const ResultadoCompartir({
    required this.exito,
    this.mensaje,
    this.rutaArchivo,
    this.cancelado = false,
  });

  factory ResultadoCompartir.ok({String? rutaArchivo}) =>
      ResultadoCompartir(exito: true, rutaArchivo: rutaArchivo);

  factory ResultadoCompartir.cancelado() =>
      const ResultadoCompartir(exito: false, cancelado: true);

  factory ResultadoCompartir.fallo(String mensaje) =>
      ResultadoCompartir(exito: false, mensaje: mensaje);

  final bool exito;
  final String? mensaje;

  /// Ruta del archivo temporal generado (útil para reintentar o para adjuntarlo
  /// a otra cosa). Vive en el directorio temporal del sistema.
  final String? rutaArchivo;

  /// El usuario cerró la hoja de compartir sin elegir app.
  final bool cancelado;

  @override
  String toString() =>
      'ResultadoCompartir(exito: $exito, cancelado: $cancelado, mensaje: $mensaje)';
}

/// Estado de un permiso de sistema, sin filtrar el enum de `permission_handler`
/// hacia el resto de la app.
enum EstadoPermiso {
  concedido,
  denegado,

  /// Denegado con "no volver a preguntar": hay que mandar al usuario a Ajustes.
  denegadoPermanentemente,

  /// El dispositivo no tiene el hardware (emulador sin cámara, tablet sin BT).
  noDisponible,
}

extension EstadoPermisoX on EstadoPermiso {
  bool get concedidoOk => this == EstadoPermiso.concedido;

  /// Mensaje listo para mostrar cuando el permiso no está concedido.
  String get explicacion => switch (this) {
        EstadoPermiso.concedido => '',
        EstadoPermiso.denegado =>
          'Necesitamos tu permiso para continuar. Toca "Permitir" cuando el '
              'teléfono lo pregunte.',
        EstadoPermiso.denegadoPermanentemente =>
          'El permiso está bloqueado. Abre Ajustes > Aplicaciones > PagoYa > '
              'Permisos y actívalo.',
        EstadoPermiso.noDisponible =>
          'Este teléfono no tiene ese hardware disponible.',
      };
}