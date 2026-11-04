import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profile_categories/data/repositories/categories_repository_impl.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';
import 'package:mani/core/network/gateway_exception.dart';

import 'fakes.dart';

void main() {
  late FakeCategoriesDataSource ds;
  late CategoriesRepositoryImpl repo;

  setUp(() {
    ds = FakeCategoriesDataSource();
    repo = CategoriesRepositoryImpl(remoteDataSource: ds);
  });

  test('mapea {id, nombre} de la RPC a entidades con emoji', () async {
    ds.catalogo = [
      {'id': 'a', 'nombre': 'Plomería y Redes Hidráulicas'},
      {'id': 'b', 'nombre': 'Instalación de Gas'},
    ];

    final cats = await repo.getAvailableCategories();

    expect(cats.map((c) => c.id), ['a', 'b']);
    expect(cats.first.label, 'Plomería y Redes Hidráulicas');
    expect(cats.first.emoji, '🔧');
    expect(cats.last.emoji, '🛠️'); // sin coincidencia -> genérico
  });

  test('obtiene y guarda como conjuntos de ids', () async {
    ds.mias = ['a', 'b'];
    expect(await repo.getSelectedCategoryIds(), {'a', 'b'});

    final guardadas = await repo.saveSelectedCategories({'a', 'c'});
    expect(ds.ultimoEnvio!.toSet(), {'a', 'c'});
    expect(guardadas, {'a', 'c'});
  });

  group('traduce el code MANI-CAT-* del Gateway', () {
    final casos = <String, CategoriesErrorTipo>{
      'MANI-CAT-401: sesión requerida': CategoriesErrorTipo.sinSesion,
      'MANI-CAT-403: solo un aliado activo': CategoriesErrorTipo.noEsAliado,
      // SCRUM-1392 C2: Core usa el mismo código cuando el aliado existe pero su
      // verificación no está aprobada.
      'MANI-CAT-403: la verificación del aliado debe estar aprobada para '
              'declarar categorías':
          CategoriesErrorTipo.noEsAliado,
      'MANI-CAT-422V: selecciona al menos una categoría':
          CategoriesErrorTipo.seleccionVacia,
      'MANI-CAT-422C: categoría no disponible':
          CategoriesErrorTipo.categoriaNoDisponible,
      'JWT expired': CategoriesErrorTipo.sinSesion,
      'algo raro': CategoriesErrorTipo.desconocido,
    };
    for (final c in casos.entries) {
      test(c.key, () async {
        ds.error = GatewayException(
          message: c.key,
          statusCode: 422,
          cuerpo: {'code': c.key.split(':').first, 'error': c.key},
        );
        await expectLater(
          repo.saveSelectedCategories({'a'}),
          throwsA(
            isA<CategoriesFailure>().having((f) => f.tipo, 'tipo', c.value),
          ),
        );
      });
    }

    // SCRUM-1392 C2: Core agrupa bajo MANI-CAT-403 dos casos — quien pide no es
    // aliado de este tenant, y es un aliado sin la verificación aprobada. El
    // mensaje al usuario tiene que ser cierto en los dos.
    test('el mensaje del 403 no afirma que baste con ser aliado', () {
      const falla = CategoriesFailure(CategoriesErrorTipo.noEsAliado);
      expect(falla.mensajeUsuario, contains('verificación aprobada'));
      expect(
        falla.mensajeUsuario,
        isNot('Solo los aliados pueden declarar las categorías que atienden.'),
      );
    });

    test('sin red -> sinConexion', () async {
      ds.error = Exception('SocketException: Failed host lookup');
      await expectLater(
        repo.getAvailableCategories(),
        throwsA(
          isA<CategoriesFailure>().having(
            (f) => f.tipo,
            'tipo',
            CategoriesErrorTipo.sinConexion,
          ),
        ),
      );
    });
  });
}
