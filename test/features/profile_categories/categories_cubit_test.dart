import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';
import 'package:mani/features/profile_categories/presentation/bloc/categories_cubit.dart';

import 'fakes.dart';

Future<CategoriesCubit> _cargado(FakeCategoriesRepository repo) async {
  final cubit = cubitCon(repo);
  await Future<void>.delayed(Duration.zero);
  return cubit;
}

void main() {
  group('carga', () {
    test('trae el catálogo del tenant y marca las ya declaradas', () async {
      final cubit = await _cargado(
        FakeCategoriesRepository(guardadas: {'c-ele'}),
      );

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.categories, [plomeria, electricidad, cerrajeria]);
      expect(cubit.state.selectedIds, {'c-ele'});
    });

    test('ignora declaradas que ya no están en el catálogo', () async {
      final cubit = await _cargado(
        FakeCategoriesRepository(guardadas: {'c-ele', 'c-vieja'}),
      );

      expect(cubit.state.selectedIds, {'c-ele'});
    });

    test(
      'un error de carga queda en loadFailure y se puede reintentar',
      () async {
        final repo = FakeCategoriesRepository(
          fallaCarga: const CategoriesFailure(CategoriesErrorTipo.sinConexion),
        );
        final cubit = await _cargado(repo);

        expect(cubit.state.loadFailure?.tipo, CategoriesErrorTipo.sinConexion);
        expect(cubit.state.categories, isEmpty);

        repo.fallaCarga = null;
        await cubit.loadCategories();

        expect(cubit.state.loadFailure, isNull);
        expect(cubit.state.categories, hasLength(3));
      },
    );
  });

  group('selección', () {
    test('toggle marca y desmarca', () async {
      final cubit = await _cargado(FakeCategoriesRepository());

      cubit.toggleCategory('c-plo');
      cubit.toggleCategory('c-cer');
      expect(cubit.state.selectedIds, {'c-plo', 'c-cer'});

      cubit.toggleCategory('c-plo');
      expect(cubit.state.selectedIds, {'c-cer'});
    });
  });

  group('guardar', () {
    test('sin selección muestra error y no llama al backend', () async {
      final repo = FakeCategoriesRepository();
      final cubit = await _cargado(repo);

      await cubit.save();

      expect(cubit.state.showError, isTrue);
      expect(repo.llamadasGuardar, 0);
    });

    test('envía la selección completa y marca éxito', () async {
      final repo = FakeCategoriesRepository(guardadas: {'c-plo'});
      final cubit = await _cargado(repo);

      cubit.toggleCategory('c-plo'); // la quita
      cubit.toggleCategory('c-ele');
      cubit.toggleCategory('c-cer');
      await cubit.save();

      expect(repo.ultimoEnvio, {'c-ele', 'c-cer'});
      expect(repo.guardadas, {'c-ele', 'c-cer'});
      expect(cubit.state.saveSuccess, isTrue);
      expect(cubit.state.isSaving, isFalse);
    });

    test(
      'si el backend falla conserva la selección y expone el error',
      () async {
        final repo = FakeCategoriesRepository(
          fallaGuardado: const CategoriesFailure(
            CategoriesErrorTipo.categoriaNoDisponible,
          ),
        );
        final cubit = await _cargado(repo);

        cubit.toggleCategory('c-plo');
        await cubit.save();

        expect(cubit.state.saveSuccess, isFalse);
        expect(
          cubit.state.saveFailure?.tipo,
          CategoriesErrorTipo.categoriaNoDisponible,
        );
        expect(cubit.state.selectedIds, {'c-plo'});
      },
    );

    test(
      'cambiar la selección limpia el éxito y el error anteriores',
      () async {
        final cubit = await _cargado(FakeCategoriesRepository());

        cubit.toggleCategory('c-plo');
        await cubit.save();
        expect(cubit.state.saveSuccess, isTrue);

        cubit.toggleCategory('c-ele');
        expect(cubit.state.saveSuccess, isFalse);
        expect(cubit.state.saveFailure, isNull);
      },
    );
  });
}
