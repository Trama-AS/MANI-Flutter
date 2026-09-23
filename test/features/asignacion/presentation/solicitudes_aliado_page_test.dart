import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/regla_sitio.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';
import 'package:mani/features/asignacion/presentation/pages/solicitudes_aliado_page.dart';

import '../fakes.dart';

const _movil = Size(420, 900);
const _escritorio = Size(1300, 900);

Future<void> _montar(
  WidgetTester t,
  FakeAsignacionRepository repo, {
  Size tamano = _movil,
  VoidCallback? onAbrirCobertura,
  VoidCallback? onAbrirCategorias,
}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final cubit = crearCubit(repo);
  addTearDown(cubit.close);
  await t.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: SolicitudesAliadoPage(
          intervaloRefresco: null,
          onAbrirCobertura: onAbrirCobertura,
          onAbrirCategorias: onAbrirCategorias,
        ),
      ),
    ),
  );
  await cubit.cargar();
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

FakeAsignacionRepository _repoBase() => FakeAsignacionRepository([
  solicitud(
    's1',
    categoria: 'Plomería',
    minutosAtras: 45,
    reglas: const [
      ReglaSitio('mascotas', true),
      ReglaSitio('parqueadero', false),
      ReglaSitio('horario_acceso', '8-17'),
    ],
  ),
  solicitud('s2', categoria: 'Electricidad', minutosAtras: 3),
]);

void main() {
  testWidgets('muestra las solicitudes disponibles con conteos y la regla', (
    t,
  ) async {
    await _montar(t, _repoBase());

    expect(find.text('Solicitudes de servicio'), findsOneWidget);
    expect(find.bySemanticsLabel('Disponibles: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Mis trabajos: 0'), findsOneWidget);
    expect(
      find.textContaining('el primero en aceptar se queda con el trabajo'),
      findsOneWidget,
    );
    expect(find.text('Plomería'), findsOneWidget);
    expect(find.text('Electricidad'), findsOneWidget);
  });

  testWidgets(
    'antes de aceptar muestra zona, modalidad y TODAS las reglas del sitio, '
    'pero no la dirección',
    (t) async {
      await _montar(t, _repoBase());

      expect(find.text('Roma Norte · Cuauhtémoc'), findsNWidgets(2));
      expect(
        find.text('Requiere cotización antes de empezar'),
        findsNWidgets(2),
      );
      expect(find.text('Hay mascotas'), findsOneWidget);
      expect(find.text('Sin parqueadero'), findsOneWidget);
      expect(find.text('Horario acceso: 8-17'), findsOneWidget);
      expect(find.byKey(const ValueKey('direccion-solicitud')), findsNothing);
    },
  );

  testWidgets('marca como urgente a quien espera 30+ minutos', (t) async {
    await _montar(t, _repoBase());

    expect(find.text('Solicitada hace 45 min'), findsOneWidget);
    expect(find.text('Solicitada hace 3 min'), findsOneWidget);
  });

  testWidgets(
    'aceptar asegura el trabajo, pasa a Mis trabajos y revela la dirección',
    (t) async {
      final repo = _repoBase();
      await _montar(t, repo);

      await _tocar(t, const ValueKey('btn-aceptar-s1'));

      expect(repo.porId('s1')?.esMia, isTrue);
      expect(find.bySemanticsLabel('Mis trabajos: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Disponibles: 1'), findsOneWidget);
      expect(find.text('NUEVA'), findsOneWidget);
      expect(find.byKey(const ValueKey('direccion-solicitud')), findsOneWidget);
      expect(find.text('Calle Colima 120, Apto 401'), findsOneWidget);
      expect(find.textContaining('es tuya'), findsOneWidget);
    },
  );

  testWidgets('si otro aliado ganó, la tarjeta desaparece y se explica', (
    t,
  ) async {
    final repo = _repoBase();
    await _montar(t, repo);
    repo.tomadaPorOtroAliado('s1');

    await _tocar(t, const ValueKey('btn-aceptar-s1'));

    expect(find.byKey(const ValueKey('card-solicitud-s1')), findsNothing);
    expect(find.textContaining('Otro aliado tomó'), findsOneWidget);
    expect(find.bySemanticsLabel('Disponibles: 1'), findsOneWidget);
  });

  testWidgets('rechazar pide confirmación y un motivo opcional', (t) async {
    final repo = _repoBase();
    await _montar(t, repo);

    await _tocar(t, const ValueKey('btn-rechazar-s2'));
    expect(find.text('¿Rechazar Electricidad?'), findsOneWidget);
    expect(find.textContaining('Seguirá disponible'), findsOneWidget);

    await _tocar(t, const ValueKey('motivo-SIN_DISPONIBILIDAD'));
    await _tocar(t, const ValueKey('dlg-confirmar-rechazo'));

    expect(repo.rechazadas['s2'], MotivoRechazo.sinDisponibilidad);
    expect(find.byKey(const ValueKey('card-solicitud-s2')), findsNothing);
    expect(find.textContaining('Solicitud descartada'), findsOneWidget);
  });

  testWidgets('volver del diálogo no rechaza nada', (t) async {
    final repo = _repoBase();
    await _montar(t, repo);

    await _tocar(t, const ValueKey('btn-rechazar-s2'));
    await _tocar(t, const ValueKey('dlg-cancelar-rechazo'));

    expect(repo.llamadasRechazar, 0);
    expect(find.byKey(const ValueKey('card-solicitud-s2')), findsOneWidget);
  });

  testWidgets('mientras acepta, deshabilita las demás acciones', (t) async {
    final repo = _repoBase()..pausa = Completer<void>();
    await _montar(t, repo);

    await t.tap(find.byKey(const ValueKey('btn-aceptar-s1')));
    await t.pump();

    expect(find.text('Asegurando…'), findsOneWidget);
    final otro = t.widget<ManiButton>(
      find.byKey(const ValueKey('btn-aceptar-s2')),
    );
    expect(otro.onPressed, isNull);

    repo.pausa!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('sin solicitudes invita a revisar zonas y especialidades', (
    t,
  ) async {
    var zonas = 0;
    var especialidades = 0;
    await _montar(
      t,
      FakeAsignacionRepository(),
      onAbrirCobertura: () => zonas++,
      onAbrirCategorias: () => especialidades++,
    );

    expect(find.text('No hay solicitudes nuevas'), findsOneWidget);
    await _tocar(t, const ValueKey('btn-vacio-cobertura'));
    await _tocar(t, const ValueKey('btn-vacio-categorias'));
    expect((zonas, especialidades), (1, 1));
  });

  testWidgets('un aliado en revisión ve por qué no puede tomar trabajos', (
    t,
  ) async {
    final repo = _repoBase()
      ..fallarAlListar = const AsignacionFailure(
        AsignacionErrorTipo.aliadoNoVerificado,
      );
    await _montar(t, repo);

    expect(
      find.textContaining('Tu registro aún está en revisión'),
      findsOneWidget,
    );

    repo.fallarAlListar = null;
    await _tocar(t, const ValueKey('btn-reintentar-solicitudes'));
    expect(find.text('Plomería'), findsOneWidget);
  });

  testWidgets('en escritorio la lista se centra con ancho legible', (t) async {
    await _montar(t, _repoBase(), tamano: _escritorio);

    final ancho = t.getSize(find.byKey(const ValueKey('card-solicitud-s1')));
    expect(ancho.width, lessThanOrEqualTo(760));
  });

  test('las solicitudes asignadas no ofrecen acciones', () {
    final s = solicitud('x', estado: EstadoSolicitud.asignada, esMia: true);
    expect(s.estaDisponible, isFalse);
  });
}
