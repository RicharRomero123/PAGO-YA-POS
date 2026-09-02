// PagoYa Móvil — dominio/proveedor.dart
//
// PORT de `Proveedor.cs`. Distribuidor/mayorista al que reabastecer.

library;

import 'entidad_base.dart';
import 'tiempo.dart';
import 'uuid.dart';

final class Proveedor extends EntidadBase {
  String nombre;
  String? ruc;
  String? contacto;

  /// Teléfono / WhatsApp (el canal real de reposición en el Perú).
  String? telefono;
  String? direccion;
  String? notas;
  bool activo;

  Proveedor({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.nombre = '',
    this.ruc,
    this.contacto,
    this.telefono,
    this.direccion,
    this.notas,
    this.activo = true,
  });

  factory Proveedor.desdeFila(Map<String, Object?> f) => Proveedor(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        nombre: Leer.texto(f, 'nombre'),
        ruc: Leer.textoNulable(f, 'ruc'),
        contacto: Leer.textoNulable(f, 'contacto'),
        telefono: Leer.textoNulable(f, 'telefono'),
        direccion: Leer.textoNulable(f, 'direccion'),
        notas: Leer.textoNulable(f, 'notas'),
        activo: Leer.booleano(f, 'activo', true),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'nombre': nombre,
        'ruc': ruc,
        'contacto': contacto,
        'telefono': telefono,
        'direccion': direccion,
        'notas': notas,
        'activo': activo ? 1 : 0,
      };

  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Nombre': nombre,
        'Ruc': ruc,
        'Contacto': contacto,
        'Telefono': telefono,
        'Direccion': direccion,
        'Notas': notas,
        'Activo': activo,
      };

  factory Proveedor.desdeJson(Map<String, Object?> j) => Proveedor(
        id: Uuid.normalizar(j['Id'] as String?),
        nombre: (j['Nombre'] as String?) ?? '',
        ruc: j['Ruc'] as String?,
        contacto: j['Contacto'] as String?,
        telefono: j['Telefono'] as String?,
        direccion: j['Direccion'] as String?,
        notas: j['Notas'] as String?,
        activo: (j['Activo'] as bool?) ?? true,
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
