import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/availability/domain/entities/ausencia.dart';
import 'package:mani/features/availability/domain/failures/disponibilidad_failure.dart';
import 'package:mani/features/availability/presentation/pages/disponibilidad_page.dart';
import 'package:mani/features/availability/presentation/widgets/formulario_ausencia.dart';

import 'fakes.dart';

Widget _app(FakeDisponibilidadRepository repo) => MaterialApp(
  home: BlocProvider(
    create: (_) => cubitCon(repo)..cargar(),
    child: const DisponibilidadView(),
  ),
);

Future<void> _pantallaAlta(WidgetTester t) async {
  t.view.physicalSize = const Size(1000, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('sin ausencias muestra Disponible y el estado vacío', (t) async {
    await _pantallaAlta(t);
    await t.pumpWidget(_app(FakeDisponibilidadRepository()));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('estado-disponible')), findsOneWidget);
    expect(find.byKey(const ValueKey('sin-ausencias')), findsOneWidget);
  });

  testWidgets('lista las ausencias con motivo, fechas y nota', (t) async {
    await _pantallaAlta(t);
    await t.pumpWidget(
      _app(FakeDisponibilidadRepository(ausencias: [vacaciones])),
    );
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('ausencia-aus-1')), findsOneWidget);
    expect(find.text('Vacaciones'), findsOneWidget);
    expect(find.textContaining('Desde mar 20 oct 2026, 08:00'), findsOneWidget);
    expect(find.text('Viaje familiar'), findsOneWidget);
  });

  testWidgets('marcar no disponible con los valores por defecto la agrega', (
    t,
  ) async {
    await _pantallaAlta(t);
    final repo = FakeDisponibilidadRepository();
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('btn-nueva-ausencia')));
    await t.pumpAndSettle();
    // Por defecto: desde la próxima hora en punto (11:00) durante un día.
    expect(find.text('sáb 17 oct 2026'), findsOneWidget);
    expect(find.text('11:00'), findsNWidgets(2));

    await t.tap(find.byKey(const ValueKey('motivo-ENFERMEDAD')));
    await t.enterText(
      find.byKey(const ValueKey('nota-ausencia')),
      'Cita médica',
    );
    await t.tap(find.byKey(const ValueKey('btn-guardar-ausencia')));
    await t.pumpAndSettle();

    expect(repo.ausencias.single.motivo, MotivoAusencia.enfermedad);
    expect(repo.ausencias.single.nota, 'Cita médica');
    expect(find.text('Cita médica'), findsOneWidget);
    expect(find.text('Ausencia registrada'), findsOneWidget);
  });

  testWidgets('el formulario no envía un horario inválido', (t) async {
    var envios = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioAusencia(
            ahora: ahoraFijo,
            inicial: BorradorAusencia(
              inicio: DateTime(2026, 10, 21, 10),
              fin: DateTime(2026, 10, 20, 10),
              motivo: MotivoAusencia.otro,
            ),
            onGuardar: (_) async {
              envios++;
              return true;
            },
          ),
        ),
      ),
    );

    await t.tap(find.byKey(const ValueKey('btn-guardar-ausencia')));
    await t.pump();

    expect(find.byKey(const ValueKey('error-formulario')), findsOneWidget);
    expect(envios, 0);
  });

  testWidgets('un solapamiento mantiene abierto el formulario y avisa', (
    t,
  ) async {
    await _pantallaAlta(t);
    final repo = FakeDisponibilidadRepository(
      ausencias: [
        Ausencia(
          id: 'aus-hoy',
          inicio: DateTime(2026, 10, 17, 9),
          fin: DateTime(2026, 10, 19, 9),
          motivo: MotivoAusencia.enfermedad,
          activa: true,
        ),
      ],
    );
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('estado-no-disponible')), findsOneWidget);
    expect(find.text('En curso'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('btn-nueva-ausencia')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('btn-guardar-ausencia')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('btn-guardar-ausencia')), findsOneWidget);
    expect(find.textContaining('se cruza'), findsOneWidget);
    expect(repo.ausencias, hasLength(1));
  });

  testWidgets('eliminar pide confirmación y devuelve a Disponible', (t) async {
    await _pantallaAlta(t);
    final repo = FakeDisponibilidadRepository(
      ausencias: [
        Ausencia(
          id: 'aus-hoy',
          inicio: DateTime(2026, 10, 17, 9),
          fin: DateTime(2026, 10, 19, 9),
          motivo: MotivoAusencia.enfermedad,
          activa: true,
        ),
      ],
    );
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('eliminar-aus-hoy')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirmar-eliminar')));
    await t.pumpAndSettle();

    expect(repo.ausencias, isEmpty);
    expect(find.byKey(const ValueKey('estado-disponible')), findsOneWidget);
  });

  testWidgets('un error de carga ofrece reintentar', (t) async {
    await _pantallaAlta(t);
    final repo = FakeDisponibilidadRepository(
      fallaCarga: const DisponibilidadFailure(
        DisponibilidadErrorTipo.noEsAliado,
      ),
    );
    await t.pumpWidget(_app(repo));
    await t.pumpAndSettle();

    expect(
      find.text('Solo los aliados pueden gestionar su disponibilidad.'),
      findsOneWidget,
    );

    repo.fallaCarga = null;
    await t.tap(find.byKey(const ValueKey('btn-reintentar-disponibilidad')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('estado-disponible')), findsOneWidget);
  });
}
