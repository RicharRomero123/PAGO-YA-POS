// PagoYa Móvil — dominio/comprobante.dart
//
// PORT de `Comprobante.cs`.
//
// Los campos de facturación electrónica (hash, CDR, estado SUNAT) solo se
// llenan cuando el flag firmado "invoicing" está activo. En el MÓVIL además
// se llenan siempre desde el backend/PSE: el .pfx no vive en el teléfono
// (docs/MOBILE-ARQUITECTURA.md §5.6), así que aquí solo se guarda el
// resultado que devuelve el servidor.

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'tiempo.dart';
import 'uuid.dart';

final class Comprobante extends EntidadBase {
  String ventaId;
  TipoComprobante tipo;

  /// Serie (ej. "B001", "F001", "NV01").
  String serie;

  /// Correlativo dentro de la serie.
  int correlativo;

  String? documentoCliente;
  String? nombreCliente;
  Dinero total;

  // --- Facturación electrónica SUNAT (solo con flag "invoicing") ---
  String? hashXml;
  String? estadoSunat;
  String? codigoCdr;
  String? rutaXml;
  String? rutaPdf;

  Comprobante({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.ventaId = Uuid.vacio,
    this.tipo = TipoComprobante.notaVenta,
    this.serie = '',
    this.correlativo = 0,
    this.documentoCliente,
    this.nombreCliente,
    Dinero? total,
    this.hashXml,
    this.estadoSunat,
    this.codigoCdr,
    this.rutaXml,
    this.rutaPdf,
  }) : total = total ?? Dinero.cero;

  factory Comprobante.desdeFila(Map<String, Object?> f) => Comprobante(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        ventaId: Uuid.normalizar(Leer.texto(f, 'venta_id')),
        tipo: TipoComprobante.desde(Leer.entero(f, 'tipo')),
        serie: Leer.texto(f, 'serie'),
        correlativo: Leer.entero(f, 'correlativo'),
        documentoCliente: Leer.textoNulable(f, 'documento_cliente'),
        nombreCliente: Leer.textoNulable(f, 'nombre_cliente'),
        total: Dinero.desdeDb(Leer.numero(f, 'total')),
        hashXml: Leer.textoNulable(f, 'hash_xml'),
        estadoSunat: Leer.textoNulable(f, 'estado_sunat'),
        codigoCdr: Leer.textoNulable(f, 'codigo_cdr'),
        rutaXml: Leer.textoNulable(f, 'ruta_xml'),
        rutaPdf: Leer.textoNulable(f, 'ruta_pdf'),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'venta_id': ventaId,
        'tipo': tipo.valor,
        'serie': serie,
        'correlativo': correlativo,
        'documento_cliente': documentoCliente,
        'nombre_cliente': nombreCliente,
        'total': total.aDb(),
        'hash_xml': hashXml,
        'estado_sunat': estadoSunat,
        'codigo_cdr': codigoCdr,
        'ruta_xml': rutaXml,
        'ruta_pdf': rutaPdf,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'VentaId': ventaId,
        'Tipo': tipo.valor,
        'Serie': serie,
        'Correlativo': correlativo,
        'DocumentoCliente': documentoCliente,
        'NombreCliente': nombreCliente,
        'Total': total.aDb(),
        'HashXml': hashXml,
        'EstadoSunat': estadoSunat,
        'CodigoCdr': codigoCdr,
        'RutaXml': rutaXml,
        'RutaPdf': rutaPdf,
      };

  factory Comprobante.desdeJson(Map<String, Object?> j) => Comprobante(
        id: Uuid.normalizar(j['Id'] as String?),
        ventaId: Uuid.normalizar(j['VentaId'] as String?),
        tipo: TipoComprobante.desde((j['Tipo'] as num?)?.toInt()),
        serie: (j['Serie'] as String?) ?? '',
        correlativo: (j['Correlativo'] as num?)?.toInt() ?? 0,
        documentoCliente: j['DocumentoCliente'] as String?,
        nombreCliente: j['NombreCliente'] as String?,
        total: Dinero.desdeDb(j['Total'] as num?),
        hashXml: j['HashXml'] as String?,
        estadoSunat: j['EstadoSunat'] as String?,
        codigoCdr: j['CodigoCdr'] as String?,
        rutaXml: j['RutaXml'] as String?,
        rutaPdf: j['RutaPdf'] as String?,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
