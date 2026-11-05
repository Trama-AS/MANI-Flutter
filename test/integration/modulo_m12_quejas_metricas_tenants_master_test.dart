// Prueba maestra frontend de M-12 (SCRUM-895, 896, 900, 901). Cada criterio C1-C3 se recorre en la pantalla real con
// fuentes en memoria que responden como Core (mismos códigos de error). El aislamiento por tenant y las reglas
// definitivas se prueban contra PostgreSQL en MANI-Node (tests/integration/pg/moduloM12Master.pg.test.js); aquí se
// prueba qué ve y qué envía la app.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/session/guardas_ruta.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
import 'package:mani/features/complaints/data/quejas_datasource.dart';
import 'package:mani/features/complaints/domain/queja.dart';
import 'package:mani/features/complaints/presentation/dialogo_queja.dart';
import 'package:mani/features/complaints/presentation/quejas_cubit.dart';
import 'package:mani/features/complaints/presentation/quejas_page.dart';
import 'package:mani/features/metrics/data/metricas_datasource.dart';
import 'package:mani/features/metrics/presentation/metricas_page.dart';
import 'package:mani/features/platform/data/tenants_datasource.dart';
import 'package:mani/features/platform/presentation/tenants_page.dart';

GatewayException _error(int status, String code, String mensaje) =>
    GatewayException(
      message: mensaje,
      statusCode: status,
      cuerpo: {
        'error': '$code: $mensaje',
        'code': code,
        'correlationId': 'corr',
      },
    );

// ------------------------------------------------------------------ fuentes en memoria
/// Quejas como Core: una abierta por solicitud y transiciones válidas.
class _Quejas implements FuenteQuejas {
  final quejas = <Queja>[];
  final enviados = <Map<String, Object?>>[];

  @override
  Future<Queja> registrar(
    String solicitudId, {
    required MotivoQueja motivo,
    required String descripcion,
  }) async {
    enviados.add({
      'solicitudId': solicitudId,
      'motivo': motivo,
      'descripcion': descripcion,
    });
    if (quejas.any((q) => q.solicitudId == solicitudId && !q.estado.esFinal)) {
      throw _error(
        409,
        'MANI-QJA-409A',
        'la solicitud ya tiene una queja abierta',
      );
    }
    final q = Queja(
      id: 'q-${quejas.length + 1}',
      solicitudId: solicitudId,
      categoria: 'Plomería',
      motivo: motivo,
      descripcion: descripcion.trim(),
      estado: EstadoQueja.abierta,
      historial: const [
        TransicionQueja(estadoNuevo: EstadoQueja.abierta, actorRol: 'CLIENT'),
      ],
    );
    quejas.add(q);
    return q;
  }

  @override
  Future<List<Queja>> mias() async => List.of(quejas);

  @override
  Future<List<Queja>> delTenant({EstadoQueja? estado}) async =>
      quejas.where((q) => estado == null || q.estado == estado).toList();

  @override
  Future<Queja> detalle(String quejaId) async =>
      quejas.firstWhere((q) => q.id == quejaId);

  @override
  Future<Queja> cambiarEstado(
    String quejaId,
    EstadoQueja estado, {
    String? nota,
  }) async {
    final i = quejas.indexWhere((q) => q.id == quejaId);
    final q = quejas[i];
    if (!q.estado.siguientes.contains(estado)) {
      throw _error(
        409,
        'MANI-QJA-409T',
        'una queja en estado ${q.estado.valor} no puede pasar a ${estado.valor}',
      );
    }
    final nueva = Queja(
      id: q.id,
      solicitudId: q.solicitudId,
      categoria: q.categoria,
      motivo: q.motivo,
      descripcion: q.descripcion,
      estado: estado,
      respuesta: estado.esFinal ? nota : q.respuesta,
      historial: [
        ...q.historial,
        TransicionQueja(
          estadoAnterior: q.estado,
          estadoNuevo: estado,
          actorRol: 'ADMIN',
          nota: nota,
        ),
      ],
    );
    quejas[i] = nueva;
    return nueva;
  }
}

class _Metricas implements FuenteMetricas {
  _Metricas(this.respuesta);

  final MetricasOperativas respuesta;
  final periodos = <List<String>>[];

  @override
  Future<MetricasOperativas> consultar(String desde, String hasta) async {
    periodos.add([desde, hasta]);
    return respuesta;
  }
}

class _Tenants implements FuenteTenants {
  _Tenants({this.sinPermiso = false});

  final bool sinPermiso;
  final tenants = [
    const TenantPlataforma(
      id: 't-1',
      nombre: 'Plomería Express',
      slug: 'plomeria',
      estado: EstadoTenant.activo,
    ),
  ];
  final cambios = <List<Object>>[];

  @override
  Future<List<TenantPlataforma>> listar() async {
    if (sinPermiso) {
      throw const GatewayException(
        message: 'No tienes permiso para realizar esta acción.',
        statusCode: 403,
      );
    }
    return List.of(tenants);
  }

  @override
  Future<TenantPlataforma> cambiarEstado(
    String tenantId,
    EstadoTenant estado,
    String motivo,
  ) async {
    cambios.add([tenantId, estado, motivo]);
    final t = TenantPlataforma(
      id: tenantId,
      nombre: tenants.first.nombre,
      slug: tenants.first.slug,
      estado: estado,
    );
    tenants[0] = t;
    return t;
  }

  @override
  Future<List<CambioEstadoTenant>> historial(String tenantId) async => const [];
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

MetricasOperativas _metricas({
  int creadas = 0,
  double? promedio,
  double? tasa,
}) => MetricasOperativas(
  solicitudesCreadas: creadas,
  porEstado: creadas == 0 ? const {} : {'FINALIZADA': creadas},
  finalizadas: creadas,
  canceladas: 0,
  tasaCancelacion: tasa,
  cotizacionesEmitidas: creadas,
  cotizacionesAceptadas: creadas,
  tasaAceptacion: creadas == 0 ? null : 1,
  pagosAprobados: 0,
  montoAprobado: 0,
  calificaciones: promedio == null ? 0 : 2,
  calificacionPromedio: promedio,
  quejasRegistradas: 0,
  quejasAbiertas: 0,
  quejasCerradas: 0,
  aliadosConServicios: creadas == 0 ? 0 : 1,
);

void main() {
  // ============================================================== SCRUM-895 · HU-M12-01
  group('895 · el cliente presenta una queja', () {
    Future<Queja?> abrir(WidgetTester tester, _Quejas fuente) async {
      Queja? resultado;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => resultado = await presentarQueja(
                context,
                fuente: fuente,
                solicitudId: 'sol-1',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return resultado;
    }

    testWidgets(
      'C1/C2: sin motivo o con descripción corta no se puede enviar; con ambos queda registrada',
      (tester) async {
        final fuente = _Quejas();
        await abrir(tester, fuente);
        expect(
          tester
              .widget<ManiButton>(find.byKey(const Key('queja-enviar')))
              .onPressed,
          isNull,
        );

        await tester.enterText(
          find.byKey(const Key('queja-descripcion')),
          'corta',
        );
        await tester.tap(find.byKey(const Key('queja-motivo')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cobro indebido').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ManiButton>(find.byKey(const Key('queja-enviar')))
              .onPressed,
          isNull,
        );

        await tester.enterText(
          find.byKey(const Key('queja-descripcion')),
          'Me cobraron dos veces el servicio',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('queja-enviar')));
        await tester.pumpAndSettle();

        expect(fuente.enviados.single, {
          'solicitudId': 'sol-1',
          'motivo': MotivoQueja.cobroIndebido,
          'descripcion': 'Me cobraron dos veces el servicio',
        });
        expect(find.byType(DialogoQueja), findsNothing);
      },
    );

    testWidgets(
      'C2: una segunda queja abierta la rechaza Core y el diálogo lo explica',
      (tester) async {
        final fuente = _Quejas();
        await fuente.registrar(
          'sol-1',
          motivo: MotivoQueja.otro,
          descripcion: 'Primera queja abierta',
        );
        await abrir(tester, fuente);
        await tester.tap(find.byKey(const Key('queja-motivo')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Otro').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('queja-descripcion')),
          'Segunda queja sobre lo mismo',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('queja-enviar')));
        await tester.pumpAndSettle();

        expect(
          find.text('la solicitud ya tiene una queja abierta'),
          findsOneWidget,
        );
        expect(fuente.quejas.length, 1);
      },
    );

    testWidgets(
      'C3: «Mis quejas» muestra solo lo que Core devuelve para la sesión',
      (tester) async {
        final fuente = _Quejas();
        await fuente.registrar(
          'sol-1',
          motivo: MotivoQueja.tratoInadecuado,
          descripcion: 'El aliado fue grosero',
        );
        await tester.pumpWidget(
          _app(
            BlocProvider(
              create: (_) => QuejasCubit(fuente, esAdmin: false)..cargar(),
              child: const QuejasPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mis quejas'), findsOneWidget);
        expect(find.byKey(const Key('queja-q-1')), findsOneWidget);
        expect(
          find.byKey(const Key('queja-EN_REVISION-q-1')),
          findsNothing,
          reason: 'el cliente no cambia estados',
        );
      },
    );
  });

  // ============================================================== SCRUM-896 · HU-M12-02
  group('896 · el administrador gestiona quejas', () {
    Future<_Quejas> montar(WidgetTester tester) async {
      final fuente = _Quejas();
      await fuente.registrar(
        'sol-1',
        motivo: MotivoQueja.incumplimientoDeHorario,
        descripcion: 'Llegó dos horas tarde',
      );
      await tester.pumpWidget(
        _app(
          BlocProvider(
            create: (_) => QuejasCubit(fuente, esAdmin: true)..cargar(),
            child: const QuejasPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fuente;
    }

    testWidgets(
      'C1: pasa a revisión y la resuelve con respuesta; el historial muestra cada transición',
      (tester) async {
        final fuente = await montar(tester);
        expect(find.byKey(const Key('queja-EN_REVISION-q-1')), findsOneWidget);

        await tester.tap(find.byKey(const Key('queja-EN_REVISION-q-1')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('queja-estado-q-1')),
            matching: find.text('En revisión'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('queja-RESUELTA-q-1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('queja-nota')),
          'Se aplicó un descuento',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('queja-confirmar')));
        await tester.pumpAndSettle();

        expect(fuente.quejas.single.estado, EstadoQueja.resuelta);
        expect(find.text('Respuesta: Se aplicó un descuento'), findsOneWidget);
        await tester.tap(find.byKey(const Key('queja-historial-q-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('queja-transicion-0')), findsOneWidget);
        expect(find.byKey(const Key('queja-transicion-2')), findsOneWidget);
        expect(find.textContaining('En revisión → Resuelta'), findsOneWidget);
      },
    );

    testWidgets(
      'C2: una queja cerrada no ofrece transiciones y cerrar sin respuesta no se permite',
      (tester) async {
        final fuente = await montar(tester);
        await tester.tap(find.byKey(const Key('queja-RECHAZADA-q-1')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('queja-nota')), 'no');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ManiButton>(find.byKey(const Key('queja-confirmar')))
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('queja-nota')),
          'No procede: el servicio se cumplió',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('queja-confirmar')));
        await tester.pumpAndSettle();

        expect(fuente.quejas.single.estado, EstadoQueja.rechazada);
        for (final e in EstadoQueja.values) {
          expect(find.byKey(Key('queja-${e.valor}-q-1')), findsNothing);
        }
        // Si otra sesión la cambió mientras tanto, Core responde 409 y la app lo muestra.
        await tester.runAsync(
          () => tester
              .element(find.byType(QuejasPage))
              .read<QuejasCubit>()
              .cambiarEstado(fuente.quejas.single, EstadoQueja.enRevision),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'una queja en estado RECHAZADA no puede pasar a EN_REVISION',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'C3: el filtro por estado lo resuelve Core para el tenant de la sesión',
      (tester) async {
        await montar(tester);
        await tester.tap(find.byKey(const Key('filtro-RESUELTA')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quejas-vacio')), findsOneWidget);
        await tester.tap(find.byKey(const Key('filtro-todas')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('queja-q-1')), findsOneWidget);
      },
    );
  });

  // ============================================================== SCRUM-900 · HU-M12-06
  group('900 · métricas operativas', () {
    Future<_Metricas> montar(WidgetTester tester, MetricasOperativas m) async {
      final fuente = _Metricas(m);
      await tester.pumpWidget(
        _app(
          BlocProvider(
            create: (_) =>
                MetricasCubit(fuente, hoy: DateTime(2026, 10, 29))..consultar(),
            child: const MetricasPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fuente;
    }

    testWidgets(
      'C1: consulta el mes en curso y muestra los agregados que devuelve Core',
      (tester) async {
        final fuente = await montar(
          tester,
          _metricas(creadas: 4, promedio: 4.5, tasa: 0.25),
        );
        expect(fuente.periodos.single, ['2026-10-01', '2026-10-29']);
        expect(
          find.descendant(
            of: find.byKey(const Key('metrica-solicitudes')),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        expect(find.text('4.50 (2)'), findsOneWidget);
        expect(find.text('0 (25.0 %)'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('metrica-estado-FINALIZADA')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const Key('metrica-estado-FINALIZADA')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'C2: un periodo sin datos muestra ceros reales, sin promedio inventado',
      (tester) async {
        await montar(tester, _metricas());
        expect(find.byKey(const Key('metricas-sin-datos')), findsOneWidget);
        expect(find.text('Sin calificaciones'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('metrica-aceptacion')),
            matching: find.text('—'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ============================================================== SCRUM-901 · HU-M12-07
  group('901 · estado de tenants', () {
    testWidgets(
      'C1: suspende un tenant con motivo y la lista muestra el estado nuevo',
      (tester) async {
        final fuente = _Tenants();
        await tester.pumpWidget(
          _app(
            BlocProvider(
              create: (_) => TenantsCubit(fuente)..cargar(),
              child: const TenantsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('tenant-acciones-t-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suspender'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('tenant-motivo')), 'corto');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ManiButton>(find.byKey(const Key('tenant-confirmar')))
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('tenant-motivo')),
          'Mora de dos meses en el plan',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tenant-confirmar')));
        await tester.pumpAndSettle();

        expect(fuente.cambios.single, [
          't-1',
          EstadoTenant.suspendido,
          'Mora de dos meses en el plan',
        ]);
        expect(
          find.descendant(
            of: find.byKey(const Key('tenant-estado-t-1')),
            matching: find.text('Suspendido'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'C2/C3: sin el permiso de plataforma Core responde 403 y no se lista ningún tenant',
      (tester) async {
        await tester.pumpWidget(
          _app(
            BlocProvider(
              create: (_) => TenantsCubit(_Tenants(sinPermiso: true))..cargar(),
              child: const TenantsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tenants-error')), findsOneWidget);
        expect(find.byKey(const Key('tenant-t-1')), findsNothing);
      },
    );

    test(
      'C2/C3: el claim admin_plataforma abre solo /plataforma; ningún rol de tenant la abre',
      () {
        expect(rolDesdeClaim('admin_plataforma'), RolUsuario.adminPlataforma);
        expect(
          rolPuedeAbrir(RolUsuario.adminPlataforma, '/plataforma/tenants'),
          isTrue,
        );
        for (final rol in [
          RolUsuario.adminTenant,
          RolUsuario.cliente,
          RolUsuario.aliado,
          RolUsuario.desconocido,
        ]) {
          expect(
            rolPuedeAbrir(rol, '/plataforma/tenants'),
            isFalse,
            reason: '$rol',
          );
        }
        expect(
          rolPuedeAbrir(RolUsuario.adminPlataforma, '/admin/quejas'),
          isFalse,
        );
        expect(rolPuedeAbrir(RolUsuario.cliente, '/admin/tarifas'), isFalse);
        expect(rolPuedeAbrir(RolUsuario.cliente, '/cliente/quejas'), isTrue);
        expect(
          entradasMenuPara(RolUsuario.adminPlataforma).map((e) => e.ruta),
          contains('/plataforma/tenants'),
        );
        expect(
          entradasMenuPara(RolUsuario.adminTenant).map((e) => e.ruta),
          containsAll([
            '/admin/tarifas',
            '/admin/quejas',
            '/admin/metricas',
            '/admin/reportes/cotizaciones-fuera-de-rango',
          ]),
        );
      },
    );
  });
}
