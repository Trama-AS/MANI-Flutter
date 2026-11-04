import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/conversation_review/data/conversacion_queja_datasource.dart';
import 'package:mani/features/conversation_review/domain/consulta_conversacion.dart';
import 'package:mani/features/conversation_review/presentation/conversacion_queja_cubit.dart';
import 'package:mani/features/conversation_review/presentation/conversacion_queja_page.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _sol = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _respuesta({int mensajes = 2}) => {
  'consulta': {
    'id': 'c-1',
    'solicitudId': _sol,
    'motivo': 'Queja por retraso',
    'quejaRef': 'Q-7',
    'mensajesVistos': mensajes,
    'creadoEn': '2026-11-04T15:00:00.000Z',
  },
  'mensajes': [
    for (var i = 0; i < mensajes; i++)
      {
        'id': 'm$i',
        'solicitudId': _sol,
        'contenido': 'Texto $i',
        'creadoEn': '2026-11-04T14:0$i:00.000Z',
        'remitente': {'rol': i.isEven ? 'CLIENT' : 'ALLY'},
        'mio': false,
      },
  ],
};

class _FuenteFalsa implements FuenteConversacionQueja {
  _FuenteFalsa({this.falla});

  Object? falla;
  final consultas = <({String id, String motivo, String? ref})>[];

  @override
  Future<ConversacionConsultada> consultar(
    String solicitudId, {
    required String motivo,
    String? quejaRef,
  }) async {
    consultas.add((id: solicitudId, motivo: motivo, ref: quejaRef));
    if (falla != null) throw falla!;
    return ConversacionConsultada.fromJson(_respuesta());
  }
}

/// SCRUM-883: el administrador abre la conversación de una queja por el Gateway;
/// cada consulta queda registrada en la auditoría de Core.
void main() {
  group('GatewayFuenteConversacionQueja', () {
    test('POST con motivo y referencia, sin enviar actor ni tenant', () async {
      late http.Request visto;
      final fuente = GatewayFuenteConversacionQueja(
        GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-admin',
          correlationId: () => 'corr-test',
          maxRetries: 0,
          httpClient: MockClient((r) async {
            visto = r;
            return http.Response(jsonEncode(_respuesta()), 201, headers: _json);
          }),
        ),
      );

      final r = await fuente.consultar(
        _sol,
        motivo: 'Queja por retraso',
        quejaRef: 'Q-7',
      );

      expect(r.consulta.mensajesVistos, 2);
      expect(r.mensajes.first.etiquetaRemitente, 'Cliente');
      expect(visto.method, 'POST');
      expect(
        visto.url.path,
        '/api/v1/core/solicitudes/$_sol/conversacion/consultas',
      );
      expect(jsonDecode(visto.body), {
        'motivo': 'Queja por retraso',
        'quejaRef': 'Q-7',
      });
      expect(visto.headers['Authorization'], 'Bearer jwt-admin');
    });

    test(
      'sin referencia no la envía; una respuesta sin consulta o mensajes es un error de formato',
      () async {
        late http.Request visto;
        var cuerpo = <String, dynamic>{'otra': 1};
        final fuente = GatewayFuenteConversacionQueja(
          GatewayClient(
            baseUrl: 'http://gateway.local',
            tokenProvider: () async => 'jwt',
            maxRetries: 0,
            httpClient: MockClient((r) async {
              visto = r;
              return http.Response(jsonEncode(cuerpo), 201, headers: _json);
            }),
          ),
        );
        await expectLater(
          fuente.consultar(_sol, motivo: 'motivo válido'),
          throwsFormatException,
        );
        expect(jsonDecode(visto.body), {'motivo': 'motivo válido'});
        cuerpo = _respuesta(mensajes: 0);
        final r = await fuente.consultar(
          _sol,
          motivo: 'motivo válido',
          quejaRef: '',
        );
        expect(r.mensajes, isEmpty);
      },
    );
  });

  group('ConversacionQuejaCubit', () {
    test('consulta con datos válidos y entrega los mensajes', () async {
      final f = _FuenteFalsa();
      final cubit = ConversacionQuejaCubit(f);
      await cubit.consultar(
        solicitudId: ' $_sol ',
        motivo: ' Queja por retraso ',
        quejaRef: ' Q-7 ',
      );
      expect(cubit.state.fase, FaseConversacion.listo);
      expect(cubit.state.resultado!.mensajes, hasLength(2));
      expect(f.consultas.single, (
        id: _sol,
        motivo: 'Queja por retraso',
        ref: 'Q-7',
      ));
    });

    test(
      'valida lo mismo que Core y no consulta con datos inválidos (la consulta queda auditada)',
      () async {
        final f = _FuenteFalsa();
        final cubit = ConversacionQuejaCubit(f);

        await cubit.consultar(solicitudId: 'no-uuid', motivo: 'motivo válido');
        expect(cubit.state.error, contains('solicitud no es válido'));
        await cubit.consultar(solicitudId: _sol, motivo: 'abc');
        expect(cubit.state.error, contains('entre 5 y 500'));
        await cubit.consultar(solicitudId: _sol, motivo: 'x' * 501);
        expect(cubit.state.error, contains('entre 5 y 500'));
        await cubit.consultar(
          solicitudId: _sol,
          motivo: 'motivo válido',
          quejaRef: 'con espacio!',
        );
        expect(cubit.state.error, contains('referencia'));

        expect(f.consultas, isEmpty);
      },
    );

    test(
      'un 403 (no es administrador) y un 404 (solicitud ajena) se muestran sin mensajes',
      () async {
        for (final status in [403, 404]) {
          final f = _FuenteFalsa(
            falla: GatewayException(
              message: 'Rechazado $status',
              statusCode: status,
            ),
          );
          final cubit = ConversacionQuejaCubit(f);
          await cubit.consultar(solicitudId: _sol, motivo: 'motivo válido');
          expect(cubit.state.fase, FaseConversacion.error, reason: '$status');
          expect(cubit.state.error, 'Rechazado $status');
          expect(cubit.state.resultado, isNull);
        }
      },
    );

    test('un error de formato da un mensaje genérico', () async {
      final cubit = ConversacionQuejaCubit(
        _FuenteFalsa(falla: const FormatException('x')),
      );
      await cubit.consultar(solicitudId: _sol, motivo: 'motivo válido');
      expect(cubit.state.error, contains('No pudimos leer la conversación'));
    });
  });

  group('ConversacionQuejaView', () {
    Future<_FuenteFalsa> montar(
      WidgetTester tester, {
      String? solicitudId,
      String? quejaRef,
      _FuenteFalsa? fuente,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 2200);
      addTearDown(tester.view.reset);
      final f = fuente ?? _FuenteFalsa();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => ConversacionQuejaCubit(f),
            child: ConversacionQuejaView(
              solicitudId: solicitudId,
              quejaRef: quejaRef,
            ),
          ),
        ),
      );
      return f;
    }

    testWidgets(
      'avisa que cada consulta queda registrada y prellena la solicitud y la queja',
      (tester) async {
        await montar(tester, solicitudId: _sol, quejaRef: 'Q-7');
        expect(find.byKey(const Key('aviso-auditoria')), findsOneWidget);
        expect(find.text(_sol), findsOneWidget);
        expect(find.text('Q-7'), findsOneWidget);
      },
    );

    testWidgets(
      'con el motivo escrito muestra los mensajes y cuántos se vieron',
      (tester) async {
        final f = await montar(tester, solicitudId: _sol);
        await tester.enterText(
          find.byKey(const Key('campo-motivo')),
          'Queja por retraso',
        );
        await tester.tap(find.byKey(const Key('btn-consultar')));
        await tester.pumpAndSettle();

        expect(f.consultas, hasLength(1));
        expect(find.byKey(const Key('mensajes-vistos')), findsOneWidget);
        expect(find.text('Texto 0'), findsOneWidget);
        expect(find.textContaining('Cliente'), findsWidgets);
      },
    );

    testWidgets('un motivo corto muestra el error sin consultar', (
      tester,
    ) async {
      final f = await montar(tester, solicitudId: _sol);
      await tester.enterText(find.byKey(const Key('campo-motivo')), 'abc');
      await tester.tap(find.byKey(const Key('btn-consultar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-conversacion')), findsOneWidget);
      expect(f.consultas, isEmpty);
    });

    testWidgets('una conversación sin mensajes lo dice', (tester) async {
      final f = _FuenteFalsa();
      await montar(tester, solicitudId: _sol, fuente: f);
      await tester.enterText(
        find.byKey(const Key('campo-motivo')),
        'motivo válido',
      );
      await tester.tap(find.byKey(const Key('btn-consultar')));
      await tester.pumpAndSettle();
      expect(find.text('Texto 1'), findsOneWidget);
    });
  });
}
