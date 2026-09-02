// PagoYa Móvil — dominio/producto.dart
//
// PORT de `src/PagoYa.Core/Entidades/Producto.cs`.
//
// NOTA SOBRE CANTIDADES vs DINERO
// -------------------------------
// Los importes usan `Dinero` (céntimos enteros). Las CANTIDADES (stock, kilos)
// usan `double` a propósito: el escritorio las guarda en columnas REAL y hace
// la aritmética dentro del SQL (`stock_actual = stock_actual - @cant`), o sea
// en punto flotante de SQLite. Modelarlas como decimal en el móvil crearía una
// divergencia donde hoy no la hay.

library;

import 'dinero.dart';
import 'entidad_base.dart';
import 'enums.dart';
import 'personalizacion.dart';
import 'tiempo.dart';
import 'uuid.dart';

/// Producto o artículo del catálogo.
///
/// `stockActual` es **caché desnormalizada** para lecturas rápidas del POS: la
/// fuente de verdad es la tabla `inventario` (kardex append-only). Ver
/// `datos/outbox_store.dart` para por qué esa distinción es crítica al
/// sincronizar dos cajas que venden a la vez.
final class Producto extends EntidadBase {
  /// Código de barras o SKU interno. Único (índice `ix_productos_codigo`).
  String codigo;
  String nombre;
  String? descripcion;

  /// Precio de venta unitario. En Perú lo habitual es que ya incluya IGV.
  Dinero precioVenta;
  Dinero? costoCompra;
  bool precioIncluyeIgv;

  /// Unidad de medida (Catálogo 03 SUNAT: "NIU" unidad, "KGM" kilo…).
  String unidadMedida;

  /// Caché de stock. La verdad está en el kardex `inventario`.
  double stockActual;
  bool controlaStock;
  bool activo;

  /// Umbral de reposición. 0 = sin aviso.
  double stockMinimo;

  // --- Campos farmacéuticos (rubro farmacia/botica; null en otros rubros) ---
  DateTime? fechaVencimiento;
  String? lote;
  String? registroSanitario;

  /// Principio activo / DCI: permite buscar genéricos (obligación en Perú).
  String? principioActivo;
  bool requiereReceta;

  String? imagenRuta;
  String? proveedorId;

  /// Modificadores serializados (rubro comida). Ver [personalizacion].
  String? personalizacionJson;

  TipoDescuento tipoDescuento;

  /// Valor del descuento según [tipoDescuento]: porcentaje 0–100 (con hasta 2
  /// decimales) si es `porcentaje`, o precio de oferta en soles si es `oferta`.
  ///
  /// Se guarda como `Dinero` aunque a veces sea un porcentaje: ambas lecturas
  /// son punto fijo de 2 decimales, y así el cálculo del precio final puede
  /// hacerse con enteros y replicar el redondeo bancario de `decimal.Round`.
  Dinero descuentoValor;

  Producto({
    super.id,
    super.creadoUtc,
    super.actualizadoUtc,
    super.origenCajaId,
    this.codigo = '',
    this.nombre = '',
    this.descripcion,
    Dinero? precioVenta,
    this.costoCompra,
    this.precioIncluyeIgv = true,
    this.unidadMedida = 'NIU',
    this.stockActual = 0,
    this.controlaStock = true,
    this.activo = true,
    this.stockMinimo = 0,
    this.fechaVencimiento,
    this.lote,
    this.registroSanitario,
    this.principioActivo,
    this.requiereReceta = false,
    this.imagenRuta,
    this.proveedorId,
    this.personalizacionJson,
    this.tipoDescuento = TipoDescuento.ninguno,
    Dinero? descuentoValor,
  })  : precioVenta = precioVenta ?? Dinero.cero,
        descuentoValor = descuentoValor ?? Dinero.cero;

  // ---------------------------------------------------------------- Derivados

  /// Días que faltan para vencer (negativo si ya venció); null si no aplica.
  /// Espeja `Producto.DiasParaVencer` (compara solo la parte de fecha).
  int? diasParaVencer([DateTime? hoy]) {
    final f = fechaVencimiento;
    if (f == null) return null;
    final h = hoy ?? DateTime.now();
    final a = DateTime(f.year, f.month, f.day);
    final b = DateTime(h.year, h.month, h.day);
    return a.difference(b).inDays;
  }

  /// True si el producto ya venció (no debe venderse).
  bool estaVencido([DateTime? hoy]) {
    final d = diasParaVencer(hoy);
    return d != null && d < 0;
  }

  /// True si vence dentro de los próximos [dias] días (pero aún no vence).
  bool porVencer({int dias = 30, DateTime? hoy}) {
    final d = diasParaVencer(hoy);
    return d != null && d >= 0 && d <= dias;
  }

  /// True si el umbral está definido y el stock cayó a ese nivel o menos.
  bool get stockBajo =>
      controlaStock && stockMinimo > 0 && stockActual <= stockMinimo;

  /// Precio efectivo tras aplicar el descuento. Nunca supera [precioVenta].
  ///
  /// PARIDAD: espeja `Producto.PrecioFinal`, incluido el redondeo bancario de
  /// `decimal.Round(..., 2)`. El cálculo se hace con enteros
  /// ([Dinero.porcentaje]) precisamente para que 3.55 con 50 % dé 1.78 (medio
  /// hacia el par) y no 1.77, que es lo que daría un `double`.
  Dinero get precioFinal {
    switch (tipoDescuento) {
      case TipoDescuento.porcentaje:
        // DescuentoValor está en "centésimas de punto porcentual" gracias a la
        // representación de Dinero: 15.00 % -> 1500.
        var pct = descuentoValor.centimos;
        if (pct < 0) pct = 0;
        if (pct > 10000) pct = 10000;
        return precioVenta.porcentaje(10000 - pct);
      case TipoDescuento.oferta:
        return descuentoValor.esPositivo && descuentoValor < precioVenta
            ? descuentoValor
            : precioVenta;
      case TipoDescuento.ninguno:
        return precioVenta;
    }
  }

  /// True si hay oferta vigente.
  bool get tieneDescuento => precioFinal < precioVenta;

  /// Porcentaje efectivo redondeado para el badge "-15 %"; 0 si no aplica.
  /// Espeja `(int)decimal.Round((1 - PrecioFinal / PrecioVenta) * 100m, 0)`.
  int get porcentajeDescuento {
    if (!precioVenta.esPositivo || !tieneDescuento) return 0;
    final delta = precioVenta.centimos - precioFinal.centimos;
    return divRedondeadoMitadPar(delta * 100, precioVenta.centimos);
  }

  /// Modificadores del producto (nunca null; vacío si es un producto simple).
  PersonalizacionProducto get personalizacion =>
      PersonalizacionSerializer.deserializar(personalizacionJson);

  /// True si al venderlo hay que abrir el diálogo de personalización.
  bool get tienePersonalizacion =>
      personalizacionJson != null &&
      personalizacionJson!.trim().isNotEmpty &&
      personalizacion.tieneContenido;

  // ------------------------------------------------------------------ Mapeo DB

  /// Construye desde una fila de la tabla `productos`.
  factory Producto.desdeFila(Map<String, Object?> f) => Producto(
        id: Uuid.normalizar(Leer.texto(f, 'id')),
        codigo: Leer.texto(f, 'codigo'),
        nombre: Leer.texto(f, 'nombre'),
        descripcion: Leer.textoNulable(f, 'descripcion'),
        precioVenta: Dinero.desdeDb(Leer.numero(f, 'precio_venta')),
        costoCompra: Dinero.desdeDbNulable(Leer.numero(f, 'costo_compra')),
        precioIncluyeIgv: Leer.booleano(f, 'precio_incluye_igv', true),
        unidadMedida: Leer.texto(f, 'unidad_medida', 'NIU'),
        stockActual: (Leer.numero(f, 'stock_actual') ?? 0).toDouble(),
        controlaStock: Leer.booleano(f, 'controla_stock', true),
        activo: Leer.booleano(f, 'activo', true),
        stockMinimo: (Leer.numero(f, 'stock_minimo') ?? 0).toDouble(),
        fechaVencimiento: Leer.fechaNulable(f, 'fecha_vencimiento'),
        lote: Leer.textoNulable(f, 'lote'),
        registroSanitario: Leer.textoNulable(f, 'registro_sanitario'),
        principioActivo: Leer.textoNulable(f, 'principio_activo'),
        requiereReceta: Leer.booleano(f, 'requiere_receta'),
        imagenRuta: Leer.textoNulable(f, 'imagen_ruta'),
        proveedorId: Leer.textoNulable(f, 'proveedor_id'),
        personalizacionJson: Leer.textoNulable(f, 'personalizacion_json'),
        tipoDescuento: TipoDescuento.desde(Leer.entero(f, 'tipo_descuento')),
        descuentoValor: Dinero.desdeDb(Leer.numero(f, 'descuento_valor')),
        origenCajaId: Leer.texto(f, 'origen_caja_id'),
        creadoUtc: Leer.fecha(f, 'created_utc'),
        actualizadoUtc: Leer.fecha(f, 'updated_utc'),
      );

  /// Parámetros nombrados para el UPSERT de `productos`.
  Map<String, Object?> aFila() => {
        ...baseAFila(),
        'codigo': codigo,
        'nombre': nombre,
        'descripcion': descripcion,
        'precio_venta': precioVenta.aDb(),
        'costo_compra': costoCompra?.aDb(),
        'precio_incluye_igv': precioIncluyeIgv ? 1 : 0,
        'unidad_medida': unidadMedida,
        'stock_actual': stockActual,
        'controla_stock': controlaStock ? 1 : 0,
        'activo': activo ? 1 : 0,
        'imagen_ruta': imagenRuta,
        'proveedor_id': proveedorId,
        'tipo_descuento': tipoDescuento.valor,
        'descuento_valor': descuentoValor.aDb(),
        'stock_minimo': stockMinimo,
        'fecha_vencimiento':
            fechaVencimiento == null ? null : TiempoUtc.formatoFecha(fechaVencimiento!),
        'lote': lote,
        'registro_sanitario': registroSanitario,
        'principio_activo': principioActivo,
        'requiere_receta': requiereReceta ? 1 : 0,
        'personalizacion_json': personalizacionJson,
      };

  // ---------------------------------------------------------------- Mapeo JSON

  /// Snapshot para `outbox_sync.payload_json`, en PascalCase (ver
  /// `EntidadBase.baseAJson` para por qué NO es camelCase).
  ///
  /// Se omiten las propiedades calculadas de C# (`PrecioFinal`, `EstaVencido`,
  /// `DiasParaVencer`…). El escritorio las serializa por tener getter público,
  /// pero al deserializar las ignora (no tienen setter), y `DiasParaVencer`
  /// depende de `DateTime.Today`, o sea que haría el payload no determinista.
  Map<String, Object?> aJson() => {
        ...baseAJson(),
        'Codigo': codigo,
        'Nombre': nombre,
        'Descripcion': descripcion,
        'PrecioVenta': precioVenta.aDb(),
        'CostoCompra': costoCompra?.aDb(),
        'PrecioIncluyeIgv': precioIncluyeIgv,
        'UnidadMedida': unidadMedida,
        'StockActual': stockActual,
        'ControlaStock': controlaStock,
        'Activo': activo,
        'StockMinimo': stockMinimo,
        'FechaVencimiento': fechaVencimiento == null
            ? null
            // C# la guarda como DateTime con Kind=Unspecified (viene de
            // 'yyyy-MM-dd'), así que se emite sin zona horaria.
            : '${TiempoUtc.formatoFecha(fechaVencimiento!)}T00:00:00',
        'Lote': lote,
        'RegistroSanitario': registroSanitario,
        'PrincipioActivo': principioActivo,
        'RequiereReceta': requiereReceta,
        'ImagenRuta': imagenRuta,
        'ProveedorId': proveedorId,
        'PersonalizacionJson': personalizacionJson,
        'TipoDescuento': tipoDescuento.valor,
        'DescuentoValor': descuentoValor.aDb(),
      };

  /// Reconstruye desde el payload de un cambio remoto.
  factory Producto.desdeJson(Map<String, Object?> j) => Producto(
        id: Uuid.normalizar(j['Id'] as String?),
        codigo: (j['Codigo'] as String?) ?? '',
        nombre: (j['Nombre'] as String?) ?? '',
        descripcion: j['Descripcion'] as String?,
        precioVenta: Dinero.desdeDb(j['PrecioVenta'] as num?),
        costoCompra: Dinero.desdeDbNulable(j['CostoCompra'] as num?),
        precioIncluyeIgv: (j['PrecioIncluyeIgv'] as bool?) ?? true,
        unidadMedida: (j['UnidadMedida'] as String?) ?? 'NIU',
        stockActual: (j['StockActual'] as num?)?.toDouble() ?? 0,
        controlaStock: (j['ControlaStock'] as bool?) ?? true,
        activo: (j['Activo'] as bool?) ?? true,
        stockMinimo: (j['StockMinimo'] as num?)?.toDouble() ?? 0,
        fechaVencimiento: TiempoUtc.parsear(j['FechaVencimiento'] as String?),
        lote: j['Lote'] as String?,
        registroSanitario: j['RegistroSanitario'] as String?,
        principioActivo: j['PrincipioActivo'] as String?,
        requiereReceta: (j['RequiereReceta'] as bool?) ?? false,
        imagenRuta: j['ImagenRuta'] as String?,
        proveedorId: j['ProveedorId'] as String?,
        personalizacionJson: j['PersonalizacionJson'] as String?,
        tipoDescuento: TipoDescuento.desde((j['TipoDescuento'] as num?)?.toInt()),
        descuentoValor: Dinero.desdeDb(j['DescuentoValor'] as num?),
        origenCajaId: (j['OrigenCajaId'] as String?) ?? '',
        creadoUtc: TiempoUtc.parsearUtc(j['CreadoUtc'] as String?),
        actualizadoUtc: TiempoUtc.parsearUtc(j['ActualizadoUtc'] as String?),
      );
}
