import 'package:flutter/material.dart';

import 'tokens_pagoya.dart';

/// Rutas centralizadas a la iconografía de PagoYa Móvil — port de
/// `src/PagoYa.Desktop/Servicios/IconosPos.cs` con **el mismo criterio**:
/// un solo lugar para el mapeo icono→archivo, así que cambiar un icono mañana
/// es tocar una línea y toda la app queda alineada.
///
/// ## De dónde salen los PNG
///
/// - **Fuente primaria:** `iconos-app-mobil/` en la raíz del repo (46 PNG de
///   icons8 elegidos para móvil). Se copian a `assets/iconos/` renombrados a
///   nombres semánticos ASCII `ico-<funcion>.png` — los originales tienen
///   tildes, eñes, espacios y paréntesis, que rompen Gradle y el bundle de
///   assets.
/// - **Huecos** que ese set no cubre (candado, impresora, nube, sincronización,
///   inventario, proveedores, facturación): salen de `Iconos-POS/` o de
///   `src/PagoYa.Desktop/Assets/Iconos/`, que pasa a ser solo respaldo.
///
/// La tabla origen→destino completa está en el reporte de `mobile-ux`. **No se
/// usan Material Icons para estos conceptos**: la identidad visual del producto
/// es este set de PNG.
abstract final class IconosPos {
  static const String _base = 'assets/iconos/';

  // -------------------------------------------------------------------------
  // Navegación
  // -------------------------------------------------------------------------

  /// `página-principal` — inicio del POS.
  static const String inicio = '${_base}ico-inicio.png';

  /// `atrás`.
  static const String atras = '${_base}ico-atras.png';

  /// `forward`.
  static const String adelante = '${_base}ico-adelante.png';

  // -------------------------------------------------------------------------
  // Módulos (equivalentes al sidebar del escritorio)
  // -------------------------------------------------------------------------

  /// `calculator` — el teclado de cobro. Acción estrella de la app.
  static const String cobrar = '${_base}ico-cobrar.png';

  /// `banknotes` (fajo de billetes) — caja: apertura, cierre y arqueo.
  static const String caja = '${_base}ico-caja.png';

  /// Respaldo del escritorio (`ico-inventario.png`): el set móvil no lo trae.
  static const String inventario = '${_base}ico-inventario.png';

  /// Respaldo del escritorio (`ico-proveedores.png`).
  static const String proveedores = '${_base}ico-proveedores.png';

  /// `carta-de-área` — reportes de ventas.
  static const String reportes = '${_base}ico-reportes.png';

  /// Respaldo del escritorio (`ico-facturacion.png`).
  static const String facturacion = '${_base}ico-facturacion.png';

  /// Respaldo del escritorio (`ico-nube.png`) — estado de sincronización.
  static const String nube = '${_base}ico-nube.png';

  /// `company` — multisede.
  static const String multisede = '${_base}ico-multisede.png';

  /// `grupo-de-usuarios-hombre-hombre` — usuarios y turnos.
  static const String usuarios = '${_base}ico-usuarios.png';

  /// `ajustes` — configuración.
  static const String configuracion = '${_base}ico-configuracion.png';

  /// `cubiertos` — mesas y comandas (rubros de comida).
  static const String mesas = '${_base}ico-restaurante.png';

  /// `cama` — habitaciones (rubro hotel).
  static const String habitaciones = '${_base}ico-cama.png';

  /// `apoyo` — soporte / ayuda por WhatsApp.
  static const String soporte = '${_base}ico-soporte.png';

  // -------------------------------------------------------------------------
  // Cobro y dinero
  // -------------------------------------------------------------------------

  /// `dinero` (un billete) — pago en efectivo y vuelto.
  static const String efectivo = '${_base}ico-efectivo.png';

  /// `tarjeta-de-fidelidad` — pago con tarjeta / cliente frecuente.
  static const String tarjeta = '${_base}ico-tarjeta.png';

  /// Respaldo de `Iconos-POS/icons8-print-96` — impresión del ticket ESC/POS.
  static const String imprimir = '${_base}ico-imprimir.png';

  /// `share` — enviar el comprobante por WhatsApp.
  static const String compartir = '${_base}ico-compartir.png';

  // -------------------------------------------------------------------------
  // Escáner: el diferenciador del móvil frente a la PC
  // -------------------------------------------------------------------------

  /// `slr-camera` — abrir la cámara como lector.
  static const String escaner = '${_base}ico-escaner.png';

  /// `código-de-barras` — código de barras del producto.
  static const String codigoBarras = '${_base}ico-codigo-barras.png';

  /// `código-qr`.
  static const String codigoQr = '${_base}ico-codigo-qr.png';

  // -------------------------------------------------------------------------
  // Catálogo y edición
  // -------------------------------------------------------------------------

  /// `search`.
  static const String buscar = '${_base}ico-buscar.png';

  /// `slider` — filtros y orden.
  static const String filtros = '${_base}ico-filtros.png';

  /// `folder` — categoría de producto.
  static const String categoria = '${_base}ico-categoria.png';

  /// `imagen` — marcador de producto sin foto.
  static const String imagen = '${_base}ico-imagen.png';

  /// `añadir-imagen` — tomar/elegir foto del producto.
  static const String anadirImagen = '${_base}ico-anadir-imagen.png';

  /// `plus-math` — agregar / subir cantidad.
  static const String mas = '${_base}ico-mas.png';

  /// `subtract` — quitar / bajar cantidad.
  static const String menos = '${_base}ico-menos.png';

  /// `edit-pencil`.
  static const String editar = '${_base}ico-editar.png';

  /// `eliminar` (papelera) — borrar una línea del carrito o un producto.
  static const String eliminar = '${_base}ico-eliminar.png';

  /// `eliminar (1)` (aspa) — cerrar hoja/diálogo.
  static const String cerrar = '${_base}ico-cerrar.png';

  /// `eliminar-archivo` — anular un comprobante.
  static const String anular = '${_base}ico-anular.png';

  // -------------------------------------------------------------------------
  // Negocio y personas
  // -------------------------------------------------------------------------

  /// `tienda` — el negocio; también el rubro por defecto.
  static const String tienda = '${_base}ico-tienda.png';

  /// `pin` — sede / dirección.
  static const String sede = '${_base}ico-sede.png';

  /// `usuario` — cajero en turno.
  static const String usuario = '${_base}ico-usuario.png';

  /// `cuenta` — mi cuenta / licencia.
  static const String cuenta = '${_base}ico-cuenta.png';

  // -------------------------------------------------------------------------
  // Estado
  // -------------------------------------------------------------------------

  /// Respaldo del escritorio (`ico-candado.png`) — **función bloqueada por
  /// licencia**. Es el icono del upsell: nunca se oculta la función, se
  /// muestra con candado.
  static const String candado = '${_base}ico-candado.png';

  /// `done` — operación completada (venta cobrada).
  static const String listo = '${_base}ico-listo.png';

  /// `check-mark` — marca de verificación en listas.
  static const String check = '${_base}ico-check.png';

  /// `error`.
  static const String error = '${_base}ico-error.png';

  /// `spinner-para-iphone` — cargando.
  static const String cargando = '${_base}ico-cargando.png';

  /// Respaldo de `Iconos-POS/icons8-synchronize-96` — sincronizando con la nube.
  static const String sincronizar = '${_base}ico-sincronizar.png';

  /// Respaldo de `Iconos-POS/icons8-error-cloud-96` — sincronización fallida.
  static const String nubeError = '${_base}ico-nube-error.png';

  /// `refresh` — recargar.
  static const String actualizar = '${_base}ico-actualizar.png';

  /// `globe` — con/sin internet.
  static const String internet = '${_base}ico-internet.png';

  /// `notification`.
  static const String notificacion = '${_base}ico-notificacion.png';

  /// `heart` — favorito / producto frecuente.
  static const String favorito = '${_base}ico-favorito.png';

  /// `en-alza` — tendencia al alza en reportes.
  static const String tendencia = '${_base}ico-tendencia.png';

  /// `toggle-on`.
  static const String toggleOn = '${_base}ico-toggle-on.png';

  /// `toggle-off`.
  static const String toggleOff = '${_base}ico-toggle-off.png';

  // -------------------------------------------------------------------------
  // Rubros (los que tienen icono propio; el resto cae a emoji en el onboarding)
  // -------------------------------------------------------------------------

  /// Bodega / minimarket → `tienda`.
  static const String rubroBodega = tienda;

  /// Restaurante, cafetería y pollería → `cubiertos`.
  static const String rubroRestaurante = '${_base}ico-restaurante.png';

  /// Farmacia / botica → `píldora`.
  static const String rubroFarmacia = '${_base}ico-farmacia.png';

  /// Ferretería → `mantenimiento`.
  static const String rubroFerreteria = '${_base}ico-ferreteria.png';

  /// Hotel / hospedaje → `cama`.
  static const String rubroHotel = '${_base}ico-cama.png';

  /// Icono del rubro para la identidad del negocio (encabezado, onboarding).
  ///
  /// **Mismo criterio que `IconosPos.DeRubro` en C#**: devuelve el PNG del
  /// rubro si existe; si no, cae al icono genérico de tienda para que la
  /// pantalla siempre muestre un icono coherente. `licoreria` y `otro` caen
  /// aquí a `tienda`; en la grilla de onboarding usan su emoji propio
  /// (ver `RubroUi`).
  static String deRubro(String? clave) {
    switch ((clave ?? '').toLowerCase()) {
      case 'restaurante':
      case 'cafeteria':
      case 'polleria':
        return rubroRestaurante;
      case 'farmacia':
        return rubroFarmacia;
      case 'ferreteria':
        return rubroFerreteria;
      case 'hotel':
        return rubroHotel;
      default:
        // bodega, licoreria, otro y desconocidos
        return rubroBodega;
    }
  }
}

/// Muestra un PNG de [IconosPos] con tamaño y filtrado consistentes.
///
/// Si el asset falta (por ejemplo, porque aún no se copiaron los PNG a
/// `assets/iconos/`), degrada a [respaldoEmoji] o a un hueco del mismo tamaño
/// en vez de romper la pantalla con la caja roja de error de Flutter.
class IconoPos extends StatelessWidget {
  const IconoPos(
    this.ruta, {
    super.key,
    this.tamano = Toques.iconoLista,
    this.color,
    this.respaldoEmoji,
    this.semantica,
  });

  /// Ruta del asset, siempre tomada de [IconosPos].
  final String ruta;

  /// Lado del icono en dp.
  final double tamano;

  /// Tinte opcional (los PNG de icons8 son monocromos y aceptan tinte).
  final Color? color;

  /// Emoji a mostrar si el PNG no se puede cargar.
  final String? respaldoEmoji;

  /// Etiqueta para lectores de pantalla.
  final String? semantica;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      ruta,
      width: tamano,
      height: tamano,
      color: color,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semantica,
      errorBuilder: (context, _, __) => SizedBox(
        width: tamano,
        height: tamano,
        child: respaldoEmoji == null
            ? const SizedBox.shrink()
            : Center(
                child: Text(
                  respaldoEmoji!,
                  style: TextStyle(fontSize: tamano * 0.82),
                ),
              ),
      ),
    );
  }
}
