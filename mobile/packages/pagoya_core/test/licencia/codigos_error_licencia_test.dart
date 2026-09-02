/// Tests de la clasificación de errores del backend de asientos.
///
/// La regla que protegen: **se ramifica por `codigo`, nunca por el texto**. El
/// texto se reescribe, se acorta y algún día se traduce; el código es estable
/// (`server/README.md §10`).
///
/// ⚠ NO EJECUTADOS: el entorno donde se escribieron no tiene shell disponible.
library;

import 'package:pagoya_core/licencia/codigos_error_licencia.dart';
import 'package:pagoya_core/nube/contratos.dart';
import 'package:test/test.dart';

void main() {
  group('codigoDeVinculacion', () {
    test('lee el código que viaja en el resultado', () {
      // Mientras esta función devolvía `null`, el clasificador code-first no lo
      // veía nadie y todo el flujo caía a la ruta por texto.
      const ResultadoVinculacion r = ResultadoVinculacion(
        exito: false,
        mensaje: 'Límite alcanzado (3/3).',
        codigo: CodigosErrorLicencia.cupoDispositivosLleno,
      );

      expect(codigoDeVinculacion(r), CodigosErrorLicencia.cupoDispositivosLleno);
      expect(
        clasificarFalloVinculacion(
          codigo: codigoDeVinculacion(r),
          mensaje: r.mensaje,
        ),
        MotivoFalloVinculacion.cupoDispositivosLleno,
      );
    });

    test('null cuando el backend es anterior al catálogo', () {
      const ResultadoVinculacion r =
          ResultadoVinculacion(exito: false, mensaje: 'algo falló');

      expect(codigoDeVinculacion(r), isNull);
    });
  });

  group('clasificarFalloVinculacion por código', () {
    test('mapea cada código del catálogo a su motivo', () {
      const Map<String, MotivoFalloVinculacion> esperado =
          <String, MotivoFalloVinculacion>{
        CodigosErrorLicencia.claveNoEncontrada:
            MotivoFalloVinculacion.claveNoEncontrada,
        CodigosErrorLicencia.licenciaSuspendida:
            MotivoFalloVinculacion.licenciaSuspendida,
        CodigosErrorLicencia.licenciaRevocada:
            MotivoFalloVinculacion.licenciaRevocada,
        CodigosErrorLicencia.cupoDispositivosLleno:
            MotivoFalloVinculacion.cupoDispositivosLleno,
        CodigosErrorLicencia.dispositivoYaEsPrincipal:
            MotivoFalloVinculacion.yaEsDispositivoPrincipal,
        CodigosErrorLicencia.prefijosAgotados:
            MotivoFalloVinculacion.prefijosAgotados,
        CodigosErrorLicencia.tokenExpirado:
            MotivoFalloVinculacion.tokenExpirado,
        CodigosErrorLicencia.tokenInvalido:
            MotivoFalloVinculacion.tokenInvalido,
        CodigosErrorLicencia.asientoRevocado:
            MotivoFalloVinculacion.tokenInvalido,
        CodigosErrorLicencia.deviceIdRequerido:
            MotivoFalloVinculacion.tokenInvalido,
      };

      esperado.forEach((String codigo, MotivoFalloVinculacion motivo) {
        expect(
          clasificarFalloVinculacion(codigo: codigo),
          motivo,
          reason: 'código $codigo',
        );
      });
    });

    test('el código GANA sobre un texto que dice otra cosa', () {
      // Es la regla entera en un test: si el texto y el código discrepan, manda
      // el código. Un cambio de redacción no puede cambiar la acción del cliente.
      expect(
        clasificarFalloVinculacion(
          codigo: CodigosErrorLicencia.tokenExpirado,
          mensaje: 'Ya usaste todos tus dispositivos.',
        ),
        MotivoFalloVinculacion.tokenExpirado,
      );
    });

    test('token_expirado y token_invalido NO se confunden', () {
      // Antes del catálogo eran indistinguibles y mandábamos al dueño a
      // re-activar una licencia que solo había que renovar.
      expect(
        clasificarFalloVinculacion(codigo: CodigosErrorLicencia.tokenExpirado),
        isNot(
          clasificarFalloVinculacion(
            codigo: CodigosErrorLicencia.tokenInvalido,
          ),
        ),
      );
    });

    test('un código nuevo desconocido no se adivina', () {
      expect(
        clasificarFalloVinculacion(codigo: 'condicion_del_futuro'),
        MotivoFalloVinculacion.desconocido,
        reason: 'mejor mostrar el texto del backend que inventar una acción',
      );
    });
  });

  group('requiereSoporte / esTransitorio', () {
    test('solo los casos que el dueño no puede resolver piden soporte', () {
      expect(
        MotivoFalloVinculacion.cupoDispositivosLleno.requiereSoporte,
        isTrue,
      );
      expect(MotivoFalloVinculacion.licenciaSuspendida.requiereSoporte, isTrue);
      expect(MotivoFalloVinculacion.licenciaRevocada.requiereSoporte, isTrue);
      expect(MotivoFalloVinculacion.prefijosAgotados.requiereSoporte, isTrue);

      // Estos los arregla el propio usuario: reescribir la clave, renovar, o
      // volver a vincular.
      expect(MotivoFalloVinculacion.claveNoEncontrada.requiereSoporte, isFalse);
      expect(MotivoFalloVinculacion.tokenExpirado.requiereSoporte, isFalse);
      expect(MotivoFalloVinculacion.tokenInvalido.requiereSoporte, isFalse);
      expect(MotivoFalloVinculacion.red.requiereSoporte, isFalse);
    });

    test('solo la red es transitoria', () {
      for (final MotivoFalloVinculacion m in MotivoFalloVinculacion.values) {
        expect(m.esTransitorio, m == MotivoFalloVinculacion.red,
            reason: '$m');
      }
    });

    test('todo motivo tiene un mensaje por defecto no vacío', () {
      for (final MotivoFalloVinculacion m in MotivoFalloVinculacion.values) {
        expect(mensajePorDefectoDe(m), isNotEmpty, reason: '$m');
      }
    });
  });

  group('Ruta de compatibilidad (servers sin `codigo`)', () {
    test('sin código, cae al texto', () {
      expect(
        clasificarFalloVinculacion(mensaje: 'Ya usaste tus 3 dispositivos.'),
        MotivoFalloVinculacion.cupoDispositivosLleno,
      );
      expect(
        clasificarFalloVinculacion(mensaje: 'La licencia está suspendida.'),
        MotivoFalloVinculacion.licenciaSuspendida,
      );
      expect(
        clasificarFalloVinculacion(mensaje: 'El token expiró.'),
        MotivoFalloVinculacion.tokenExpirado,
      );
    });

    test('un código vacío se trata como ausente', () {
      expect(
        clasificarFalloVinculacion(codigo: '   ', mensaje: 'suspendida'),
        MotivoFalloVinculacion.licenciaSuspendida,
      );
    });

    test('ante la duda, desconocido: no se inventa una acción', () {
      expect(
        clasificarFalloVinculacion(mensaje: 'Algo salió mal.'),
        MotivoFalloVinculacion.desconocido,
      );
      expect(clasificarFalloVinculacion(), MotivoFalloVinculacion.desconocido);
    });
  });
}
