import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/domain/entities/documento_kyc.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';

import '../fakes.dart';

void main() {
  group('EstadoVerificacion.desde', () {
    test('traduce los valores de BD, incluido VERIFICADO de los seeds', () {
      expect(
        EstadoVerificacion.desde('PENDIENTE'),
        EstadoVerificacion.pendiente,
      );
      expect(
        EstadoVerificacion.desde('VERIFICADO'),
        EstadoVerificacion.aprobado,
      );
      expect(EstadoVerificacion.desde('aprobado'), EstadoVerificacion.aprobado);
      expect(
        EstadoVerificacion.desde(' RECHAZADO '),
        EstadoVerificacion.rechazado,
      );
    });

    test(
      'un valor desconocido se trata como pendiente (nunca se pierde en la bandeja)',
      () {
        expect(
          EstadoVerificacion.desde('EN_REVISION'),
          EstadoVerificacion.pendiente,
        );
      },
    );
  });

  test(
    'TipoAliado distingue empresa (PERSONA_JURIDICA) de persona natural',
    () {
      expect(TipoAliado.desde('PERSONA_JURIDICA'), TipoAliado.empresa);
      expect(TipoAliado.desde('PERSONA_NATURAL'), TipoAliado.personaNatural);
    },
  );

  group('DocumentoKyc', () {
    test(
      'mapea los tipos que envía el registro y degrada lo desconocido a "otro"',
      () {
        expect(
          TipoDocumentoKyc.desde('CEDULA_CIUDADANIA'),
          TipoDocumentoKyc.cedulaCiudadania,
        );
        expect(
          TipoDocumentoKyc.desde('CAMARA_COMERCIO'),
          TipoDocumentoKyc.camaraComercio,
        );
        expect(TipoDocumentoKyc.desde('PASAPORTE'), TipoDocumentoKyc.otro);
      },
    );

    test('expone nombre de archivo y detecta imágenes', () {
      final png = doc('1', ruta: 'kyc/t1/cedula_frente.PNG');
      final pdf = doc('2', ruta: 'kyc/t1/rut.pdf');
      expect(png.nombreArchivo, 'cedula_frente.PNG');
      expect(png.esImagen, isTrue);
      expect(pdf.esImagen, isFalse);
    });
  });

  group('SolicitudAliado', () {
    test('iniciales toma las dos primeras palabras', () {
      expect(aliado(nombre: 'carlos alberto gómez').iniciales, 'CA');
      expect(aliado(nombre: '  Ana  ').iniciales, 'A');
    });

    test(
      'coincideCon busca por nombre, correo y especialidad sin distinguir mayúsculas',
      () {
        final a = aliado(
          nombre: 'Carlos Mendoza',
          email: 'cm@mail.com',
          categorias: ['Electricidad'],
        );
        expect(a.coincideCon(''), isTrue);
        expect(a.coincideCon('MENDO'), isTrue);
        expect(a.coincideCon('cm@'), isTrue);
        expect(a.coincideCon('electri'), isTrue);
        expect(a.coincideCon('plomería'), isFalse);
      },
    );

    test('diasEnEspera cuenta desde el registro', () {
      expect(aliado(diasEspera: 4).diasEnEspera(DateTime.now()), 4);
    });

    test('tieneDocumentos y estaPendiente', () {
      expect(aliado(documentos: const []).tieneDocumentos, isFalse);
      expect(
        aliado(estado: EstadoVerificacion.rechazado).estaPendiente,
        isFalse,
      );
    });
  });

  group('DecisionVerificacion', () {
    test(
      'rechazar exige un motivo de 10 a 500 caracteres (sin contar espacios extremos)',
      () {
        expect(
          () => DecisionVerificacion.rechazar('   corto   '),
          throwsA(
            isA<VerificacionFailure>().having(
              (f) => f.tipo,
              'tipo',
              VerificacionErrorTipo.motivoInvalido,
            ),
          ),
        );
        expect(
          () => DecisionVerificacion.rechazar('x' * 501),
          throwsA(isA<VerificacionFailure>()),
        );
      },
    );

    test('rechazar recorta el motivo válido', () {
      final d = DecisionVerificacion.rechazar('  Documento ilegible  ');
      expect(d, isA<Rechazo>());
      expect((d as Rechazo).motivo, 'Documento ilegible');
    });

    test('aprobar no requiere datos y es igual por valor', () {
      expect(
        const DecisionVerificacion.aprobar(),
        const DecisionVerificacion.aprobar(),
      );
    });
  });

  test('cada tipo de falla tiene un mensaje para el usuario', () {
    for (final t in VerificacionErrorTipo.values) {
      expect(VerificacionFailure(t).mensajeUsuario, isNotEmpty, reason: t.name);
    }
  });
}
