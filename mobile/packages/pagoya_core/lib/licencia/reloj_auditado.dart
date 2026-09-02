/// Implementación de [RelojAuditado]: defensa contra manipulación del reloj.
///
/// En escritorio esto no existe — allí basta `DateTime.UtcNow`. En un teléfono
/// cambiar la fecha son tres toques, así que un token expirado "revive"
/// retrocediendo el reloj.
///
/// La política es deliberadamente **suave** (MOBILE-ARQUITECTURA §5.5): un
/// retroceso NO degrada la licencia de golpe. Cruzar zonas horarias, un cambio
/// de horario de verano o una sincronización NTP tardía no son ataques y no
/// pueden dejar sin caja a una bodega. Lo que se hace es:
///
/// 1. Mantener un `ultimo_visto_utc` **monotónico** en la tabla `meta`.
/// 2. Marcar [detectoRetroceso] si el reloj retrocedió más que
///    [RelojAuditado.toleranciaRetroceso], para que la UI avise y se fuerce una
///    revalidación online.
/// 3. Usar esa marca como **piso** en [ahoraUtc] cuando el retroceso es
///    sospechoso: así retrasar el reloj no resucita un token vencido, pero el
///    usuario legítimo sigue operando con normalidad.
///
library;

import 'meta_licencia.dart';
import 'puertos_licencia.dart';

/// [RelojAuditado] respaldado por la tabla `meta` de SQLite.
final class RelojAuditadoMeta implements RelojAuditado {
  /// Salto hacia adelante máximo que se persiste de una sola vez.
  ///
  /// Evita el envenenamiento del piso: si alguien pone el reloj en 2099, sin
  /// este tope `ultimo_visto_utc` quedaría en 2099 para siempre y la licencia
  /// se vería expirada aunque el reloj vuelva a la normalidad. Que el piso
  /// quede rezagado es inofensivo (solo es una cota inferior); que se adelante
  /// sí rompe al cliente.
  static const Duration maxSaltoAdelante = Duration(days: 400);

  final MetaLicencia _meta;
  final DateTime Function() _ahoraDelSistema;

  /// [ahoraDelSistema] se inyecta en los tests para simular un reloj movido.
  RelojAuditadoMeta(
    this._meta, {
    DateTime Function()? ahoraDelSistema,
  }) : _ahoraDelSistema = ahoraDelSistema ?? relojDelSistema;

  /// Reloj real del dispositivo.
  static DateTime relojDelSistema() => DateTime.now().toUtc();

  @override
  Future<DateTime> ahoraUtc() async {
    final DateTime ahora = _ahoraDelSistema().toUtc();
    final DateTime? piso = await _leerPiso();

    if (piso == null || !ahora.isBefore(piso)) return ahora;
    if (piso.difference(ahora) <= RelojAuditado.toleranciaRetroceso) {
      // Retroceso pequeño: se respeta el reloj del usuario.
      return ahora;
    }
    return piso;
  }

  @override
  Future<bool> detectoRetroceso() async {
    final DateTime ahora = _ahoraDelSistema().toUtc();
    final DateTime? piso = await _leerPiso();
    if (piso == null || !ahora.isBefore(piso)) return false;
    return piso.difference(ahora) > RelojAuditado.toleranciaRetroceso;
  }

  @override
  Future<void> registrarVisto() async {
    final DateTime ahora = _ahoraDelSistema().toUtc();
    final DateTime? piso = await _leerPiso();

    if (piso != null && ahora.isBefore(piso)) {
      // El piso NO baja nunca. Si el retroceso es sospechoso, se deja rastro
      // para soporte.
      if (piso.difference(ahora) > RelojAuditado.toleranciaRetroceso) {
        await _meta.escribirFecha(ClavesMetaLicencia.ultimoRetrocesoUtc, ahora);
      }
      return;
    }

    await _meta.escribirFecha(
      ClavesMetaLicencia.ultimoVistoUtc,
      _conTope(piso, ahora),
    );
  }

  /// Nunca avanza el piso más de [maxSaltoAdelante] de golpe.
  static DateTime _conTope(DateTime? piso, DateTime ahora) {
    if (piso == null) return ahora;
    final DateTime tope = piso.add(maxSaltoAdelante);
    return ahora.isAfter(tope) ? tope : ahora;
  }

  Future<DateTime?> _leerPiso() =>
      _meta.leerFecha(ClavesMetaLicencia.ultimoVistoUtc);
}

/// [RelojAuditado] sin persistencia, para tests y para el arranque de
/// emergencia si la base no abrió. Nunca marca retroceso.
final class RelojAuditadoSimple implements RelojAuditado {
  final DateTime Function() _ahora;

  RelojAuditadoSimple([DateTime Function()? ahora])
      : _ahora = ahora ?? RelojAuditadoMeta.relojDelSistema;

  @override
  Future<DateTime> ahoraUtc() async => _ahora().toUtc();

  @override
  Future<bool> detectoRetroceso() async => false;

  @override
  Future<void> registrarVisto() async {}
}
