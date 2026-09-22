import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';
import 'package:mani/features/profiles/verification/presentation/pages/bandeja_verificacion_page.dart';
import 'package:mani/features/profiles/verification/presentation/pages/detalle_aliado_page.dart';

import '../fakes.dart';

const _escritorio = Size(1400, 900);
const _movil = Size(400, 860);

Future<BandejaVerificacionCubit> _montar(
  WidgetTester t,
  FakeVerificacionRepository repo, {
  Size tamano = _escritorio,
  FakeUrlOpener? opener,
}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final cubit = crearCubit(repo, opener: opener);
  addTearDown(cubit.close);
  await t.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: const BandejaVerificacionPage(),
      ),
    ),
  );
  await cubit.cargar();
  await t.pumpAndSettle();
  return cubit;
}

FakeVerificacionRepository _repoBase() => FakeVerificacionRepository([
  aliado(
    id: 'a1',
    nombre: 'Ana Ruiz',
    email: 'ana@correo.com',
    diasEspera: 5,
    categorias: ['Plomería'],
  ),
  aliado(
    id: 'a2',
    nombre: 'Beto Díaz',
    email: 'beto@correo.com',
    diasEspera: 1,
    documentos: const [],
  ),
  aliado(
    id: 'r1',
    nombre: 'Rita Sol',
    estado: EstadoVerificacion.rechazado,
    motivoRechazo: 'La cédula está vencida.',
    fechaVerificacion: DateTime.now(),
  ),
]);

void main() {
  group('Escritorio (maestro-detalle)', () {
    testWidgets(
      'muestra la bandeja de pendientes con conteos y el panel vacío',
      (t) async {
        await _montar(t, _repoBase());

        expect(find.text('Solicitudes de aliados'), findsOneWidget);
        expect(find.bySemanticsLabel('Pendientes: 2'), findsOneWidget);
        expect(find.bySemanticsLabel('Rechazados: 1'), findsOneWidget);
        expect(find.text('Ana Ruiz'), findsOneWidget);
        expect(find.text('Beto Díaz'), findsOneWidget);
        expect(find.text('Rita Sol'), findsNothing);
        expect(find.text('Selecciona un aliado'), findsOneWidget);
      },
    );

    testWidgets('marca como urgente a quien lleva 3+ días esperando', (
      t,
    ) async {
      await _montar(t, _repoBase());

      expect(find.text('Registrado hace 5 días'), findsOneWidget);
      expect(find.text('Registrado ayer'), findsOneWidget);
      expect(find.text('Sin documentos'), findsOneWidget);
    });

    testWidgets('al tocar una tarjeta muestra el perfil con sus documentos', (
      t,
    ) async {
      await _montar(t, _repoBase());

      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      expect(find.text('ana@correo.com'), findsNWidgets(2)); // tarjeta + panel
      expect(find.text('Documentos KYC (1)'), findsOneWidget);
      expect(find.text('Cédula de ciudadanía'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-aprobar')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-rechazar')), findsOneWidget);
    });

    testWidgets(
      'aprobar pide confirmación, aprueba y pasa al siguiente pendiente',
      (t) async {
        final repo = _repoBase();
        await _montar(t, repo);
        await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
        await t.pumpAndSettle();

        await t.tap(find.byKey(const ValueKey('btn-aprobar')));
        await t.pumpAndSettle();
        expect(find.text('¿Aprobar a Ana Ruiz?'), findsOneWidget);

        await t.tap(find.byKey(const ValueKey('dlg-confirmar-aprobar')));
        await t.pumpAndSettle();

        expect(repo.porId('a1')?.estado, EstadoVerificacion.aprobado);
        expect(find.textContaining('Ana Ruiz fue aprobado'), findsOneWidget);
        expect(find.bySemanticsLabel('Pendientes: 1'), findsOneWidget);
        expect(find.bySemanticsLabel('Aprobados: 1'), findsOneWidget);
        // El panel avanzó a Beto (el siguiente pendiente).
        expect(find.text('Documentos KYC (0)'), findsOneWidget);
      },
    );

    testWidgets('cancelar la confirmación no aprueba', (t) async {
      final repo = _repoBase();
      await _montar(t, repo);
      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('btn-aprobar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dlg-cancelar')));
      await t.pumpAndSettle();

      expect(repo.llamadasResolver, 0);
      expect(repo.porId('a1')?.estaPendiente, isTrue);
    });

    testWidgets(
      'sin documentos el botón Aprobar está deshabilitado y se explica por qué',
      (t) async {
        final repo = _repoBase();
        await _montar(t, repo);
        await t.tap(find.byKey(const ValueKey('card-aliado-a2')));
        await t.pumpAndSettle();

        expect(find.textContaining('no adjuntó documentos'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('btn-aprobar')));
        await t.pumpAndSettle();
        expect(find.textContaining('¿Aprobar'), findsNothing);
      },
    );

    testWidgets('rechazar valida el motivo, admite motivos rápidos y rechaza', (
      t,
    ) async {
      final repo = _repoBase();
      await _montar(t, repo);
      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('btn-rechazar')));
      await t.pumpAndSettle();
      expect(find.text('Rechazar a Ana Ruiz'), findsOneWidget);

      // Sin motivo: muestra error y no cierra.
      await t.tap(find.byKey(const ValueKey('dlg-confirmar-rechazar')));
      await t.pumpAndSettle();
      expect(find.text('Escribe al menos 10 caracteres.'), findsOneWidget);
      expect(repo.llamadasResolver, 0);

      await t.tap(find.text('Documento vencido'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('campo-motivo-rechazo')),
        'Documento vencido. Carga una cédula vigente.',
      );
      await t.tap(find.byKey(const ValueKey('dlg-confirmar-rechazar')));
      await t.pumpAndSettle();

      expect(repo.porId('a1')?.estado, EstadoVerificacion.rechazado);
      expect(
        repo.porId('a1')?.motivoRechazo,
        'Documento vencido. Carga una cédula vigente.',
      );
      expect(find.textContaining('Rechazaste a Ana Ruiz'), findsOneWidget);
    });

    testWidgets('la pestaña Rechazados muestra el resultado con el motivo', (
      t,
    ) async {
      await _montar(t, _repoBase());

      await t.tap(find.byKey(const ValueKey('tab-rechazado')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('card-aliado-r1')));
      await t.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('resultado-verificacion')),
        findsOneWidget,
      );
      expect(find.text('La cédula está vencida.'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-aprobar')), findsNothing);
    });

    testWidgets('ver un documento abre su URL firmada', (t) async {
      final opener = FakeUrlOpener();
      await _montar(t, _repoBase(), opener: opener);
      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('ver-doc-d-a1')));
      await t.pumpAndSettle();

      expect(opener.abiertas.single.host, 'storage.test');
    });

    testWidgets('la búsqueda filtra y muestra un estado vacío claro', (
      t,
    ) async {
      await _montar(t, _repoBase());

      await t.enterText(find.byKey(const ValueKey('buscar-aliado')), 'beto');
      await t.pumpAndSettle();
      expect(find.text('Ana Ruiz'), findsNothing);
      expect(find.text('Beto Díaz'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('buscar-aliado')), 'zzz');
      await t.pumpAndSettle();
      expect(find.text('Sin resultados'), findsOneWidget);
    });

    testWidgets('bandeja sin pendientes celebra que está al día', (t) async {
      await _montar(t, FakeVerificacionRepository([]));
      expect(find.text('¡Bandeja al día!'), findsOneWidget);
    });

    testWidgets('error de carga ofrece reintentar', (t) async {
      final repo = FakeVerificacionRepository([aliado()])
        ..fallarAlListar = const VerificacionFailure(
          VerificacionErrorTipo.noAutorizado,
        );
      await _montar(t, repo);

      expect(
        find.text('Solo el administrador del tenant puede verificar aliados.'),
        findsOneWidget,
      );

      repo.fallarAlListar = null;
      await t.tap(find.byKey(const ValueKey('btn-reintentar')));
      await t.pumpAndSettle();
      expect(find.text('Carlos Mendoza'), findsOneWidget);
    });
  });

  group('Móvil', () {
    testWidgets('tocar una tarjeta abre el perfil en su propia pantalla', (
      t,
    ) async {
      await _montar(t, _repoBase(), tamano: _movil);

      expect(find.text('Selecciona un aliado'), findsNothing);
      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      expect(find.byType(DetalleAliadoPage), findsOneWidget);
      expect(find.text('Perfil del aliado'), findsOneWidget);
    });

    testWidgets('tras aprobar vuelve a la bandeja con el conteo actualizado', (
      t,
    ) async {
      final repo = _repoBase();
      await _montar(t, repo, tamano: _movil);
      await t.tap(find.byKey(const ValueKey('card-aliado-a1')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('btn-aprobar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dlg-confirmar-aprobar')));
      await t.pumpAndSettle();

      expect(find.byType(DetalleAliadoPage), findsNothing);
      expect(find.bySemanticsLabel('Pendientes: 1'), findsOneWidget);
      expect(find.text('Ana Ruiz'), findsNothing);
    });
  });
}
