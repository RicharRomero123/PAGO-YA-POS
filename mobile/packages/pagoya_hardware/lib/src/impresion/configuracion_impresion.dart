/// Ancho del rollo de papel térmico.
///
/// **No hardcodear el ancho.** En Perú conviven los dos: el bodeguero compra
/// la impresora más barata (58 mm) y el restaurante suele tener 80 mm. El
/// usuario lo elige en Configuración y se guarda con el resto de ajustes.
enum AnchoPapel {
  /// 58 mm ≈ 32 columnas en fuente A.
  mm58(58, 32, 'Papel de 58 mm (el más común)'),

  /// 80 mm ≈ 42 columnas. Es el valor por defecto del escritorio
  /// (`TicketPrinterEscPos.AnchoColumnasDefault`).
  mm80(80, 42, 'Papel de 80 mm (impresora grande)');

  const AnchoPapel(this.milimetros, this.columnasPorDefecto, this.etiqueta);

  final int milimetros;

  /// Columnas de texto en fuente A. Coincide con los valores documentados en
  /// `DatosNegocio.ColumnasTicket` del escritorio (58 mm≈32, 80 mm≈42).
  final int columnasPorDefecto;

  /// Texto para el selector de la pantalla de configuración.
  final String etiqueta;
}

/// Ajustes de impresión. Todo lo que el usuario puede cambiar sin recompilar.
class ConfiguracionImpresion {
  const ConfiguracionImpresion({
    this.ancho = AnchoPapel.mm58,
    this.columnas,
    this.abrirCajonEnEfectivo = false,
    this.cortarPapel = true,
    this.lineasFinales = 3,
    this.copias = 1,
    this.transliterarAcentos = false,
    this.imprimirPieSunat = true,
  });

  final AnchoPapel ancho;

  /// Override manual de columnas. Algunas térmicas chinas de 58 mm imprimen 31
  /// o 33 columnas; esto evita tener que parchear código por un clon raro.
  final int? columnas;

  /// Pulso al cajón portamonedas al cobrar en efectivo
  /// (`DatosNegocio.AbrirCajonEnEfectivo`). **Por defecto `false` en móvil**:
  /// una impresora Bluetooth portátil casi nunca tiene cajón conectado, al
  /// revés que en el mostrador de la PC.
  final bool abrirCajonEnEfectivo;

  /// Corte parcial al final (GS V). Las impresoras portátiles de 58 mm sin
  /// cortadora ignoran el comando; no molesta.
  final bool cortarPapel;

  /// Avance de papel antes del corte. El escritorio manda 3.
  final int lineasFinales;

  /// Copias del mismo ticket (bodegas que dan una al cliente y guardan otra).
  final int copias;

  /// Si la impresora no soporta la página de códigos CP850, se quitan las
  /// tildes en vez de imprimir basura (`á` → `a`). Se activa manualmente
  /// cuando el usuario reporta "salen símbolos raros".
  final bool transliterarAcentos;

  /// Pie legal "Documento interno - no es comprobante de pago autorizado por
  /// SUNAT". Se apaga cuando la venta sí generó una boleta/factura electrónica
  /// (tier Facturador Pro), donde el texto sería falso.
  final bool imprimirPieSunat;

  /// Columnas efectivas.
  int get columnasEfectivas {
    final c = columnas;
    if (c != null && c > 0) return c;
    return ancho.columnasPorDefecto;
  }

  ConfiguracionImpresion copyWith({
    AnchoPapel? ancho,
    int? columnas,
    bool? abrirCajonEnEfectivo,
    bool? cortarPapel,
    int? lineasFinales,
    int? copias,
    bool? transliterarAcentos,
    bool? imprimirPieSunat,
  }) {
    return ConfiguracionImpresion(
      ancho: ancho ?? this.ancho,
      columnas: columnas ?? this.columnas,
      abrirCajonEnEfectivo: abrirCajonEnEfectivo ?? this.abrirCajonEnEfectivo,
      cortarPapel: cortarPapel ?? this.cortarPapel,
      lineasFinales: lineasFinales ?? this.lineasFinales,
      copias: copias ?? this.copias,
      transliterarAcentos: transliterarAcentos ?? this.transliterarAcentos,
      imprimirPieSunat: imprimirPieSunat ?? this.imprimirPieSunat,
    );
  }

  Map<String, Object?> aJson() => {
        'ancho': ancho.name,
        'columnas': columnas,
        'abrirCajonEnEfectivo': abrirCajonEnEfectivo,
        'cortarPapel': cortarPapel,
        'lineasFinales': lineasFinales,
        'copias': copias,
        'transliterarAcentos': transliterarAcentos,
        'imprimirPieSunat': imprimirPieSunat,
      };

  static ConfiguracionImpresion desdeJson(Map<String, Object?> json) {
    return ConfiguracionImpresion(
      ancho: AnchoPapel.values.firstWhere(
        (a) => a.name == json['ancho'],
        orElse: () => AnchoPapel.mm58,
      ),
      columnas: json['columnas'] as int?,
      abrirCajonEnEfectivo: json['abrirCajonEnEfectivo'] as bool? ?? false,
      cortarPapel: json['cortarPapel'] as bool? ?? true,
      lineasFinales: json['lineasFinales'] as int? ?? 3,
      copias: json['copias'] as int? ?? 1,
      transliterarAcentos: json['transliterarAcentos'] as bool? ?? false,
      imprimirPieSunat: json['imprimirPieSunat'] as bool? ?? true,
    );
  }
}