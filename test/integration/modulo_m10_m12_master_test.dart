// Prueba maestra frontend de M-10 (SCRUM-885, 886, 887) y M-12 (SCRUM-895, 896, 900, 901). Cada criterio C1-C3 se
// recorre en la pantalla real con fuentes en memoria que responden como Core (mismos códigos de error). El aislamiento
// por tenant y las reglas definitivas se prueban contra PostgreSQL en MANI-Node
// (tests/integration/pg/moduloM10M12Master.pg.test.js); aquí se prueba qué ve y qué envía la app.
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
import 'package:mani/features/services/categories/domain/entities/categoria_servicio.dart';
import 'package:mani/features/services/categories/domain/repositories/categorias_repository.dart';
import 'package:mani/features/tariffs/data/tarifas_datasource.dart';
import 'package:mani/features/tariffs/domain/tarifa.dart';
import 'package:mani/features/tariffs/presentation/referencia_tarifa_seccion.dart';
import 'package:mani/features/tariffs/presentation/reporte_fuera_rango_page.dart';
import 'package:mani/features/tariffs/presentation/tarifario_cubit.dart';
import 'package:mani/features/tariffs/presentation/tarifario_page.dart';

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
class _Categorias implements CategoriasRepository {
  @override
  Future<List<CategoriaServicio>> listar() async => const [
    CategoriaServicio(id: 'cat-1', nombre: 'Plomería', activa: true),
    CategoriaServicio(id: 'cat-2', nombre: 'Pintura', activa: true),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Tarifario como Core: versiones inmutables y 409 si la vigencia se cruza.
class _Tarifas implements FuenteTarifas {
  final versiones = <Tarifa>[];
  int llamadasCrear = 0;
  ReferenciaTarifa referenciaFija = const ReferenciaTarifa();
  Object? errorReporte;
  ReporteFueraDeRango? reporte;

  Tarifa _nueva(String categoriaId, DatosTarifa d, int version) => Tarifa(
    id: 'tar-$categoriaId-$version',
    categoriaId: categoriaId,
    categoriaNombre: categoriaId == 'cat-1' ? 'Plomería' : 'Pintura',
    valorMin: d.valorMin,
    valorTipico: d.valorTipico,
    valorMax: d.valorMax,
    moneda: d.moneda,
    vigenciaDesde: d.vigenciaDesde ?? '2026-10-29',
    vigenciaHasta: d.vigenciaHasta,
    condiciones: d.condiciones,
    version: version,
  );

  @override
  Future<List<Tarifa>> activas() async =>
      versiones.where((t) => t.activa).toList();

  @override
  Future<Tarifa> crear(String categoriaId, DatosTarifa datos) async {
    llamadasCrear++;
    if (versiones.any((t) => t.categoriaId == categoriaId && t.activa)) {
      throw _error(
        409,
        'MANI-TAR-409V',
        'la vigencia se cruza con otra tarifa activa de la categoría',
      );
    }
    final t = _nueva(
      categoriaId,
      datos,
      versiones.where((v) => v.categoriaId == categoriaId).length + 1,
    );
    versiones.add(t);
    return t;
  }

  @override
  Future<Tarifa> editar(String tarifaId, DatosTarifa datos) async {
    final i = versiones.indexWhere((t) => t.id == tarifaId);
    final actual = versiones[i];
    versiones[i] = Tarifa(
      id: actual.id,
      categoriaId: actual.categoriaId,
      categoriaNombre: actual.categoriaNombre,
      valorMin: actual.valorMin,
      valorTipico: actual.valorTipico,
      valorMax: actual.valorMax,
      moneda: actual.moneda,
      vigenciaDesde: actual.vigenciaDesde,
      version: actual.version,
      estado: 'REEMPLAZADA',
    );
    final t = _nueva(actual.categoriaId, datos, actual.version + 1);
    versiones.add(t);
    return t;
  }

  @override
  Future<List<Tarifa>> historial(String categoriaId) async => versiones
      .where((t) => t.categoriaId == categoriaId)
      .toList()
      .reversed
      .toList();

  @override
  Future<ReferenciaTarifa> referencia(String solicitudId) async =>
      referenciaFija;

  @override
  Future<ReporteFueraDeRango> reporteFueraDeRango(
    String desde,
    String hasta,
  ) async {
    if (errorReporte != null) throw errorReporte!;
    return reporte!;
  }
}

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
  // ============================================================== SCRUM-885 · HU-M10-01
  group('885 · tarifario', () {
    Future<_Tarifas> montar(WidgetTester tester) async {
      final fuente = _Tarifas();
      await tester.pumpWidget(
        _app(
          BlocProvider(
            create: (_) => TarifarioCubit(fuente, _Categorias())..cargar(),
            child: const TarifarioPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fuente;
    }

    Future<void> llenar(
      WidgetTester tester, {
      required String min,
      required String tipico,
      required String max,
    }) async {
      await tester.enterText(find.byKey(const Key('tarifa-min')), min);
      await tester.enterText(find.byKey(const Key('tarifa-tipico')), tipico);
      await tester.enterText(find.byKey(const Key('tarifa-max')), max);
      await tester.enterText(
        find.byKey(const Key('tarifa-desde')),
        '2026-01-01',
      );
      await tester.tap(find.byKey(const Key('tarifa-guardar')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'C1: el administrador carga la tarifa y la ve en su categoría tras recargar de Core',
      (tester) async {
        final fuente = await montar(tester);
        expect(find.text('Sin tarifa de referencia.'), findsNWidgets(2));

        await tester.tap(find.byKey(const Key('cargar-tarifa-cat-1')));
        await tester.pumpAndSettle();
        await llenar(tester, min: '80000', tipico: '120000', max: '180000');

        expect(fuente.versiones.single.valorMax, 180000);
        expect(
          find.byKey(const Key('tarifa-rango-tar-cat-1-1')),
          findsOneWidget,
        );
        expect(find.text('Tarifa guardada: versión 1.'), findsOneWidget);
      },
    );

    testWidgets(
      'C1: editar crea la versión 2 y el historial conserva la 1 como reemplazada',
      (tester) async {
        final fuente = await montar(tester);
        await fuente.crear(
          'cat-1',
          const DatosTarifa(
            valorMin: 80000,
            valorTipico: 120000,
            valorMax: 180000,
          ),
        );
        await tester.tap(find.byKey(const Key('historial-tarifa-cat-2')));
        await tester.pumpAndSettle();
        expect(find.text('Sin versiones registradas.'), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, 300));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('editar-tarifa-tar-cat-1-1')));
        await tester.pumpAndSettle();
        expect(find.textContaining('(v2)'), findsOneWidget);
        await llenar(tester, min: '90000', tipico: '130000', max: '200000');

        expect(fuente.versiones.map((t) => [t.version, t.estado]), [
          [1, 'REEMPLAZADA'],
          [2, 'ACTIVA'],
        ]);
        await tester.tap(find.byKey(const Key('historial-tarifa-cat-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('historial-version-2')), findsOneWidget);
        expect(find.byKey(const Key('historial-version-1')), findsOneWidget);
        expect(find.textContaining('Reemplazada'), findsOneWidget);
      },
    );

    testWidgets(
      'C2: valores invertidos o negativos no se envían; una vigencia cruzada la rechaza Core sin tocar la vigente',
      (tester) async {
        final fuente = await montar(tester);
        await tester.tap(find.byKey(const Key('cargar-tarifa-cat-1')));
        await tester.pumpAndSettle();
        await llenar(tester, min: '200000', tipico: '120000', max: '180000');
        expect(find.byKey(const Key('tarifa-error')), findsOneWidget);
        expect(
          find.text('Debe cumplirse mínimo ≤ típico ≤ máximo.'),
          findsOneWidget,
        );
        await llenar(tester, min: '-5', tipico: '1', max: '2');
        // El campo solo admite dígitos: «-5» queda como «5», que tampoco cumple el rango.
        expect(find.byKey(const Key('tarifa-error')), findsOneWidget);
        expect(fuente.llamadasCrear, 0);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        await fuente.crear(
          'cat-1',
          const DatosTarifa(valorMin: 1, valorTipico: 2, valorMax: 3),
        );
        await tester.tap(find.byKey(const Key('cargar-tarifa-cat-1')));
        await tester.pumpAndSettle();
        await llenar(tester, min: '80000', tipico: '120000', max: '180000');

        expect(
          find.text(
            'la vigencia se cruza con otra tarifa activa de la categoría',
          ),
          findsOneWidget,
        );
        expect(
          fuente.versiones.length,
          1,
          reason: 'la tarifa vigente sigue intacta',
        );
      },
    );
  });

  // ============================================================== SCRUM-886 · HU-M10-02
  group('886 · referencia al cotizar', () {
    testWidgets('C1: muestra el rango vigente de la categoría', (tester) async {
      final fuente = _Tarifas()
        ..referenciaFija = ReferenciaTarifa(
          tarifa: Tarifa.fromJson({
            'id': 't',
            'categoriaId': 'cat-1',
            'categoriaNombre': 'Plomería',
            'valorMin': 80000,
            'valorTipico': 120000,
            'valorMax': 180000,
            'moneda': 'COP',
            'vigenciaDesde': '2026-01-01',
            'condiciones': 'Incluye visita',
            'version': 3,
          }),
        );
      await tester.pumpWidget(
        _app(ReferenciaTarifaSeccion(fuente: fuente, solicitudId: 'sol-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('\$ 80.000,00 – \$ 180.000,00 COP'), findsOneWidget);
      expect(find.text('Valor típico: \$ 120.000,00'), findsOneWidget);
      expect(find.text('Condiciones: Incluye visita'), findsOneWidget);
    });

    testWidgets(
      'C2: sin tarifa vigente dice «no disponible» y no muestra ningún valor',
      (tester) async {
        await tester.pumpWidget(
          _app(
            ReferenciaTarifaSeccion(fuente: _Tarifas(), solicitudId: 'sol-1'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('referencia-no-disponible')),
          findsOneWidget,
        );
        expect(find.textContaining('\$'), findsNothing);
      },
    );

    testWidgets('C3: una solicitud ajena (404 de Core) no expone tarifa', (
      tester,
    ) async {
      final fuente = _FuenteTarifasQueFalla(
        _error(404, 'MANI-TAR-404S', 'solicitud no encontrada'),
      );
      await tester.pumpWidget(
        _app(ReferenciaTarifaSeccion(fuente: fuente, solicitudId: 'ajena')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referencia-error')), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
    });
  });

  // ============================================================== SCRUM-887 · HU-M10-03
  group('887 · reporte fuera de rango', () {
    Future<void> montar(WidgetTester tester, _Tarifas fuente) async {
      await tester.pumpWidget(
        _app(
          BlocProvider(
            create: (_) =>
                ReporteFueraDeRangoCubit(fuente, hoy: DateTime(2026, 10, 29))
                  ..consultar(),
            child: const ReporteFueraDeRangoPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'C1: lista las cotizaciones que Rules evaluó fuera de rango con su desviación',
      (tester) async {
        final fuente = _Tarifas()
          ..reporte = ReporteFueraDeRango.fromJson({
            'reglasVersion': 'rates-v1',
            'totales': {
              'cotizaciones': 3,
              'evaluadas': 2,
              'sinTarifa': 1,
              'fueraDeRango': 1,
            },
            'cotizaciones': [
              {
                'id': 'cot-1',
                'solicitudId': 'sol-1',
                'total': 250000,
                'categoria': {'nombre': 'Plomería'},
                'aliado': {'nombre': 'Ana Aliada'},
                'tarifa': {
                  'version': 1,
                  'valorMin': 80000,
                  'valorTipico': 120000,
                  'valorMax': 180000,
                },
                'resultado': 'POR_ENCIMA',
                'desviacionPorcentaje': 38.89,
              },
            ],
          });
        await montar(tester, fuente);
        expect(
          find.text('2026-09-30 a 2026-10-29'),
          findsOneWidget,
          reason: 'por omisión, los últimos 30 días',
        );
        expect(
          find.text(
            '3 cotizaciones · 2 evaluadas · 1 sin tarifa · 1 fuera de rango',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('por encima 38.89 %'), findsOneWidget);
        expect(find.textContaining('Aliado: Ana Aliada'), findsOneWidget);
      },
    );

    testWidgets(
      'C2: sin datos es un vacío controlado; si Rules no responde se dice, sin valores',
      (tester) async {
        final vacio = _Tarifas()
          ..reporte = const ReporteFueraDeRango(
            cotizaciones: [],
            evaluadas: 0,
            sinTarifa: 0,
            totalCotizaciones: 0,
          );
        await montar(tester, vacio);
        expect(find.byKey(const Key('reporte-vacio')), findsOneWidget);

        final caido = _Tarifas()
          ..errorReporte = const GatewayException(
            message: 'x',
            statusCode: 503,
            cuerpo: {
              'error': 'El servicio de reglas no está disponible',
              'code': 'RULES_SERVICE_UNAVAILABLE',
            },
          );
        // Se desmonta la pantalla para que el Cubit nuevo consulte otra vez.
        await tester.pumpWidget(const SizedBox());
        await montar(tester, caido);
        expect(
          find.textContaining('motor de reglas no está disponible'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('reporte-totales')), findsNothing);
      },
    );

    testWidgets('C3: un rol sin permiso ve el 403 de Core y ningún dato', (
      tester,
    ) async {
      final fuente = _Tarifas()
        ..errorReporte = const GatewayException(
          message: 'No tienes permiso para realizar esta acción.',
          statusCode: 403,
        );
      await montar(tester, fuente);
      expect(
        find.text('No tienes permiso para realizar esta acción.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reporte-totales')), findsNothing);
    });
  });

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

class _FuenteTarifasQueFalla extends _Tarifas {
  _FuenteTarifasQueFalla(this.error);

  final Object error;

  @override
  Future<ReferenciaTarifa> referencia(String solicitudId) async => throw error;
}
