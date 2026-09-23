import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/coverage/presentation/controllers/cobertura_controller.dart';
import 'package:mani/features/profiles/coverage/presentation/pages/declarar_cobertura_page.dart';

import 'fakes.dart';

Widget _app(CoberturaController c) => MaterialApp(
  home: DeclararCoberturaPage(controller: c, debounce: Duration.zero),
);

FilledButton _botonGuardar(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const ValueKey('btn-guardar-cobertura')));

void main() {
  testWidgets('muestra localidades y el botón Guardar inicia deshabilitado', (
    t,
  ) async {
    await t.pumpWidget(_app(CoberturaController(FakeCoberturaRepository())));
    await t.pumpAndSettle();

    expect(find.text('Toda Bogotá'), findsOneWidget);
    expect(find.text('Chapinero'), findsOneWidget);
    expect(find.text('Suba'), findsOneWidget);
    expect(find.text('Aún no has seleccionado zonas'), findsOneWidget);
    expect(_botonGuardar(t).onPressed, isNull);
  });

  testWidgets('seleccionar un barrio y guardar llama a la RPC con ese id', (
    t,
  ) async {
    final repo = FakeCoberturaRepository();
    await t.pumpWidget(_app(CoberturaController(repo)));
    await t.pumpAndSettle();

    await t.tap(find.text('Suba')); // expande y carga barrios
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('zona-niz')));
    await t.pump();

    expect(find.text('1 zona seleccionada'), findsOneWidget);
    expect(_botonGuardar(t).onPressed, isNotNull);

    await t.tap(find.byKey(const ValueKey('btn-guardar-cobertura')));
    await t.pumpAndSettle();

    expect(repo.ultimoEnvio, {'niz'});
    expect(find.textContaining('Cobertura guardada'), findsOneWidget);
  });

  testWidgets('localidad completa marca sus barrios como incluidos', (t) async {
    await t.pumpWidget(_app(CoberturaController(FakeCoberturaRepository())));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('grupo-check-cha')));
    await t.pump();
    // 'Chapinero' ya aparece también como chip; se expande tocando el subtítulo.
    await t.tap(find.text('Localidad completa'));
    await t.pumpAndSettle();

    expect(find.text('Incluida en Chapinero'), findsNWidgets(2));
  });

  testWidgets('la búsqueda muestra resultados con su ruta', (t) async {
    await t.pumpWidget(_app(CoberturaController(FakeCoberturaRepository())));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const ValueKey('buscar-zona')), 'ros');
    await t.pumpAndSettle();

    expect(find.text('Rosales'), findsOneWidget);
    expect(find.textContaining('Barrio · Chapinero · Bogotá'), findsOneWidget);
  });
}
