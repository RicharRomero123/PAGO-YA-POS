import 'dart:typed_data';

/// Modelo de datos del ticket. **DTO plano a propósito**: `pagoya_hardware`
/// NO depende de `pagoya_core`, para que la capa de plataforma se pueda testear
/// y evolucionar sin arrastrar el dominio ni la base de datos.
///
/// Quien construye estos objetos es la capa de UI/aplicación, mapeando desde
/// `Venta` / `DetalleVenta` de `pagoya_core`. La conversión de `Dinero` a
/// `double` la hace el llamador (`dinero.aDouble()`), igual que el escritorio
/// pasa `decimal` ya calculado al `TicketPrinterEscPos`.
library;

/// Método de pago tal como se imprime en el ticket.
///
/// Paridad literal con `PagoYa.Core.Enums.MetodoPago` (mismos ordinales) y con
/// `TicketPrinterEscPos.NombreMetodo`. **No cambiar las etiquetas**: un ticket
/// del celular y uno de la PC tienen que decir exactamente lo mismo.
enum MetodoPagoTicket {
  efectivo(0, 'Efectivo'),
  tarjeta(1, 'Tarjeta'),
  billeteraDigital(2, 'Yape / Plin'),
  transferencia(3, 'Transferencia'),
  credito(4, 'Credito');

  const MetodoPagoTicket(this.valor, this.etiqueta);

  /// Ordinal idéntico al enum de C#, para mapear sin ambigüedad.
  final int valor;

  /// Texto impreso en la línea "Pago :".
  final String etiqueta;

  static MetodoPagoTicket desdeValor(int valor) =>
      MetodoPagoTicket.values.firstWhere(
        (m) => m.valor == valor,
        orElse: () => MetodoPagoTicket.efectivo,
      );
}

/// Encabezado del negocio en el ticket.
///
/// Portado de `DatosNegocio`
/// (`src/PagoYa.Desktop/Servicios/Impresion/ITicketPrinter.cs`). Se omiten
/// `NombreImpresora` (en móvil la impresora se identifica por MAC, ver
/// `ImpresoraDisponible`) y `ColumnasTicket` (vive en
/// `ConfiguracionImpresion`, porque en móvil el ancho se cambia desde la misma
/// pantalla de impresión).
class DatosNegocioTicket {
  const DatosNegocioTicket({
    this.nombre = 'PagoYa',
    this.ruc = '',
    this.direccion = '',
    this.telefono = '',
    this.pieTicket = '¡Gracias por su compra!',
    this.logoPng,
  });

  final String nombre;
  final String ruc;
  final String direccion;
  final String telefono;

  /// Pie sugerido por rubro. Viene de `PlantillasRubro.PieTicket(clave)`
  /// portado a Dart por `flutter-datos`; aquí solo se imprime.
  final String pieTicket;

  /// Logo opcional (PNG). Solo se usa en el comprobante **imagen/PDF** que se
  /// manda por WhatsApp. El ESC/POS crudo no lo imprime, igual que en el
  /// escritorio (`TicketPrinterEscPos.ConstruirTicket` tampoco manda el logo:
  /// solo aparece en la vista previa).
  final Uint8List? logoPng;
}

/// Una línea de detalle del ticket. Portado de `DetalleVenta`.
class LineaVentaTicket {
  const LineaVentaTicket({
    required this.descripcion,
    required this.cantidad,
    required this.precioUnitario,
    required this.importe,
    this.notas = const <String>[],
  });

  /// Descripción congelada del producto (`DetalleVenta.DescripcionProducto`).
  final String descripcion;

  /// Permite decimales (venta por kilo).
  final double cantidad;

  final double precioUnitario;

  /// `cantidad * precioUnitario - descuento`, ya calculado por el dominio.
  final double importe;

  /// Modificadores / notas de cocina (rubros de comida). El escritorio aún no
  /// los imprime; en móvil se imprimen indentados debajo del ítem porque el
  /// caso de uso estrella es el mozo tomando comandas.
  final List<String> notas;
}

/// Ticket completo listo para imprimir o compartir. Portado de `Venta`.
class TicketVenta {
  const TicketVenta({
    required this.numero,
    required this.fechaHora,
    required this.metodoPago,
    required this.subTotal,
    required this.igv,
    required this.total,
    required this.lineas,
    required this.negocio,
    this.montoRecibido,
    this.titulo = 'NOTA DE VENTA',
    this.esReimpresion = false,
  });

  /// Correlativo legible. En móvil lleva prefijo de dispositivo
  /// (`M01-000123`), ver `docs/MOBILE-ARQUITECTURA.md` §6.
  final String numero;

  final DateTime fechaHora;
  final MetodoPagoTicket metodoPago;

  /// Suma de valores de venta sin IGV.
  final double subTotal;

  /// IGV 18 %.
  final double igv;

  final double total;

  /// Efectivo recibido, para calcular el vuelto. `null` si no aplica.
  final double? montoRecibido;

  final List<LineaVentaTicket> lineas;
  final DatosNegocioTicket negocio;

  /// Encabezado del documento. Se deja configurable porque el mismo motor
  /// imprime "NOTA DE VENTA", "PROFORMA", "COMANDA" o "PRE-CUENTA".
  final String titulo;

  /// Si es un "imprimir de nuevo", se estampa "** REIMPRESION **" para que el
  /// dueño distinga un duplicado de una venta nueva.
  final bool esReimpresion;

  /// Vuelto calculado. `null` si no hubo monto recibido o si no alcanza.
  double? get vuelto {
    final recibido = montoRecibido;
    if (recibido == null) return null;
    final v = recibido - total;
    return v > 0 ? v : null;
  }

  /// Nombre de archivo sugerido al compartir (sin extensión).
  String get nombreArchivoSugerido {
    final limpio = numero.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return 'PagoYa-$limpio';
  }
}