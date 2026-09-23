import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';
import 'package:mani/features/profile_categories/presentation/pages/categories_page.dart';

import 'fakes.dart';

Widget _app(FakeCategoriesRepository repo) => MaterialApp(
  home: BlocProvider(
    create: (_) => cubitCon(repo),
    child: const CategoriesView(),
  ),
);

Finder _check(String id) => find.descendant(
  of: find.byKey(ValueKey('categoria-$id')),
  matching: find.byIcon(Icons.check),
);

void main() {
  testWidgets(
    'muestra las categorías del tenant con las ya declaradas marcadas',
    (t) async {
      await t.pumpWidget(_app(FakeCategoriesRepository(guardadas: {'c-ele'})));
      await t.pumpAndSettle();

      expect(find.text('Plomería'), findsOneWidget);
      expect(find.text('Electricidad'), findsOneWidget);
      expect(find.text('Cerrajería'), findsOneWidget);
      expect(_check('c-ele'), findsOneWidget);
      expect(_check('c-plo'), findsNothing);
      expect(find.text('1 categoría(s) seleccionada(s)'), findsOneWidget);
    },
  );

  testWidgets('tocar una categoría la marca y guardar envía la selección', (
    t,
  ) async {
    final repo = FakeCategoriesRepository();
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('categoria-c-plo')));
    await t.tap(find.byKey(const ValueKey('categoria-c-cer')));
    await t.pump();
    expect(_check('c-plo'), findsOneWidget);
    expect(find.text('2 categoría(s) seleccionada(s)'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('btn-guardar-categorias')));
    await t.pumpAndSettle();

    expect(repo.ultimoEnvio, {'c-plo', 'c-cer'});
    expect(find.text('Categorías guardadas'), findsOneWidget);
  });

  testWidgets('guardar sin selección muestra el error y no llama al backend', (
    t,
  ) async {
    final repo = FakeCategoriesRepository();
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('btn-guardar-categorias')));
    await t.pump();

    expect(
      find.text('Selecciona al menos una categoría para continuar.'),
      findsOneWidget,
    );
    expect(repo.llamadasGuardar, 0);
  });

  testWidgets('un error al guardar se muestra y conserva la selección', (
    t,
  ) async {
    final repo = FakeCategoriesRepository(
      fallaGuardado: const CategoriesFailure(
        CategoriesErrorTipo.categoriaNoDisponible,
      ),
    );
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('categoria-c-plo')));
    await t.tap(find.byKey(const ValueKey('btn-guardar-categorias')));
    await t.pumpAndSettle();

    expect(find.textContaining('ya no están disponibles'), findsOneWidget);
    expect(_check('c-plo'), findsOneWidget);
  });

  testWidgets('error de carga ofrece reintentar', (t) async {
    final repo = FakeCategoriesRepository(
      fallaCarga: const CategoriesFailure(CategoriesErrorTipo.sinConexion),
    );
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    expect(find.textContaining('Sin conexión'), findsOneWidget);

    repo.fallaCarga = null;
    await t.tap(find.byKey(const ValueKey('btn-reintentar-categorias')));
    await t.pumpAndSettle();

    expect(find.text('Plomería'), findsOneWidget);
  });
}
