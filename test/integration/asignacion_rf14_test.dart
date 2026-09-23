import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/asignacion/data/repositories/asignacion_repository_impl.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';
import 'package:mani/features/asignacion/presentation/pages/solicitudes_aliado_page.dart';

import '../features/asignacion/fakes.dart';

/// Prueba de integración del flujo de aceptación (RF-14).
///
/// Recorre la interfaz completa: dos aliados abren la misma solicitud, el
/// primero la acepta y el segundo debe ver que ya no está disponible.
///
/// Vive en `test/integration/` y no en `integration_test/` a propósito:
/// `flutter test integration_test` exige un dispositivo conectado, lo que no
/// existe en un runner de CI. Aquí se ejecuta headless con el flutter tester,
/// cubriendo el mismo recorrido de interfaz (CFG-06 / SCRUM-955).
void main() {
  const solicitudId = 'sol-001';
  const boton = ValueKey('btn-aceptar-$solicitudId');

  SolicitudesAliadoCubit cubitDe(
    ServidorAsignacionFake servidor,
    String aliadoId,
  ) {
    final cubit = crearCubit(
      AsignacionRepositoryImpl(
        servidor.sesion(aliadoId),
        logger: StructuredLogger(canal: 'test', sink: (_) {}),
      ),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> mostrar(
    WidgetTester tester,
    SolicitudesAliadoCubit cubit,
    String aliadoId,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey(aliadoId),
        home: BlocProvider.value(
          value: cubit,
          child: const SolicitudesAliadoPage(intervaloRefresco: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocarAceptar(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(boton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(boton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'una solicitud se asigna a un único aliado y el resto ve ya_no_disponible',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final servidor = ServidorAsignacionFake()
        ..registrarAliado('aliado-a', AliadoFake(tenantId: 't1'))
        ..registrarAliado('aliado-b', AliadoFake(tenantId: 't1'))
        ..publicar(id: solicitudId, tenantId: 't1');

      // Ambos aliados cargan su bandeja: los dos ven la solicitud disponible.
      final cubitA = cubitDe(servidor, 'aliado-a');
      final cubitB = cubitDe(servidor, 'aliado-b');
      await cubitA.cargar();
      await cubitB.cargar();

      // Aliado A acepta primero.
      await mostrar(tester, cubitA, 'aliado-a');
      await tocarAceptar(tester);
      expect(find.text('Calle Colima 120, Apto 401'), findsOneWidget);

      // Aliado B, con la pantalla desactualizada, intenta aceptar la misma.
      await mostrar(tester, cubitB, 'aliado-b');
      expect(find.byKey(boton), findsOneWidget, reason: 'aún la ve');
      await tocarAceptar(tester);

      expect(find.textContaining('Otro aliado tomó'), findsOneWidget);
      expect(find.byKey(boton), findsNothing);
      expect(find.text('Calle Colima 120, Apto 401'), findsNothing);

      // La asignación persistida sigue siendo la del primer aliado.
      final persistida = servidor.fila(solicitudId);
      expect(persistida['aliado_id'], 'aliado-a');
      expect(persistida['estado'], 'ASIGNADA');
    },
  );
}
