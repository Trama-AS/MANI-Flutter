import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/presentation/widgets/solicitud_card.dart';
import 'package:mani/features/services/tracking/data/seguimiento_datasource.dart';
import 'package:mani/features/services/tracking/domain/solicitud_seguimiento.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_cubit.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_page.dart';

import '../../asignacion/fakes.dart' as asignacion;

class _FuenteFija implements FuenteSeguimiento {
  _FuenteFija(this.lista);

  final List<SolicitudSeguimiento> lista;

  @override
  Future<List<SolicitudSeguimiento>> listar() async => lista;

  @override
  Future<SolicitudSeguimiento> cancelar(String solicitudId, {String? motivo}) =>
      throw UnimplementedError();
}

SolicitudSeguimiento _seguimiento(String id, String estado) =>
    SolicitudSeguimiento.fromJson({
      'id': id,
      'estado': estado,
      'categoria': 'Plomería',
      'zonaDeclarada': {'nombre': 'Chapinero', 'zonaPadre': 'Bogotá'},
      'actualizadaEn': '2026-10-27T01:00:00Z',
    });

void main() {
  test(
    'los estados de la cotización tienen texto propio en el seguimiento',
    () {
      expect(
        _seguimiento('a', 'COTIZANDO').etiquetaEstado,
        'Cotización en curso',
      );
      expect(
        _seguimiento('a', 'ACEPTADA').etiquetaEstado,
        'Cotización aceptada',
      );
      expect(
        _seguimiento('a', 'RECHAZADA').etiquetaEstado,
        'Cotización rechazada',
      );
      expect(_seguimiento('a', 'ASIGNADA').tieneCotizacion, isFalse);
      expect(_seguimiento('a', 'COTIZANDO').tieneCotizacion, isTrue);
    },
  );

  testWidgets('SCRUM-867: «Ver cotización» aparece cuando el aliado ya '
      'cotizó y abre la solicitud correcta', (tester) async {
    final abiertas = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => MisSolicitudesCubit(
              _FuenteFija([
                _seguimiento('sol-asignada', 'ASIGNADA'),
                _seguimiento('sol-cotizando', 'COTIZANDO'),
              ]),
            )..cargar(),
            child: MisSolicitudesPage(onVerCotizacion: abiertas.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ver-cotizacion-sol-asignada')), findsNothing);
    await tester.tap(find.byKey(const Key('ver-cotizacion-sol-cotizando')));
    expect(abiertas, ['sol-cotizando']);
  });

  testWidgets('SCRUM-865: el aliado ve «Cotización» solo en sus solicitudes '
      'asignadas', (tester) async {
    var abiertas = 0;
    Future<void> montar({required bool esMia}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SolicitudCard(
              solicitud: asignacion.solicitud('s1', esMia: esMia),
              onCotizar: () => abiertas++,
            ),
          ),
        ),
      ),
    );

    await montar(esMia: false);
    expect(find.byKey(const ValueKey('btn-cotizar-s1')), findsNothing);

    await montar(esMia: true);
    await tester.ensureVisible(find.byKey(const ValueKey('btn-cotizar-s1')));
    await tester.tap(find.byKey(const ValueKey('btn-cotizar-s1')));
    expect(abiertas, 1);
  });
}
