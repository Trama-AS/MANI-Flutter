// Test maestro de US-03.1.1 — Crear categoría con flujo operativo (QS-07).
//
// Recorre la historia de punta a punta con TODAS las capas reales:
//   GestionCategoriasPage → CategoriasCubit → casos de uso →
//   CategoriasRepositoryImpl → CategoriasRemoteDataSource
// Solo se sustituye Supabase por `ServidorCategoriasFake`, que replica las
// reglas de las RPC de `003_categorias_servicio.sql` (tenant desde la sesión,
// solo ADMIN_TENANT, validación 422 e índice único por tenant 409).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/services/categories/data/repositories/categorias_repository_impl.dart';
import 'package:mani/features/services/categories/presentation/pages/gestion_categorias_page.dart';

import '../features/services/categories/fakes.dart';

const _tenantA = 'tenant-a';
const _tenantB = 'tenant-b';

ServidorCategoriasFake _servidor() =>
    ServidorCategoriasFake(tenantSesion: _tenantA)
      ..sembrar(tenantId: _tenantA, nombre: 'Plomería', aliados: 5)
      ..sembrar(
        tenantId: _tenantA,
        nombre: 'Cerrajería',
        estado: 'INACTIVO',
        flujo: 'TARIFA_ESTANDAR',
      )
      // Catálogo de OTRA franquicia: nunca debe verse desde el tenant A.
      ..sembrar(tenantId: _tenantB, nombre: 'Pintura');

Future<List<Map<String, dynamic>>> _montarApp(
  WidgetTester t,
  ServidorCategoriasFake servidor,
) async {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final logs = <Map<String, dynamic>>[];
  final repo = CategoriasRepositoryImpl(
    servidor,
    logger: StructuredLogger(
      canal: 'test',
      sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
    ),
  );
  final cubit = crearCubit(repo);
  addTearDown(cubit.close);

  await t.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: const GestionCategoriasPage(),
      ),
    ),
  );
  await cubit.cargar();
  await t.pumpAndSettle();
  return logs;
}

Future<void> _tocar(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

Future<void> _crearCategoria(
  WidgetTester t, {
  required String nombre,
  required String flujo,
  bool visible = true,
}) async {
  await t.tap(find.byKey(const ValueKey('btn-nueva-categoria')));
  await t.pumpAndSettle();
  await t.enterText(
    find.byKey(const ValueKey('campo-nombre-categoria')),
    nombre,
  );
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pumpAndSettle();
  await _tocar(t, ValueKey('flujo-$flujo'));
  if (!visible) {
    await _tocar(t, const ValueKey('switch-visible'));
  }
  await _tocar(t, const ValueKey('btn-crear-categoria'));
}

void main() {
  testWidgets(
    'US-03.1.1 flujo completo: el admin crea categorías con su flujo operativo',
    (t) async {
      final servidor = _servidor();
      final logs = await _montarApp(t, servidor);

      // CA-1: el admin ve solo el catálogo de su tenant, incluidas las ocultas.
      expect(find.text('Plomería'), findsOneWidget);
      expect(find.text('Cerrajería'), findsOneWidget);
      expect(find.text('Pintura'), findsNothing);
      expect(find.text('1 visible para clientes · 1 oculta'), findsOneWidget);

      // CA-2: crea una categoría visible con cotización previa. Queda ACTIVA
      // en BD de inmediato (QS-07: sin despliegues) y aparece en el catálogo.
      await _crearCategoria(
        t,
        nombre: '  Aire   acondicionado ',
        flujo: 'COTIZACION_PREVIA',
      );
      final aire = servidor.delTenant(_tenantA).last;
      expect(aire['nombre'], 'Aire acondicionado');
      expect(aire['estado'], 'ACTIVO');
      expect(aire['flujo_operativo'], 'COTIZACION_PREVIA');
      expect(find.text('Aire acondicionado'), findsOneWidget);
      expect(find.text('NUEVA'), findsOneWidget);
      expect(
        find.textContaining('Ya aparece en el catálogo de tus clientes'),
        findsOneWidget,
      );

      // CA-3: crea una categoría oculta con tarifa estándar. El nombre
      // "Pintura" existe en OTRO tenant, pero no choca con este.
      await _crearCategoria(
        t,
        nombre: 'Pintura',
        flujo: 'TARIFA_ESTANDAR',
        visible: false,
      );
      final pintura = servidor.delTenant(_tenantA).last;
      expect(pintura['estado'], 'INACTIVO');
      expect(pintura['flujo_operativo'], 'TARIFA_ESTANDAR');
      expect(find.text('2 visibles para clientes · 2 ocultas'), findsOneWidget);

      // Trazabilidad (criterio de US-03.1.1): log JSON con los campos
      // acordados, uno por categoría creada.
      final creadas = logs
          .where((l) => l['event'] == 'US-03.1.1.crear_categoria')
          .toList();
      expect(creadas, hasLength(2));
      for (final log in creadas) {
        for (final campo in [
          'timestamp',
          'level',
          'service_id',
          'trace_id',
          'tenant_id',
          'message',
        ]) {
          expect(log[campo], isNotNull, reason: campo);
        }
        expect(log['tenant_id'], _tenantA);
      }
      expect(creadas.map((l) => l['flujo_operativo']), [
        'COTIZACION_PREVIA',
        'TARIFA_ESTANDAR',
      ]);
    },
  );

  testWidgets('CA-4: no se puede repetir un nombre del catálogo', (t) async {
    final servidor = _servidor();
    await _montarApp(t, servidor);
    final antes = servidor.delTenant(_tenantA).length;

    await t.tap(find.byKey(const ValueKey('btn-nueva-categoria')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('campo-nombre-categoria')),
      ' PLOMERÍA ',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await _tocar(t, const ValueKey('flujo-COTIZACION_PREVIA'));

    expect(
      find.text('Ya tienes la categoría "Plomería" en tu catálogo.'),
      findsOneWidget,
    );
    await _tocar(t, const ValueKey('btn-crear-categoria'));
    expect(find.byType(Dialog), findsOneWidget, reason: 'botón deshabilitado');
    expect(servidor.delTenant(_tenantA), hasLength(antes));
  });

  testWidgets(
    'CA-4b: si otro admin crea el mismo nombre a la vez, gana el índice único',
    (t) async {
      final servidor = _servidor();
      await _montarApp(t, servidor);

      await t.tap(find.byKey(const ValueKey('btn-nueva-categoria')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('campo-nombre-categoria')),
        'Jardinería',
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      await _tocar(t, const ValueKey('flujo-COTIZACION_PREVIA'));

      // Otro administrador del mismo tenant la crea desde otro dispositivo.
      servidor.sembrar(tenantId: _tenantA, nombre: 'Jardinería');

      await _tocar(t, const ValueKey('btn-crear-categoria'));

      final jardinerias = servidor
          .delTenant(_tenantA)
          .where((f) => f['nombre'] == 'Jardinería');
      expect(jardinerias, hasLength(1), reason: 'sin duplicados en BD');
      // El formulario sigue abierto, explica el motivo y el catálogo se
      // actualizó con la categoría del otro admin.
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.text('Ya tienes la categoría "Jardinería" en tu catálogo.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'CA-5: un usuario que no es ADMIN_TENANT no gestiona categorías',
    (t) async {
      final servidor = _servidor()..rolSesion = 'CLIENTE';
      await _montarApp(t, servidor);

      expect(
        find.text(
          'Solo el administrador del tenant puede gestionar categorías.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('btn-nueva-categoria')), findsNothing);
    },
  );

  testWidgets('CA-6: sesión expirada pide volver a iniciar sesión', (t) async {
    final servidor = _servidor()..haySesion = false;
    await _montarApp(t, servidor);

    expect(find.textContaining('Tu sesión expiró'), findsOneWidget);
  });
}
