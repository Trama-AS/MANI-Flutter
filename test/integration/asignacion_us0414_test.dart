// Test maestro de US-04.1.4 — Aceptar/rechazar solicitud sin doble asignación
// (RF-14, QS-09, QS-06, QS-12).
//
// Recorre la historia de punta a punta con TODAS las capas reales:
//   SolicitudesAliadoPage → SolicitudesAliadoCubit → casos de uso →
//   AsignacionRepositoryImpl → AsignacionRemoteDataSource
// Solo se sustituye Supabase por `ServidorAsignacionFake`, que replica las RPC
// de `005_aceptar_rechazar_solicitud.sql` para varios aliados a la vez: la
// asignación es un check-and-set atómico tras la latencia de red, igual que el
// UPDATE condicional de PostgreSQL (DD-MANI §7.1).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/asignacion/data/repositories/asignacion_repository_impl.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';
import 'package:mani/features/asignacion/presentation/pages/solicitudes_aliado_page.dart';

import '../features/asignacion/fakes.dart';

const _tenant = 'tenant-a';

ServidorAsignacionFake _servidor() {
  final s = ServidorAsignacionFake(latencia: const Duration(milliseconds: 20))
    ..registrarAliado('carlos', AliadoFake(tenantId: _tenant))
    ..registrarAliado('diana', AliadoFake(tenantId: _tenant))
    ..registrarAliado(
      'pendiente',
      AliadoFake(tenantId: _tenant, verificado: false),
    )
    ..publicar(
      id: 'fuga',
      tenantId: _tenant,
      categoria: 'Plomería',
      minutosAtras: 50,
      reglas: {'mascotas': true, 'horario_acceso': '8-17'},
    )
    ..publicar(id: 'grifo', tenantId: _tenant, minutosAtras: 5)
    // No elegibles para Carlos: otra categoría, otra zona y otro tenant.
    ..publicar(id: 'pintura', tenantId: _tenant, categoria: 'Pintura')
    ..publicar(
      id: 'polanco',
      tenantId: _tenant,
      zona: 'Polanco',
      zonaPadre: 'Miguel Hidalgo',
    )
    ..publicar(id: 'otro-tenant', tenantId: 'tenant-b');
  return s;
}

class _Sesion {
  _Sesion(this.cubit, this.logs);
  final SolicitudesAliadoCubit cubit;
  final List<Map<String, dynamic>> logs;
}

_Sesion _sesion(ServidorAsignacionFake servidor, String aliadoId) {
  final logs = <Map<String, dynamic>>[];
  final cubit = crearCubit(
    AsignacionRepositoryImpl(
      servidor.sesion(aliadoId),
      logger: StructuredLogger(
        canal: 'test',
        sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
      ),
    ),
  );
  addTearDown(cubit.close);
  return _Sesion(cubit, logs);
}

Future<void> _mostrar(WidgetTester t, _Sesion sesion, String clave) async {
  await t.pumpWidget(
    MaterialApp(
      key: ValueKey(clave),
      home: BlocProvider.value(
        value: sesion.cubit,
        child: const SolicitudesAliadoPage(intervaloRefresco: null),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tocar(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

void _vista(WidgetTester t) {
  t.view.physicalSize = const Size(420, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets(
    'US-04.1.4 flujo completo: el aliado revisa, acepta una y rechaza otra',
    (t) async {
      _vista(t);
      final servidor = _servidor();
      final carlos = _sesion(servidor, 'carlos');
      await carlos.cubit.cargar();
      await _mostrar(t, carlos, 'carlos');

      // CA-1: solo ve solicitudes pendientes de SUS categorías y zonas, de su
      // tenant, con la que más espera primero.
      expect(find.bySemanticsLabel('Disponibles: 2'), findsOneWidget);
      for (final ajena in ['pintura', 'polanco', 'otro-tenant']) {
        expect(find.byKey(ValueKey('card-solicitud-$ajena')), findsNothing);
      }
      final yFuga = t
          .getTopLeft(find.byKey(const ValueKey('card-solicitud-fuga')))
          .dy;
      final yGrifo = t
          .getTopLeft(find.byKey(const ValueKey('card-solicitud-grifo')))
          .dy;
      expect(yFuga, lessThan(yGrifo), reason: 'FIFO');

      // CA-2 · QS-06: antes de aceptar ve TODAS las reglas del sitio, pero no
      // la dirección exacta del cliente.
      expect(find.text('Hay mascotas'), findsOneWidget);
      expect(find.text('Horario acceso: 8-17'), findsOneWidget);
      expect(find.byKey(const ValueKey('direccion-solicitud')), findsNothing);

      // CA-3: acepta → la solicitud es suya, pasa a "Mis trabajos", se revela
      // la dirección, queda el evento en la línea de tiempo (QS-12) y el
      // cliente recibe la notificación.
      await _tocar(t, const ValueKey('btn-aceptar-fuga'));
      expect(servidor.fila('fuga')['aliado_id'], 'carlos');
      expect(servidor.fila('fuga')['estado'], 'ASIGNADA');
      expect(find.bySemanticsLabel('Mis trabajos: 1'), findsOneWidget);
      expect(find.text('Calle Colima 120, Apto 401'), findsOneWidget);
      expect(servidor.eventos.single['tipo_evento'], 'SOLICITUD_ASIGNADA');
      expect(servidor.notificaciones, hasLength(1));

      // CA-4: rechaza la otra con motivo → desaparece para él, pero sigue
      // disponible para los demás aliados.
      await _tocar(t, const ValueKey('tab-disponibles'));
      await _tocar(t, const ValueKey('btn-rechazar-grifo'));
      await _tocar(t, const ValueKey('motivo-FUERA_DE_ZONA'));
      await _tocar(t, const ValueKey('dlg-confirmar-rechazo'));
      expect(find.byKey(const ValueKey('card-solicitud-grifo')), findsNothing);
      expect(servidor.rechazos[('grifo', 'carlos')], 'FUERA_DE_ZONA');
      expect(servidor.fila('grifo')['estado'], 'PENDIENTE');
      final diana = _sesion(servidor, 'diana');
      await diana.cubit.cargar();
      expect(diana.cubit.state.bandeja.porId('grifo'), isNotNull);

      // Trazabilidad: log JSON por intento, con duración (QS-09 < 500 ms).
      final aceptar = carlos.logs.firstWhere(
        (l) => l['event'] == 'US-04.1.4.aceptar_solicitud',
      );
      for (final campo in [
        'timestamp',
        'level',
        'service_id',
        'trace_id',
        'tenant_id',
        'message',
      ]) {
        expect(aceptar[campo], isNotNull, reason: campo);
      }
      expect(aceptar['duracion_ms'], lessThan(500));
    },
  );

  testWidgets(
    'CA-5 · QS-09: dos aliados aceptan A LA VEZ y solo uno se queda con ella',
    (t) async {
      _vista(t);
      final servidor = _servidor();
      final carlos = _sesion(servidor, 'carlos');
      final diana = _sesion(servidor, 'diana');
      await carlos.cubit.cargar();
      await diana.cubit.cargar();
      await _mostrar(t, diana, 'diana');

      // Ambos tocan "Aceptar" en el mismo instante.
      final resultados = await t.runAsync(
        () => Future.wait([
          carlos.cubit.aceptar('fuga'),
          diana.cubit.aceptar('fuga'),
        ]),
      );
      await t.pumpAndSettle();

      expect(resultados!.where((gano) => gano), hasLength(1));
      expect(servidor.eventos, hasLength(1), reason: 'una sola asignación');
      expect(servidor.notificaciones, hasLength(1));
      expect(servidor.fila('fuga')['aliado_id'], 'carlos');

      // La perdedora ve por qué y la solicitud desaparece de su bandeja.
      expect(find.textContaining('Otro aliado tomó'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-solicitud-fuga')), findsNothing);
      expect(find.bySemanticsLabel('Mis trabajos: 0'), findsOneWidget);
    },
  );

  testWidgets(
    'CA-6: aceptar dos veces (doble toque o reintento) es idempotente',
    (t) async {
      final servidor = _servidor();
      final repo = AsignacionRepositoryImpl(
        servidor.sesion('carlos'),
        logger: StructuredLogger(canal: 'test', sink: (_) {}),
      );

      final primera = await t.runAsync(() => repo.aceptar('fuga'));
      final reintento = await t.runAsync(() => repo.aceptar('fuga'));

      expect(reintento, primera);
      expect(servidor.eventos, hasLength(1));
      expect(servidor.notificaciones, hasLength(1));
    },
  );

  testWidgets('CA-7: un aliado aún no verificado no puede tomar trabajos', (
    t,
  ) async {
    _vista(t);
    final servidor = _servidor();
    final pendiente = _sesion(servidor, 'pendiente');
    await pendiente.cubit.cargar();
    await _mostrar(t, pendiente, 'pendiente');

    expect(
      find.textContaining('Tu registro aún está en revisión'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('btn-aceptar-fuga')), findsNothing);
    expect(servidor.fila('fuga')['aliado_id'], isNull);
  });
}
