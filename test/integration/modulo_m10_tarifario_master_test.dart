// Prueba maestra frontend de M-10 (SCRUM-885, 886, 887). Cada criterio C1-C3 se recorre en la pantalla real con
// fuentes en memoria que responden como Core (mismos códigos de error). El aislamiento por tenant y las reglas
// definitivas se prueban contra PostgreSQL en MANI-Node (tests/integration/pg/moduloM10Master.pg.test.js); aquí se
// prueba qué ve y qué envía la app.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/categories/domain/entities/categoria_servicio.dart';
import 'package:mani/features/services/categories/domain/repositories/categorias_repository.dart';
import 'package:mani/features/tariffs/data/tarifas_datasource.dart';
import 'package:mani/features/tariffs/domain/evaluacion_tarifa.dart';
import 'package:mani/features/tariffs/domain/tarifa.dart';
import 'package:mani/features/tariffs/presentation/alerta_tarifa_cotizacion.dart';
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
  Map<String, dynamic>? evaluacionJson;
  Object? errorEvaluacion;
  int evaluaciones = 0;

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
  Future<EvaluacionTarifa> evaluacion(String cotizacionId) async {
    evaluaciones++;
    if (errorEvaluacion != null) throw errorEvaluacion!;
    return EvaluacionTarifa.fromJson({
      'cotizacionId': cotizacionId,
      ...?evaluacionJson,
    });
  }

  @override
  Future<ReporteFueraDeRango> reporteFueraDeRango(
    String desde,
    String hasta,
  ) async {
    if (errorReporte != null) throw errorReporte!;
    return reporte!;
  }
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

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

  // ============================================================== SCRUM-866 · HU-M06-02
  group('866 · alerta de tarifa bidireccional', () {
    const tarifa = {
      'valorMin': 80000,
      'valorTipico': 120000,
      'valorMax': 180000,
      'moneda': 'COP',
    };

    Future<void> montar(
      WidgetTester tester,
      _Tarifas fuente, {
      bool esAliado = false,
    }) async {
      await tester.pumpWidget(
        _app(
          AlertaTarifaCotizacion(
            fuente: fuente,
            cotizacionId: 'cot-1',
            esAliado: esAliado,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'C1: por encima, el cliente y el aliado ven la alerta con la referencia y el motivo',
      (tester) async {
        for (final esAliado in [false, true]) {
          final fuente = _Tarifas()
            ..evaluacionJson = {
              'resultado': 'POR_ENCIMA',
              'total': 270000,
              'desviacionPorcentaje': 50,
              'tarifa': tarifa,
            };
          await montar(tester, fuente, esAliado: esAliado);
          expect(find.byKey(const Key('alerta-tarifa-encima')), findsOneWidget);
          expect(
            find.text('Cotización por encima del rango de referencia'),
            findsOneWidget,
          );
          expect(
            find.text(
              'El total (\$ 270.000,00) supera el máximo de referencia '
              '(\$ 180.000,00) en 50 %.',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('\$ 80.000,00 – \$ 180.000,00 COP'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              esAliado
                  ? 'El cliente también ve este aviso'
                  : 'El aliado también ve este aviso',
            ),
            findsOneWidget,
            reason: 'bidireccional: cada parte sabe que la otra lo ve',
          );
          expect(
            find.text('La cotización no cambia por este aviso.'),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('C1: por debajo muestra el mínimo cruzado y la desviación', (
      tester,
    ) async {
      final fuente = _Tarifas()
        ..evaluacionJson = {
          'resultado': 'POR_DEBAJO',
          'total': 60000,
          'desviacionPorcentaje': 25,
          'tarifa': tarifa,
        };
      await montar(tester, fuente);
      expect(find.byKey(const Key('alerta-tarifa-debajo')), findsOneWidget);
      expect(
        find.text(
          'El total (\$ 60.000,00) está por debajo del mínimo de referencia '
          '(\$ 80.000,00) en 25 %.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('C1: dentro de banda no hay alerta falsa', (tester) async {
      final fuente = _Tarifas()
        ..evaluacionJson = {
          'resultado': 'DENTRO_DE_RANGO',
          'total': 120000,
          'desviacionPorcentaje': 0,
          'tarifa': tarifa,
        };
      await montar(tester, fuente, esAliado: true);
      expect(find.byKey(const Key('alerta-tarifa-en-rango')), findsOneWidget);
      expect(find.byKey(const Key('alerta-tarifa-encima')), findsNothing);
      expect(find.byKey(const Key('alerta-tarifa-debajo')), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('C2: sin tarifa lo dice y no muestra ningún valor ni alerta', (
      tester,
    ) async {
      final fuente = _Tarifas()
        ..evaluacionJson = {
          'resultado': 'SIN_TARIFA',
          'total': 999999,
          'desviacionPorcentaje': null,
          'tarifa': null,
        };
      await montar(tester, fuente);
      expect(find.byKey(const Key('alerta-tarifa-sin-tarifa')), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
    });

    testWidgets(
      'C2: si Rules no responde (503) muestra el error de Core, sin resultado inventado, y permite reintentar',
      (tester) async {
        final fuente = _Tarifas()
          ..errorEvaluacion = _error(
            503,
            'RULES_SERVICE_UNAVAILABLE',
            'El servicio de reglas no está disponible',
          );
        await montar(tester, fuente);
        expect(find.byKey(const Key('alerta-tarifa-error')), findsOneWidget);
        expect(find.textContaining('\$'), findsNothing);
        expect(find.byKey(const Key('alerta-tarifa-en-rango')), findsNothing);

        fuente
          ..errorEvaluacion = null
          ..evaluacionJson = {
            'resultado': 'POR_ENCIMA',
            'total': 270000,
            'desviacionPorcentaje': 50,
            'tarifa': tarifa,
          };
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('alerta-tarifa-encima')), findsOneWidget);
        expect(fuente.evaluaciones, 2);
      },
    );

    testWidgets('C3: una cotización ajena (404 de Core) no expone datos', (
      tester,
    ) async {
      final fuente = _Tarifas()
        ..errorEvaluacion = _error(
          404,
          'MANI-TAR-404Q',
          'cotización no encontrada',
        );
      await montar(tester, fuente);
      expect(find.byKey(const Key('alerta-tarifa-error')), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
    });

    test('un resultado desconocido o sin tarifa no se adivina', () {
      expect(
        () => EvaluacionTarifa.fromJson({
          'cotizacionId': 'c',
          'resultado': 'QUIZAS',
          'total': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => EvaluacionTarifa.fromJson({
          'cotizacionId': 'c',
          'resultado': 'POR_ENCIMA',
          'total': 1,
          'tarifa': null,
        }),
        throwsFormatException,
      );
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
}

class _FuenteTarifasQueFalla extends _Tarifas {
  _FuenteTarifasQueFalla(this.error);

  final Object error;

  @override
  Future<ReferenciaTarifa> referencia(String solicitudId) async => throw error;
}
