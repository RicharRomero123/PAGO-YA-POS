// PagoYa Móvil — datos/correlativos.dart
//
// Correlativos legibles con PREFIJO DE DISPOSITIVO.
//
// EL PROBLEMA
// -----------
// `ventas.numero` es el "correlativo legible por caja" que el cliente ve en su
// ticket. El escritorio lo genera como `"V-" + yyMMdd-HHmmss`
// (`CobroRapidoViewModel.GenerarNumero`), que ya es frágil (dos ventas en el
// mismo segundo chocan) y que, con el móvil como segunda caja, colisiona de
// verdad: la PC y el celular emitirían el mismo número para ventas distintas y
// el dueño vería dos "V-260902-143012" con importes diferentes.
//
// LA REGLA ACORDADA (docs/MOBILE-ARQUITECTURA.md §6): el número es
// `<prefijo-dispositivo>-<correlativo>`, ej. `M01-000123`.
//
// EL PREFIJO NO LO GENERA EL MÓVIL
// --------------------------------
// Lo asigna el SERVIDOR al vincular el dispositivo (`POST /devices`) y llega
// como `devicePrefix`: `C01`..`C99` para escritorio, `M01`..`M99` para móvil,
// único por licencia y no reutilizable tras revocar. Aquí solo se LEE de
// `ConfiguracionDispositivo` (fuente única) y se compone con el contador local.
// Derivarlo del id del dispositivo o inventarlo produciría choques entre dos
// celulares de la misma bodega, que es justo el bug que el prefijo evita.
//
// EL CONTADOR SÍ ES LOCAL
// -----------------------
// Vive en la tabla `meta` y se incrementa DENTRO de la misma transacción que la
// venta: si la venta hace rollback, el correlativo no se consume y no quedan
// huecos en la numeración que el contador tenga que explicar en una
// fiscalización.

library;

import 'configuracion_dispositivo.dart';
import 'ejecutor_sql.dart';
import 'esquema.dart';

/// Generador de correlativos legibles por dispositivo.
final class Correlativos {
  /// Cantidad de dígitos del contador (`M01-000123`).
  static const int digitos = 6;

  final EjecutorSql _db;
  final ConfiguracionDispositivo _config;

  Correlativos(this._db, [ConfiguracionDispositivo? config])
      : _config = config ?? ConfiguracionDispositivo(_db);

  /// Prefijo asignado por el servidor. Mientras la app no esté vinculada
  /// devuelve `ConfiguracionDispositivo.prefijoSinVincular` para poder operar
  /// offline sin dejar `ventas.numero` vacío.
  Future<String> prefijo() => _config.prefijoDispositivo();

  /// Consume el siguiente correlativo de venta. **Debe llamarse dentro de la
  /// transacción de la venta** — para eso recibe [tx].
  Future<String> siguienteVenta(EjecutorSql tx) =>
      _siguiente(tx, ClavesMeta.correlativoVenta);

  /// Consume el siguiente correlativo de comanda/pedido.
  Future<String> siguientePedido(EjecutorSql tx) =>
      _siguiente(tx, ClavesMeta.correlativoPedido);

  /// Formatea sin consumir (para previsualizar en la UI).
  Future<String> previsualizarVenta() async {
    final n = await _leerContador(_db, ClavesMeta.correlativoVenta);
    return formatear(await prefijo(), n + 1);
  }

  /// `M01` + 123 -> `M01-000123`.
  static String formatear(String prefijo, int numero) =>
      '$prefijo-${numero.toString().padLeft(digitos, '0')}';

  /// Extrae el prefijo de un correlativo ya formado (`M01-000123` -> `M01`).
  ///
  /// Devuelve cadena vacía si el formato no es el esperado: una venta vieja del
  /// escritorio (`V-260902-143012`) no lleva prefijo de dispositivo y hay que
  /// tolerarla, no reventar el reporte.
  static String prefijoDe(String numero) {
    final i = numero.indexOf('-');
    if (i <= 0) return '';
    final resto = numero.substring(i + 1);
    if (resto.isEmpty) return '';
    for (final u in resto.codeUnits) {
      if (u < 0x30 || u > 0x39) return ''; // no son puros dígitos
    }
    return numero.substring(0, i);
  }

  Future<String> _siguiente(EjecutorSql tx, String clave) async {
    // Upsert atómico del contador. El CAST evita depender de que la fila ya
    // exista y mantiene `meta.valor` como TEXT (el esquema no se cambia).
    await tx.ejecutar(
      '''
      INSERT INTO meta (clave, valor) VALUES (?, '1')
      ON CONFLICT(clave) DO UPDATE SET
        valor = CAST(CAST(meta.valor AS INTEGER) + 1 AS TEXT)
      ''',
      [clave],
    );
    final n = await _leerContador(tx, clave);
    return formatear(await prefijo(), n);
  }

  static Future<int> _leerContador(EjecutorSql db, String clave) async {
    final v = await db.escalar(
      'SELECT valor FROM meta WHERE clave = ?',
      [clave],
    );
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
