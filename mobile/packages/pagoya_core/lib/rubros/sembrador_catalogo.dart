// PagoYa Móvil — rubros/sembrador_catalogo.dart
//
// Convierte una plantilla de rubro en productos reales de la BD.
//
// Es lo que hace usable el POS "de inmediato" tras elegir el rubro en el
// onboarding (docs/MOBILE-ARQUITECTURA.md §7).
//
// DECISIÓN: se usa `crearConStockInicial` y no `guardar`, para que cada
// producto sembrado quede con su fila de apertura en el kardex
// (`MotivosKardex.stockInicial`). Sin ella, `recalcularStockDesdeKardex`
// devolvería 0 para todo el catálogo sembrado — el escritorio tiene ese hueco
// hoy y el móvil no lo hereda.

library;

import '../datos/ejecutor_sql.dart';
import '../datos/repositorios/producto_repositorio.dart';
import '../dominio/personalizacion.dart';
import '../dominio/producto.dart';
import 'plantillas_rubro.dart';

/// Resultado de sembrar un rubro.
final class ResultadoSiembra {
  final int creados;
  final int omitidos;
  final List<String> codigosOmitidos;

  const ResultadoSiembra({
    required this.creados,
    required this.omitidos,
    required this.codigosOmitidos,
  });
}

/// Siembra el catálogo de ejemplo de un rubro.
final class SembradorCatalogo {
  final EjecutorSql _db;
  final ProductoRepositorio _productos;

  SembradorCatalogo(this._db, [ProductoRepositorio? productos])
      : _productos = productos ?? ProductoRepositorio(_db);

  /// Crea los productos de la plantilla de [claveRubro].
  ///
  /// Los códigos que ya existen se OMITEN en vez de sobrescribirse: si el
  /// usuario ya sincronizó su catálogo desde la PC, sembrar no debe pisarle
  /// los precios que él configuró. [hoy] se inyecta para que las fechas de
  /// vencimiento sembradas sean deterministas en los tests.
  Future<ResultadoSiembra> sembrar(
    String claveRubro, {
    DateTime? hoy,
    String origenCajaId = '',
  }) async {
    final plantilla = PlantillasRubro.productos(claveRubro);
    var creados = 0;
    final omitidos = <String>[];

    for (final p in plantilla) {
      final existe = await _db.escalar(
        'SELECT COUNT(*) FROM productos WHERE codigo = ?',
        [p.codigo],
      );
      if (((existe as num?)?.toInt() ?? 0) > 0) {
        omitidos.add(p.codigo);
        continue;
      }

      // Igual que `SeedDemo`: se serializa siempre; da null cuando el producto
      // no tiene modificadores (solo los tiene el rubro restaurante).
      final personalizacionJson =
          PersonalizacionSerializer.serializar(p.personalizacion);

      await _productos.crearConStockInicial(Producto(
        codigo: p.codigo,
        nombre: p.nombre,
        // La CATEGORÍA reutiliza la columna `descripcion`: el esquema no tiene
        // columna propia para ella y así lo hace el escritorio
        // (`SeedDemo`: "categoría reutiliza 'descripcion'";
        // `ProductoItemViewModel.Desde`: Categoria = p.Descripcion ?? "General").
        descripcion: p.categoria,
        precioVenta: p.precio,
        stockActual: p.stock,
        // Los platos preparados no llevan control de stock: no tiene sentido
        // "quedarse sin lomo saltado" en el inventario de una bodega.
        controlaStock: p.stock > 0,
        stockMinimo: p.stockMinimo,
        principioActivo: p.principioActivo,
        registroSanitario: p.registroSanitario,
        requiereReceta: p.requiereReceta,
        fechaVencimiento: p.fechaVencimiento(hoy),
        personalizacionJson: personalizacionJson,
        origenCajaId: origenCajaId,
      ));
      creados++;
    }

    return ResultadoSiembra(
      creados: creados,
      omitidos: omitidos.length,
      codigosOmitidos: omitidos,
    );
  }
}
