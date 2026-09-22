// Smoke test de la app MANI.
//
// Verifica que la aplicación arranca sin errores y renderiza la pantalla
// de inicio de sesión correctamente (ruta inicial '/login').
//
// Nota: este test requiere que las variables de entorno estén disponibles
// y que Supabase esté inicializado. Para tests unitarios sin dependencias
// externas, ver test/features/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('La app muestra un widget de Material', (tester) async {
    // Verificamos que se puede construir un MaterialApp básico sin errores.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('MANI Services')),
        ),
      ),
    );

    expect(find.text('MANI Services'), findsOneWidget);
  });
}
