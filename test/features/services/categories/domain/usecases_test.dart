import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/entities/nueva_categoria.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';
import 'package:mani/features/services/categories/domain/usecases/categoria_usecases.dart';

import '../fakes.dart';

void main() {
  test(
    'ListarCategorias ordena alfabéticamente sin distinguir mayúsculas',
    () async {
      final repo = FakeCategoriasRepository([
        categoria('pintura'),
        categoria('Cerrajería'),
        categoria('Aire acondicionado'),
      ]);

      final r = await ListarCategorias(repo)();

      expect(r.map((c) => c.nombre), [
        'Aire acondicionado',
        'Cerrajería',
        'pintura',
      ]);
    },
  );

  group('CrearCategoria', () {
    test('delega en el repositorio y devuelve la categoría guardada', () async {
      final repo = FakeCategoriasRepository();
      final nueva = NuevaCategoria.crear(
        nombre: 'Plomería',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: false,
      );

      final creada = await CrearCategoria(repo)(nueva);

      expect(repo.ultimaCreada, nueva);
      expect(creada.nombre, 'Plomería');
      expect(creada.activa, isFalse);
      expect(creada.flujo, FlujoOperativo.cotizacionPrevia);
    });

    test('con un duplicado conocido falla sin llamar a la red', () {
      final repo = FakeCategoriasRepository();
      final nueva = NuevaCategoria.crear(
        nombre: 'plomería',
        flujo: FlujoOperativo.tarifaEstandar,
      );

      expect(
        () => CrearCategoria(repo)(nueva, existentes: [categoria('Plomería')]),
        throwsA(
          isA<CategoriaFailure>().having(
            (f) => f.tipo,
            'tipo',
            CategoriaErrorTipo.nombreDuplicado,
          ),
        ),
      );
      expect(repo.llamadasCrear, 0);
    });
  });

  group('CambiarEstadoCategoria', () {
    test('delega en el repositorio con el id limpio y el estado', () async {
      final repo = FakeCategoriasRepository([
        categoria('Plomería', id: 'cat-plo', activa: true, aliados: 3),
      ]);

      final actualizada = await CambiarEstadoCategoria(repo)(
        categoriaId: '  cat-plo ',
        activa: false,
      );

      expect(repo.ultimoCambioEstado, ('cat-plo', false));
      expect(actualizada.activa, isFalse);
      expect(actualizada.aliadosAsociados, 3);
    });

    test('con id vacío falla con noEncontrada sin llamar al repositorio', () {
      final repo = FakeCategoriasRepository();

      expect(
        () => CambiarEstadoCategoria(repo)(categoriaId: '   ', activa: false),
        throwsA(
          isA<CategoriaFailure>().having(
            (f) => f.tipo,
            'tipo',
            CategoriaErrorTipo.noEncontrada,
          ),
        ),
      );
      expect(repo.llamadasCambiarEstado, 0);
    });
  });
}
