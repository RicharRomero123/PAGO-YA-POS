import 'dart:typed_data';

import '../impresion/configuracion_impresion.dart';
import '../modelo/resultados.dart';
import '../modelo/ticket.dart';

/// Formato del comprobante que se comparte.
enum FormatoComprobante {
  /// **PNG. Es el formato por defecto y el que hay que usar por defecto.**
  /// WhatsApp muestra la imagen dentro del chat: el cliente la ve sin abrir
  /// nada. Un PDF llega como adjunto y hay que tocarlo para verlo — se pierde
  /// la mitad de la gracia.
  imagen,

  /// PDF con el ancho del rollo. Útil cuando el cliente pide "el archivo" o
  /// para reenviarlo por correo al contador.
  pdf,

  /// Solo texto. Respaldo si no se pudo renderizar (teléfono muy justo de
  /// memoria) y opción para quien tiene mala señal.
  texto,
}

/// **Compartir el comprobante, principalmente por WhatsApp.**
///
/// Es una función de primera clase del producto, no un extra: junto al escáner,
/// es el argumento que más vende la app móvil frente al POS de PC. El bodeguero
/// cobra, y antes de que el cliente se dé la vuelta ya le mandó el ticket al
/// celular.
///
/// También es la **red de seguridad de la impresión**: si la térmica no
/// respondió, la UI ofrece "Enviar por WhatsApp" y la venta queda igual de
/// cerrada. Por eso [compartirComprobante] no depende de que haya impresora ni
/// de que el Bluetooth funcione.
abstract interface class CompartirArchivo {
  /// Genera el comprobante en [formato] y abre la hoja de compartir del
  /// sistema, donde el usuario elige WhatsApp (o correo, o Drive).
  ///
  /// [mensaje] acompaña al archivo. Si es `null` se usa un texto por defecto
  /// con el nombre del negocio y el total.
  Future<ResultadoCompartir> compartirComprobante(
    TicketVenta ticket, {
    FormatoComprobante formato = FormatoComprobante.imagen,
    ConfiguracionImpresion config = const ConfiguracionImpresion(),
    String? mensaje,
  });

  /// Abre el chat de WhatsApp de un número concreto con un mensaje escrito.
  ///
  /// Ojo: el esquema `whatsapp://` **no permite adjuntar archivos**. Sirve para
  /// mandar el detalle en texto o un enlace. Para mandar la imagen del ticket
  /// hay que usar [compartirComprobante] y que el usuario elija el contacto.
  ///
  /// [telefono] en formato internacional sin `+` ni espacios (`51987654321`).
  /// Si va sin prefijo de 2 dígitos se asume Perú (51).
  Future<ResultadoCompartir> abrirChatWhatsApp({
    required String telefono,
    required String mensaje,
  });

  /// `true` si hay alguna versión de WhatsApp instalada (normal o Business).
  /// La UI la usa para decidir si el botón principal dice "Enviar por WhatsApp"
  /// o "Compartir".
  Future<bool> get whatsappDisponible;

  /// Comparte bytes arbitrarios como archivo (reportes, respaldos).
  Future<ResultadoCompartir> compartirBytes(
    Uint8List bytes, {
    required String nombreArchivo,
    required String mimeType,
    String? mensaje,
  });

  /// Comparte un archivo que ya está en disco.
  Future<ResultadoCompartir> compartirArchivoEnDisco(
    String ruta, {
    String? mensaje,
  });

  /// Comparte solo texto.
  Future<ResultadoCompartir> compartirTexto(String texto);

  /// Borra los comprobantes temporales generados por esta app. Conviene
  /// llamarlo al cerrar caja: un negocio con 200 ventas al día acumula
  /// cientos de PNG en el directorio temporal.
  Future<void> limpiarTemporales();
}