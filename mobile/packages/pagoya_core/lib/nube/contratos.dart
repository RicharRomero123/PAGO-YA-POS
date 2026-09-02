/// Contratos remotos que **no** cubre el módulo de sync: facturación
/// electrónica y registro de dispositivos (seats).
///
/// ## Arbitraje de `mobile-lead` (MOBILE-ARQUITECTURA §4.2)
///
/// `flutter-sync` publicó su propio juego de contratos de sincronización
/// (`ServicioSync`, `ResultadoSync`, `OpcionesSync`, `EventoSyncLocal`,
/// `CambioRemoto`, `TransporteSync`, `EstadoNube`) **con implementación,
/// planificador y tests**. Yo había escrito los mismos símbolos en paralelo.
/// **Gana lo implementado**: este archivo ya no los redefine, solo reexporta
/// `nube.dart`.
///
/// Lo que sí sigue viviendo aquí es lo que nadie más definió y el composition
/// root necesita: el motor de facturación y el servicio de seats.
///
/// Dueño de ESTE archivo: `mobile-lead`. Las implementaciones son de
/// `flutter-sync`.
library;

import 'package:meta/meta.dart';

import '../dominio/venta.dart';

export 'nube.dart';

// ---------------------------------------------------------------------------
// Seats / dispositivos
// ---------------------------------------------------------------------------

/// Registro de este teléfono como **dispositivo secundario** de la licencia.
///
/// Existe porque el flujo de `/activate` del escritorio NO sirve en móvil: si
/// el celular llama `/activate` con su id, desvincula la PC y quema uno de los
/// dos traslados disponibles. El móvil necesita `POST /devices` (vincular sin
/// tocar `HwidActual`) y `DELETE /devices/{id}` (revocar desde el panel).
///
/// **Estos endpoints ya existen.** Eran el punto 1 de MOBILE-ARQUITECTURA §6;
/// `backend-seats` los publicó con tests, y `flutter-sync` publicó el cliente
/// (`crearServicioDispositivos` en `nube/servicio_dispositivos_http.dart`).
/// `composicion.dart` lo cablea en `servicioDispositivosProvider`. El modo
/// "token pegado a mano" sigue existiendo como camino sin internet, pero ya no
/// es el único.
///
/// Implementa: `flutter-sync` (`ServicioDispositivosHttp`).
/// ## Dos identificadores distintos, y NO son intercambiables
///
/// Es la trampa de este contrato, y el motivo de que los parámetros se llamen
/// distinto en [vincular] y en [revocar]:
///
/// | Valor | De dónde sale | Dónde va |
/// |---|---|---|
/// | **Huella del equipo** | `IdentidadDispositivo.obtenerIdDispositivo()` (UUID v4 del almacén seguro) | cuerpo de `POST /devices` y claim `hwid` del token |
/// | **GUID del asiento** | claim `device_id` del token emitido, persistido en `meta` | ruta de `DELETE /devices/{id}` |
///
/// Pasarle la huella del equipo a `DELETE /devices/{id}` devuelve **404**: son
/// dos espacios de identificadores diferentes. El asiento es el *cupo* que
/// ocupa el equipo dentro de la licencia, no el equipo.
abstract interface class ServicioDispositivos {
  /// Vincula este dispositivo a la licencia y devuelve el token firmado que
  /// lleva su id en `hwid`. Falla si se agotaron los seats (`MaxDispositivos`).
  ///
  /// [idDispositivo] es la **huella del equipo**: lo que devuelve
  /// `IdentidadDispositivo.obtenerIdDispositivo()`.
  Future<ResultadoVinculacion> vincular({
    required String tokenLicencia,
    required String idDispositivo,
    required String nombreDispositivo,
    required String plataforma,
  });

  /// Revoca este asiento y libera el cupo. Tras esto el gate de arranque
  /// vuelve a la pantalla de activación.
  ///
  /// [idAsiento] es el **GUID del asiento** (`EstadoLicencia.idAsiento`, o sea
  /// el claim `device_id` del token), **no** la huella del equipo. Se llamaba
  /// `idDispositivo` y ese nombre era la trampa: invitaba a pasarle
  /// `obtenerIdDispositivo()`, que da 404 y deja el cupo ocupado — el dueño se
  /// queda fuera del POS *y* sin poder liberar el asiento para otro celular.
  ///
  /// Renombrado a propósito: documentar la distinción solo protege a quien lee
  /// el comentario; el nombre del parámetro protege a todos.
  Future<bool> revocar({
    required String tokenLicencia,
    required String idAsiento,
  });
}

/// Resultado de intentar vincular un dispositivo secundario.
@immutable
final class ResultadoVinculacion {
  /// Crea el resultado de la vinculación.
  const ResultadoVinculacion({
    required this.exito,
    this.tokenFirmado,
    this.mensaje,
    this.codigo,
  });

  /// `true` si el backend aceptó el dispositivo.
  final bool exito;

  /// Token firmado emitido para este dispositivo. `null` si falló.
  final String? tokenFirmado;

  /// Motivo legible (p. ej. "Ya usaste tus 2 dispositivos").
  ///
  /// Es **texto para el usuario**: se reescribe, se acorta y algún día se
  /// traduce. **Ningún cliente debe ramificar por su contenido** — para eso
  /// está [codigo].
  final String? mensaje;

  /// Código de error **estable** de `ErrorResponse.codigo`. `null` en éxito, y
  /// también cuando responde un backend viejo que todavía no emite el campo.
  ///
  /// ## Fuente única del catálogo: `server/README.md` §10
  ///
  /// Esa tabla y `CodigosError` de `server/PagoYa.Api/Contratos/Dtos.cs` son la
  /// verdad. **No copies literales a mano desde aquí**, ni siquiera para un
  /// ejemplo: el catálogo se amplía y cualquier copia se queda vieja en
  /// silencio. Los que consume el móvil están en un solo sitio, ya verificados
  /// carácter a carácter contra C#: `licencia/codigos_error_licencia.dart` y
  /// `nube/contratos_sync.dart` (`CodigosErrorSync`). Usa esas constantes.
  ///
  /// Ejemplos reales, verificados contra `Dtos.cs`: `cupo_dispositivos_lleno`
  /// (409, `/devices`, cupo de `MaxDispositivos` agotado → oportunidad de
  /// venta), `token_expirado` (renovar con `/validate`, **no** re-vincular),
  /// `asiento_revocado` (re-vincular el equipo, no vender nada).
  ///
  /// > Este docstring decía `sin_asientos_libres`, **que no existe**: nunca
  /// > estuvo en `CodigosError`. Un ejemplo inventado en un doc no es
  /// > cosmética — quien ramifique por él escribe una rama muerta que no
  /// > dispara nunca, y el fallo no se ve en compilación ni en tests, solo el
  /// > día que un cliente se queda sin cupo y la app no sabe ofrecerle el plan
  /// > mayor. De ahí la regla de arriba: literales de un solo sitio.
  ///
  /// ## Por qué existe este campo (añadido en la pasada final, §4.2)
  ///
  /// `flutter-licencia` escribió y probó un clasificador code-first en
  /// `codigos_error_licencia.dart`, pero como este resultado no transportaba el
  /// código, `codigoDeVinculacion()` devolvía siempre `null` y **todo** el flujo
  /// de asientos caía a la ruta de compatibilidad por subcadenas del mensaje.
  /// Es decir: el clasificador bueno existía y solo se ejercitaba en sus tests.
  ///
  /// Distinguir por código importa para el negocio, no solo por elegancia:
  /// "tu plan no incluye este equipo", "este equipo fue desvinculado" y "tu
  /// licencia venció" se arreglan de tres formas distintas y con tres precios
  /// distintos, y por texto son indistinguibles en cuanto alguien reescriba un
  /// mensaje.
  ///
  /// Lo rellena `flutter-sync` en su implementación HTTP con `cuerpo['codigo']`,
  /// igual que ya hace `transporte_http_sync._codigoError`. Cuando eso esté de
  /// punta a punta, la ruta de compatibilidad por subcadenas **se puede borrar**.
  final String? codigo;
}

// ---------------------------------------------------------------------------
// Facturación electrónica
// ---------------------------------------------------------------------------

/// Motor de facturación electrónica. Espejo de `IInvoiceEngine` del escritorio.
///
/// **En móvil este motor es SIEMPRE un cliente remoto** (regla §5.6): el
/// certificado `.pfx` del contribuyente no vive en el teléfono y aquí no se
/// firma ningún XML UBL. La app manda la venta al backend/PSE, que firma y
/// transmite a SUNAT, y recibe de vuelta el CDR y el PDF.
///
/// **Feature-gated por `invoicing`.** Sin el flag se inyecta
/// [MotorFacturacionDeshabilitado], igual que el escritorio inyecta
/// `InvoiceEngineDeshabilitado`.
///
/// Implementa: `flutter-sync`.
abstract interface class MotorFacturacion {
  /// `true` si la licencia habilita emitir comprobantes.
  bool get puedeEmitir;

  /// Emite el comprobante de una venta a través del backend/PSE.
  Future<ResultadoEmision> emitirComprobante(Venta venta);

  /// Reintenta las emisiones que quedaron pendientes por falta de red.
  ///
  /// Facturar exige internet; **vender no**. Si se cayó la señal, la venta ya
  /// está guardada y el comprobante se emite después. Nunca al revés.
  Future<int> reintentarPendientes();
}

/// Resultado de intentar emitir un comprobante. Espejo de `ResultadoEmision`.
@immutable
final class ResultadoEmision {
  /// Crea el resultado de la emisión.
  const ResultadoEmision({
    required this.aceptado,
    this.codigoCdr,
    this.urlPdf,
    this.mensaje,
  });

  /// Licencia sin el flag `invoicing`. Mismo texto comercial que el escritorio:
  /// dos mensajes distintos para el mismo cliente es cómo se generan tickets de
  /// soporte.
  factory ResultadoEmision.noHabilitado() => const ResultadoEmision(
        aceptado: false,
        mensaje:
            'La facturación electrónica requiere el plan PagoYa Facturador Pro.',
      );

  /// Sin red: la venta está guardada y el comprobante queda en cola.
  factory ResultadoEmision.pendientePorRed() => const ResultadoEmision(
        aceptado: false,
        mensaje: 'Sin conexión. El comprobante se enviará cuando vuelva la red.',
      );

  /// `true` si SUNAT/OSE lo aceptó.
  final bool aceptado;

  /// Código de respuesta del CDR.
  final String? codigoCdr;

  /// URL del PDF servido por el backend, para compartir por WhatsApp.
  ///
  /// En Perú esto vale más que la impresora: todos los clientes tienen
  /// WhatsApp y muchas bodegas no tienen térmica.
  final String? urlPdf;

  /// Mensaje legible (éxito o motivo del rechazo, para soporte).
  final String? mensaje;
}

/// Datos del emisor para la facturación remota.
@immutable
final class OpcionesFacturacion {
  /// Crea las opciones del emisor.
  const OpcionesFacturacion({
    this.urlBase,
    this.tokenLicencia,
    this.ruc = '',
    this.razonSocial = 'PagoYa',
    this.serieBoleta = 'B001',
    this.serieFactura = 'F001',
  });

  /// URL base del backend de facturación.
  final String? urlBase;

  /// Token de licencia que viaja como `Bearer`.
  final String? tokenLicencia;

  /// RUC del emisor.
  final String ruc;

  /// Razón social del emisor.
  final String razonSocial;

  /// Serie de boletas.
  final String serieBoleta;

  /// Serie de facturas.
  final String serieFactura;
}

/// **Null Object** de [MotorFacturacion]: rechaza la emisión sin tocar la red.
///
/// Se inyecta cuando la licencia no trae `invoicing`. La pantalla de cobro
/// sigue llamando `emitirComprobante` igual; lo que cambia es que recibe
/// `noHabilitado()` y muestra el upsell con candado. Ese es el punto del patrón:
/// que no haya un `if (tier == ...)` en la UI.
final class MotorFacturacionDeshabilitado implements MotorFacturacion {
  /// Crea el motor deshabilitado.
  const MotorFacturacionDeshabilitado();

  @override
  bool get puedeEmitir => false;

  @override
  Future<ResultadoEmision> emitirComprobante(Venta venta) async =>
      ResultadoEmision.noHabilitado();

  @override
  Future<int> reintentarPendientes() async => 0;
}
