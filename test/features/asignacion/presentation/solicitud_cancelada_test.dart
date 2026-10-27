import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/presentation/widgets/solicitud_card.dart';

import '../fakes.dart';

void main() {
  test(
    'US-04.5.1 (SCRUM-877): CANCELADA se reconoce y no queda disponible',
    () {
      expect(EstadoSolicitud.desde('cancelada'), EstadoSolicitud.cancelada);
      final s = solicitud('x', estado: EstadoSolicitud.cancelada, esMia: true);
      expect(s.cancelada, isTrue);
      expect(s.estaDisponible, isFalse);
    },
  );

  testWidgets(
    'US-04.5.1 (SCRUM-877): el aliado ve su trabajo cancelado por el cliente y sin «Cotización»',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SolicitudCard(
                solicitud: solicitud(
                  'x',
                  estado: EstadoSolicitud.cancelada,
                  esMia: true,
                  direccion: 'Calle 1',
                ),
                onCotizar: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('etiqueta-cancelada')), findsOneWidget);
      expect(find.byKey(const ValueKey('aviso-cancelada')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-cotizar-x')), findsNothing);
    },
  );

  testWidgets('una asignada sin cancelar conserva «Cotización»', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SolicitudCard(
              solicitud: solicitud(
                'x',
                estado: EstadoSolicitud.asignada,
                esMia: true,
              ),
              onCotizar: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('btn-cotizar-x')), findsOneWidget);
    expect(find.byKey(const ValueKey('etiqueta-cancelada')), findsNothing);
  });
}
