// SCRUM-1388 (RF-09): reglas del sitio en lenguaje normal; contacto e
// instrucciones de ingreso solo para el aliado asignado.
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/domain/entities/regla_sitio.dart';
import 'package:mani/features/asignacion/presentation/utils/formato_solicitud.dart';

String _texto(String clave, Object? valor) =>
    describirRegla(ReglaSitio(clave, valor)).texto;

void main() {
  group('describirHorario', () {
    test('rango de días contiguos y horas sin cero inicial', () {
      expect(
        _texto('horario', {
          'inicio': '08:00',
          'fin': '17:00',
          'diasPermitidos': ['LUN', 'MAR', 'MIE', 'JUE', 'VIE'],
        }),
        'Horario: lunes a viernes, de 8:00 a 17:00',
      );
    });

    test('días sueltos se enumeran en orden, sin repetir', () {
      expect(
        describirHorario({
          'inicio': '07:30',
          'fin': '12:00',
          'diasPermitidos': ['sab', 'LUN', 'MIE', 'LUN'],
        }),
        'Horario: lunes, miércoles y sábado, de 7:30 a 12:00',
      );
    });

    test('toda la semana', () {
      expect(
        describirHorario({
          'inicio': '10:00',
          'fin': '18:00',
          'diasPermitidos': ['LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB', 'DOM'],
        }),
        'Horario: todos los días, de 10:00 a 18:00',
      );
    });

    test('dos días contiguos no se muestran como rango', () {
      expect(
        describirHorario({
          'diasPermitidos': ['SAB', 'DOM'],
        }),
        'Horario: sábado y domingo',
      );
    });

    test('sin datos útiles no muestra formato técnico', () {
      expect(describirHorario({'diasPermitidos': 'X'}), 'Horario restringido');
    });
  });

  test('requisitos en texto legible, sin llaves ni corchetes', () {
    expect(
      _texto('permisosRequeridos', ['ARL', 'Alturas', 'Curso']),
      'Permisos requeridos: ARL, Alturas y Curso',
    );
    expect(
      _texto('elementosProteccion', ['Casco']),
      'Protección obligatoria: Casco',
    );
    expect(
      _texto('requiereAprobacionPrevia', true),
      'Requiere aprobación previa para ingresar',
    );
    expect(
      _texto('instruccionesIngreso', ' Pedir llave en recepción '),
      'Instrucciones de ingreso: Pedir llave en recepción',
    );
    expect(
      _texto('contactoAcceso', {
        'nombre': 'Portería',
        'telefono': '3000000000',
      }),
      'Contacto de acceso: Portería · 3000000000',
    );
    expect(_texto('otra_cosa', ['a', 'b']), 'Otra cosa: a y b');
    expect(_texto('otro_mapa', {'x': 'uno', 'y': null}), 'Otro mapa: uno');
  });

  group('reglasParaMostrar', () {
    const reglas = [
      ReglaSitio('contactoAcceso', {'nombre': 'Portería', 'telefono': '300'}),
      ReglaSitio('elementosProteccion', ['Casco']),
      ReglaSitio('horario', {'inicio': '08:00', 'fin': '17:00'}),
      ReglaSitio('instruccionesIngreso', 'Pedir llave'),
      ReglaSitio('permisosRequeridos', <String>[]),
      ReglaSitio('requiereAprobacionPrevia', false),
    ];

    test('en la oferta quita el contacto, las instrucciones y las vacías', () {
      expect(reglasParaMostrar(reglas, asignado: false).map((r) => r.clave), [
        'elementosProteccion',
        'horario',
      ]);
    });

    test('asignado ve también el contacto y las instrucciones', () {
      expect(reglasParaMostrar(reglas, asignado: true).map((r) => r.clave), [
        'contactoAcceso',
        'elementosProteccion',
        'horario',
        'instruccionesIngreso',
      ]);
    });

    test('valores vacíos no se muestran', () {
      const vacias = [
        ReglaSitio('instruccionesIngreso', '  '),
        ReglaSitio('contactoAcceso', {'nombre': null, 'telefono': ''}),
        ReglaSitio('nota', null),
      ];
      expect(reglasParaMostrar(vacias, asignado: true), isEmpty);
    });

    test('reglas antiguas con true/false se conservan', () {
      const antiguas = [ReglaSitio('mascotas', false)];
      expect(reglasParaMostrar(antiguas, asignado: false), antiguas);
    });
  });
}
