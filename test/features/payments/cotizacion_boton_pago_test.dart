import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/services/quotes/data/cotizaciones_datasource.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_cubit.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_page.dart';

Cotizacion _cot(String estado) => Cotizacion.fromJson({
  'id': 'cot-1',
  'solicitudId': 'sol-1',
  'version': 1,
  'estado': estado,
  'valorManoObra': 120000,
  'valorMateriales': 35500.5,
  'total': 155500.5,
});

class _Fuente implements FuenteCotizaciones {
  _Fuente(this.lista);

  final List<Cotizacion> lista;

  @override
  Future<List<Cotizacion>> listar(String solicitudId) async => lista;

  @override
  Future<Cotizacion> emitir(
    String solicitudId, {
    required String valorManoObra,
    required String valorMateriales,
  }) => throw UnimplementedError();

  @override
  Future<Cotizacion> responder(
    String cotizacionId,
    DecisionCotizacion decision, {
    String? texto,
  }) => throw UnimplementedError();
}

/// SCRUM-1432: el cliente llega al pago desde su cotización aceptada.
void main() {
  Future<List<(String, double)>> montar(
    WidgetTester tester, {
    required String estado,
    bool esAliado = false,
    bool conCallback = true,
  }) async {
    final pagos = <(String, double)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) =>
                CotizacionCubit(_Fuente([_cot(estado)]), 'sol-1')..cargar(),
            child: CotizacionPage(
              esAliado: esAliado,
              alPagar: conCallback
                  ? (id, total) => pagos.add((id, total))
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pagos;
  }

  testWidgets(
    'el cliente con la cotización aceptada ve «Pagar (sandbox)» y abre el pago con su id y total',
    (tester) async {
      final pagos = await montar(tester, estado: 'ACEPTADA');

      expect(find.byKey(const Key('btn-pagar-cotizacion')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn-pagar-cotizacion')));

      expect(pagos, [('cot-1', 155500.5)]);
    },
  );

  testWidgets('una cotización pendiente, rechazada o con ajuste no se paga', (
    tester,
  ) async {
    for (final estado in ['PENDIENTE', 'RECHAZADA', 'AJUSTE_SOLICITADO']) {
      await montar(tester, estado: estado);
      expect(
        find.byKey(const Key('btn-pagar-cotizacion')),
        findsNothing,
        reason: estado,
      );
    }
  });

  testWidgets('el aliado nunca ve el botón de pago', (tester) async {
    await montar(tester, estado: 'ACEPTADA', esAliado: true);
    expect(find.byKey(const Key('btn-pagar-cotizacion')), findsNothing);
  });

  testWidgets('sin callback de pago no se ofrece el botón', (tester) async {
    await montar(tester, estado: 'ACEPTADA', conCallback: false);
    expect(find.byKey(const Key('btn-pagar-cotizacion')), findsNothing);
    expect(
      find.byKey(const Key('estado-cotizacion-cliente')),
      findsOneWidget,
      reason: 'el resto de la pantalla sigue igual',
    );
  });
}
