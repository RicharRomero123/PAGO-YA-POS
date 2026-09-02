/// Catálogo de productos: carga, búsqueda instantánea y filtro por categoría.
///
/// Dueño: `flutter-ui`. Lo consumen la grilla de cobro, el inventario y la
/// comanda de mesas — las tres pintan lo mismo, así que filtran con el mismo
/// estado en vez de tener cada una su copia.
///
/// ## Dónde vive la categoría de un producto
///
/// **En la columna `descripcion`.** No hay columna `categoria` en el esquema:
/// el escritorio reutiliza `descripcion` para eso (`SeedDemo`: "categoría
/// reutiliza 'descripcion'"; `ProductoItemViewModel.Desde`:
/// `Categoria = p.Descripcion ?? "General"`), y `SembradorCatalogo` del móvil
/// hace exactamente lo mismo. Inventarse un campo aquí rompería la paridad.
///
/// Por eso [CategoriaDeProducto] existe: un solo lugar donde se aplica la regla
/// "sin descripción ⇒ General".
///
/// ## Por qué no se usa `observarCatalogo()`
///
/// El `Stream` está marcado `PENDIENTE (flutter-datos)` en `datos/contratos.dart`.
/// Escuchar un stream sin implementar dejaría la grilla en blanco para siempre;
/// una recarga explícita tras cada escritura es menos elegante y funciona hoy.
/// Cuando el stream exista, se cambia [CatalogoNotifier.build] y nadie más se
/// entera.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pagoya_core/pagoya_core.dart';

import '../composicion.dart';

/// Categoría de un producto, con la regla del escritorio aplicada.
extension CategoriaDeProducto on Producto {
  /// Categoría visible. `General` cuando el producto no trae ninguna.
  String get categoria {
    final texto = descripcion?.trim() ?? '';
    return texto.isEmpty ? 'General' : texto;
  }

  /// `true` si el producto no se puede vender por falta de stock.
  ///
  /// Un producto **sin control de stock** (un plato preparado, un servicio)
  /// nunca está agotado: `controlaStock == false` es lo que distingue "no me
  /// queda ninguno" de "esto no se cuenta por unidades".
  bool get agotado => controlaStock && stockActual <= 0;

  /// Stock formateado para la tarjeta (`12 und`, `2.5 KGM`).
  String get stockFormateado {
    final entero = stockActual == stockActual.roundToDouble();
    final cantidad =
        entero ? stockActual.toStringAsFixed(0) : stockActual.toStringAsFixed(3);
    final unidad = unidadMedida == 'NIU' ? 'und' : unidadMedida;
    return '$cantidad $unidad';
  }
}

/// Filtro activo de la grilla de productos.
@immutable
final class FiltroCatalogo {
  /// Crea un filtro.
  const FiltroCatalogo({this.texto = '', this.categoria});

  /// Texto tecleado o código escaneado.
  final String texto;

  /// Categoría elegida; `null` = todas.
  final String? categoria;

  /// Copia con cambios. [categoria] se limpia pasando [limpiarCategoria].
  FiltroCatalogo copiarCon({
    String? texto,
    String? categoria,
    bool limpiarCategoria = false,
  }) =>
      FiltroCatalogo(
        texto: texto ?? this.texto,
        categoria: limpiarCategoria ? null : (categoria ?? this.categoria),
      );
}

/// Filtro vivo de la grilla.
final NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo>
    filtroCatalogoProvider =
    NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo>(
        FiltroCatalogoNotifier.new);

/// Guarda el texto de búsqueda y la categoría elegida.
final class FiltroCatalogoNotifier extends Notifier<FiltroCatalogo> {
  @override
  FiltroCatalogo build() => const FiltroCatalogo();

  /// Búsqueda instantánea: se aplica en cada pulsación, sin botón.
  void buscar(String texto) => state = state.copiarCon(texto: texto);

  /// Elige una categoría, o la quita si ya estaba elegida (toque = alternar).
  void alternarCategoria(String categoria) {
    state = state.categoria == categoria
        ? state.copiarCon(limpiarCategoria: true)
        : state.copiarCon(categoria: categoria);
  }

  /// Vuelve a "todas las categorías, sin texto".
  void limpiar() => state = const FiltroCatalogo();
}

/// Catálogo completo de productos activos.
final AsyncNotifierProvider<CatalogoNotifier, List<Producto>> catalogoProvider =
    AsyncNotifierProvider<CatalogoNotifier, List<Producto>>(
        CatalogoNotifier.new);

/// Carga y mantiene el catálogo. Toda escritura recarga: la grilla del POS y la
/// lista de inventario tienen que quedar iguales tras editar un precio.
final class CatalogoNotifier extends AsyncNotifier<List<Producto>> {
  @override
  Future<List<Producto>> build() =>
      ref.watch(repositorioProductosProvider).buscar();

  /// Relee el catálogo desde SQLite.
  Future<void> recargar() async {
    state = await AsyncValue.guard(
      () => ref.read(repositorioProductosProvider).buscar(),
    );
  }

  /// Alta o edición de un producto (upsert + outbox, del lado del repositorio).
  Future<void> guardar(Producto producto) async {
    await ref.read(repositorioProductosProvider).guardar(producto);
    await recargar();
  }

  /// Borrado lógico. No borra: rompería el historial de ventas.
  Future<void> desactivar(String id) async {
    await ref.read(repositorioProductosProvider).desactivar(id);
    await recargar();
  }

  /// Busca por código de barras. Es la ruta caliente del escáner: consulta el
  /// índice `ix_productos_codigo` en vez de recorrer la lista en memoria.
  Future<Producto?> porCodigo(String codigo) =>
      ref.read(repositorioProductosProvider).obtenerPorCodigo(codigo.trim());
}

/// Categorías presentes en el catálogo, en orden alfabético.
///
/// Se calculan **en memoria** sobre el catálogo ya cargado en vez de llamar a
/// `RepositorioProductos.listarCategorias()`, que sigue `PENDIENTE`. Un catálogo
/// de bodega son cientos de filas, no millones: el propio `datos/contratos.dart`
/// razona igual para el filtro por categoría.
final Provider<List<String>> categoriasProvider =
    Provider<List<String>>((Ref ref) {
  final productos = ref.watch(catalogoProvider).valueOrNull;
  if (productos == null) return const <String>[];
  final vistas = <String>{for (final p in productos) p.categoria};
  final lista = vistas.toList()..sort();
  return List<String>.unmodifiable(lista);
});

/// Productos que se ven ahora mismo en la grilla, ya filtrados.
///
/// El filtro por texto imita al escritorio: coincide por **nombre o por
/// código**, sin distinguir mayúsculas. Que el código entre en la búsqueda es lo
/// que permite teclear un código de barras a mano cuando la cámara no engancha.
final Provider<List<Producto>> productosVisiblesProvider =
    Provider<List<Producto>>((Ref ref) {
  final productos = ref.watch(catalogoProvider).valueOrNull;
  if (productos == null) return const <Producto>[];

  final filtro = ref.watch(filtroCatalogoProvider);
  final texto = filtro.texto.trim().toLowerCase();
  final categoria = filtro.categoria;

  final resultado = <Producto>[];
  for (final p in productos) {
    if (!p.activo) continue;
    if (categoria != null && p.categoria != categoria) continue;
    if (texto.isNotEmpty &&
        !p.nombre.toLowerCase().contains(texto) &&
        !p.codigo.toLowerCase().contains(texto)) {
      continue;
    }
    resultado.add(p);
  }
  return List<Producto>.unmodifiable(resultado);
});
