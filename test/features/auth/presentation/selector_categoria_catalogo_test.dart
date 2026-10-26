import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/presentation/widgets/selector_categoria_catalogo.dart';
import 'package:mani/features/services/categories/data/datasources/catalogo_publico_datasource.dart';

void main() {
  Future<void> montar(
    WidgetTester tester, {
    required Future<List<CategoriaPublica>> Function() cargar,
    required ValueChanged<String?> onChanged,
    String? value,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SelectorCategoriaCatalogo(
          cargar: cargar,
          value: value,
          onChanged: onChanged,
        ),
      ),
    ),
  );

  testWidgets('muestra carga y luego las categorías del catálogo', (
    tester,
  ) async {
    final completer = Completer<List<CategoriaPublica>>();
    String? elegida;
    await montar(
      tester,
      cargar: () => completer.future,
      onChanged: (v) => elegida = v,
    );
    expect(find.byKey(const Key('categorias_cargando')), findsOneWidget);

    completer.complete(const [
      CategoriaPublica(id: 'c-1', nombre: 'Plomería'),
      CategoriaPublica(id: 'c-2', nombre: 'Electricidad'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dropdown_categoria_aliado')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electricidad').last);
    await tester.pumpAndSettle();
    expect(elegida, 'c-2');
  });

  testWidgets('si falla la carga muestra error y reintenta', (tester) async {
    var intentos = 0;
    await montar(
      tester,
      cargar: () async {
        intentos++;
        if (intentos == 1) throw Exception('sin red');
        return const [CategoriaPublica(id: 'c-1', nombre: 'Plomería')];
      },
      onChanged: (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categorias_error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_reintentar_categorias')));
    await tester.pumpAndSettle();
    expect(intentos, 2);
    expect(find.byKey(const Key('dropdown_categoria_aliado')), findsOneWidget);
  });

  testWidgets('catálogo vacío muestra el aviso', (tester) async {
    await montar(tester, cargar: () async => const [], onChanged: (_) {});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categorias_vacias')), findsOneWidget);
  });

  testWidgets('una categoría elegida que ya no existe se descarta', (
    tester,
  ) async {
    String? elegida = 'ya-no-existe';
    await montar(
      tester,
      value: elegida,
      cargar: () async => const [
        CategoriaPublica(id: 'c-1', nombre: 'Plomería'),
      ],
      onChanged: (v) => elegida = v,
    );
    await tester.pumpAndSettle();
    expect(elegida, isNull);
  });
}
