import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/services/categories/domain/entities/categoria_servicio.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/entities/nueva_categoria.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';

import '../fakes.dart';

Matcher _falla(CategoriaErrorTipo tipo) =>
    throwsA(isA<CategoriaFailure>().having((f) => f.tipo, 'tipo', tipo));

void main() {
  group('FlujoOperativo', () {
    test('traduce los códigos de BD usados en los seeds', () {
      expect(
        FlujoOperativo.desde('COTIZACION_PREVIA'),
        FlujoOperativo.cotizacionPrevia,
      );
      expect(
        FlujoOperativo.desde(' tarifa_estandar '),
        FlujoOperativo.tarifaEstandar,
      );
    });

    test(
      'un código desconocido o nulo devuelve null (no inventa un flujo)',
      () {
        expect(FlujoOperativo.desde('SUBASTA'), isNull);
        expect(FlujoOperativo.desde(null), isNull);
      },
    );

    test('cada flujo explica qué pasa y da un ejemplo', () {
      for (final f in FlujoOperativo.values) {
        expect(f.etiqueta, isNotEmpty);
        expect(f.descripcion, isNotEmpty);
        expect(f.ejemplo, isNotEmpty);
      }
    });
  });

  group('normalización de nombres', () {
    test('recorta y colapsa espacios internos', () {
      expect(normalizarNombre('  Aire   acondicionado '), 'Aire acondicionado');
    });

    test(
      'la clave ignora mayúsculas y espacios, igual que el índice único',
      () {
        expect(categoria('  PLOMERÍA ').claveNombre, 'plomería');
        expect(normalizarClaveNombre('Plomería'), 'plomería');
      },
    );
  });

  group('NuevaCategoria', () {
    test('se crea con el nombre normalizado', () {
      final n = NuevaCategoria.crear(
        nombre: '  Cerrajería   24h ',
        flujo: FlujoOperativo.tarifaEstandar,
      );
      expect(n.nombre, 'Cerrajería 24h');
      expect(n.flujo, FlujoOperativo.tarifaEstandar);
      expect(n.activa, isTrue);
    });

    test('rechaza nombres de menos de 3 o más de 60 caracteres', () {
      expect(
        () => NuevaCategoria.crear(
          nombre: 'ab',
          flujo: FlujoOperativo.tarifaEstandar,
        ),
        _falla(CategoriaErrorTipo.nombreInvalido),
      );
      expect(
        () => NuevaCategoria.crear(
          nombre: 'x' * 61,
          flujo: FlujoOperativo.tarifaEstandar,
        ),
        _falla(CategoriaErrorTipo.nombreInvalido),
      );
    });

    test('rechaza nombres sin letras', () {
      expect(
        () => NuevaCategoria.crear(
          nombre: '12345',
          flujo: FlujoOperativo.tarifaEstandar,
        ),
        _falla(CategoriaErrorTipo.nombreInvalido),
      );
    });

    test('acepta letras con tilde y ñ', () {
      expect(NuevaCategoria.validarNombre('Diseño'), isNull);
    });

    test('exige elegir un flujo operativo', () {
      expect(
        () => NuevaCategoria.crear(nombre: 'Pintura', flujo: null),
        _falla(CategoriaErrorTipo.flujoInvalido),
      );
    });

    test('detecta duplicados sin distinguir mayúsculas ni espacios', () {
      final existentes = [categoria('Plomería'), categoria('Pintura')];
      final n = NuevaCategoria.crear(
        nombre: '  PLOMERÍA ',
        flujo: FlujoOperativo.cotizacionPrevia,
      );
      expect(n.duplicadaEn(existentes)?.nombre, 'Plomería');
      expect(NuevaCategoria.buscarDuplicada('Jardinería', existentes), isNull);
    });
  });

  test('cada tipo de falla tiene un mensaje para el usuario', () {
    for (final t in CategoriaErrorTipo.values) {
      expect(CategoriaFailure(t).mensajeUsuario, isNotEmpty, reason: t.name);
    }
  });
}
