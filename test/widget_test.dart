// Prueba de humo de la pantalla inicial.
//
// La plantilla original verificaba un contador que ya no existe; esta version
// comprueba lo que la pantalla realmente renderiza tras el cambio a la
// arquitectura base con Supabase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mani/main.dart';

void main() {
  testWidgets('la pantalla inicial muestra el titulo de la aplicacion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ManiApp());

    expect(find.text('MANI Services'), findsOneWidget);
    expect(find.byIcon(Icons.handyman), findsOneWidget);
  });
}
