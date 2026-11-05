import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/presentation/widgets/fotos_adjuntas_viewer.dart';

const _rutas = ['t1/s1/a.jpg', 't1/s1/b.jpg', 't1/s1/c.jpg'];

Future<String> _resolver(String ruta) async => 'https://cdn.test/$ruta';

Future<void> _montar(
  WidgetTester tester,
  List<String> rutas, {
  Future<String> Function(String)? resolver,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FotosAdjuntasPreview(
          fotosRutas: rutas,
          resolverUrl: resolver ?? _resolver,
        ),
      ),
    ),
  );
}

void main() {
  group('Fotos adjuntas de la solicitud', () {
    testWidgets('sin fotos no ocupa espacio', (tester) async {
      await _montar(tester, const []);
      await tester.pumpAndSettle();
      expect(find.byType(InkWell), findsNothing);
      expect(find.textContaining('foto'), findsNothing);
    });

    testWidgets('mientras resuelve las URLs muestra la carga', (tester) async {
      final pendiente = <String>[];
      await _montar(
        tester,
        const ['a.jpg'],
        resolver: (r) {
          pendiente.add(r);
          return Future<String>.delayed(
            const Duration(seconds: 1),
            () => 'https://cdn.test/$r',
          );
        },
      );
      expect(find.text('Cargando vista previa...'), findsOneWidget);
      expect(pendiente, ['a.jpg']);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('1 foto adjunta'), findsOneWidget);
    });

    testWidgets('si no se puede resolver ninguna, lo explica', (tester) async {
      await _montar(tester, const [
        'a.jpg',
        'b.jpg',
      ], resolver: (_) async => throw StateError('sin storage'));
      await tester.pumpAndSettle();
      expect(find.text('2 foto(s) no disponible(s)'), findsOneWidget);
    });

    testWidgets('muestra las miniaturas y el detalle navega entre las fotos', (
      tester,
    ) async {
      await _montar(tester, _rutas);
      await tester.pumpAndSettle();

      expect(find.text('3 fotos adjuntas'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsNWidgets(3));

      // «Ver en detalle» abre en la primera foto.
      await tester.tap(find.text('Ver en detalle'));
      await tester.pumpAndSettle();
      expect(find.byType(FotosDetalleDialog), findsOneWidget);
      expect(find.text('Foto 1 de 3'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_forward_ios_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Foto 2 de 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Foto 1 de 3'), findsOneWidget);

      // Las miniaturas de abajo llevan a la foto elegida.
      final miniaturas = find.descendant(
        of: find.byType(FotosDetalleDialog),
        matching: find.byType(AnimatedContainer),
      );
      expect(miniaturas, findsNWidgets(3));
      await tester.tap(miniaturas.at(2));
      await tester.pumpAndSettle();
      expect(find.text('Foto 3 de 3'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);

      await tester.tap(find.bySemanticsLabel('Cerrar vista detallada'));
      await tester.pumpAndSettle();
      expect(find.byType(FotosDetalleDialog), findsNothing);
    });

    testWidgets('tocar una miniatura abre el detalle en esa foto', (
      tester,
    ) async {
      await _montar(tester, _rutas);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.fullscreen).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Foto 2 de 3'), findsOneWidget);
    });

    testWidgets('con una sola foto el detalle no muestra flechas', (
      tester,
    ) async {
      await _montar(tester, const ['a.jpg']);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver en detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Foto 1 de 1'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('al cambiar las fotos vuelve a resolverlas', (tester) async {
      final pedidas = <String>[];
      Future<String> resolver(String r) async {
        pedidas.add(r);
        return 'https://cdn.test/$r';
      }

      await _montar(tester, const ['a.jpg'], resolver: resolver);
      await tester.pumpAndSettle();
      await _montar(tester, const ['a.jpg', 'b.jpg'], resolver: resolver);
      await tester.pumpAndSettle();

      expect(pedidas, ['a.jpg', 'a.jpg', 'b.jpg']);
      expect(find.text('2 fotos adjuntas'), findsOneWidget);
    });
  });

  group('resolverUrlStorage', () {
    test('una URL absoluta se usa tal cual', () async {
      expect(
        await resolverUrlStorage('https://cdn.test/x.jpg'),
        'https://cdn.test/x.jpg',
      );
      expect(
        await resolverUrlStorage('http://cdn.test/x.jpg'),
        'http://cdn.test/x.jpg',
      );
    });

    test('sin poder firmar, usa la URL pública del bucket', () async {
      // En pruebas Supabase no está inicializado: la firma falla y se cae a
      // la URL pública en vez de dejar la foto sin mostrar.
      final url = await resolverUrlStorage('t1/s1/a.jpg');
      expect(
        url,
        endsWith('/storage/v1/object/public/solicitudes/t1/s1/a.jpg'),
      );
    });
  });
}
