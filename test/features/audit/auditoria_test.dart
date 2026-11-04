import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/audit/data/auditoria_datasource.dart';
import 'package:mani/features/audit/domain/evento_transaccion.dart';
import 'package:mani/features/audit/presentation/auditoria_cubit.dart';
import 'package:mani/features/audit/presentation/auditoria_page.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _pagoId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _evento(
  String id, {
  String rol = 'CLIENT',
  Object? monto = 150000.5,
}) => {
  'id': id,
  'pagoId': _pagoId,
  'tipo': 'PAGO_REGISTRADO',
  'estado': 'APROBADO',
  'monto': monto,
  'moneda': 'COP',
  'actor': {'id': 'u-1', 'rol': rol},
  'correlationId': 'corr-1',
  'creadoEn': '2026-11-04T15:00:00.000Z',
};

class _FuenteFalsa implements FuenteAuditoria {
  _FuenteFalsa({this.paginas = const [], this.falla});

  List<List<EventoTransaccion>> paginas;
  Object? falla;
  final pedidos = <({String? despuesDe, String? pagoId, int limite})>[];

  @override
  Future<List<EventoTransaccion>> listar({
    String? despuesDe,
    String? pagoId,
    int limite = 50,
  }) async {
    pedidos.add((despuesDe: despuesDe, pagoId: pagoId, limite: limite));
    if (falla != null) throw falla!;
    return paginas.isEmpty ? [] : paginas.removeAt(0);
  }
}

EventoTransaccion _e(String id) => EventoTransaccion.fromJson(_evento(id));

/// SCRUM-889: la auditoría de transacciones sale por el Gateway a Core y solo la
/// ve el administrador del tenant.
void main() {
  group('EventoTransaccion', () {
    test('mapea el evento con su actor y etiquetas legibles', () {
      final e = _e('e1');
      expect(e.etiquetaTipo, 'Pago registrado');
      expect(e.etiquetaActor, 'Cliente');
      expect(e.monto, 150000.5);
      expect(e.correlationId, 'corr-1');
      expect(e.creadoEn, isNotNull);
    });

    test(
      'roles y tipos desconocidos se muestran tal cual; el monto puede venir como texto',
      () {
        final e = EventoTransaccion.fromJson({
          'id': 'x',
          'tipo': 'OTRO',
          'actor': {'id': 'u', 'rol': 'ALLY'},
          'monto': '10.5',
        });
        expect(e.etiquetaTipo, 'OTRO');
        expect(e.etiquetaActor, 'Aliado');
        expect(e.monto, 10.5);
        expect(
          EventoTransaccion.fromJson(_evento('a', rol: 'ADMIN')).etiquetaActor,
          'Administrador',
        );
        expect(
          EventoTransaccion.fromJson(_evento('a', rol: 'RARO')).etiquetaActor,
          'RARO',
        );
        expect(EventoTransaccion.fromJson({'id': 'y', 'monto': null}).monto, 0);
      },
    );
  });

  group('GatewayFuenteAuditoria', () {
    test('GET con límite, cursor y filtro, sin enviar tenant', () async {
      late http.Request visto;
      final fuente = GatewayFuenteAuditoria(
        GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-admin',
          correlationId: () => 'corr-test',
          maxRetries: 0,
          httpClient: MockClient((r) async {
            visto = r;
            return http.Response(
              jsonEncode({
                'eventos': [_evento('e1')],
              }),
              200,
              headers: _json,
            );
          }),
        ),
      );

      final lista = await fuente.listar(
        despuesDe: 'e0',
        pagoId: _pagoId,
        limite: 10,
      );

      expect(lista.single.id, 'e1');
      expect(visto.url.path, '/api/v1/core/auditoria/transacciones');
      expect(visto.url.queryParameters, {
        'limite': '10',
        'despuesDe': 'e0',
        'pagoId': _pagoId,
      });
      expect(visto.headers['Authorization'], 'Bearer jwt-admin');
      expect(visto.url.toString().contains('tenant'), isFalse);
    });

    test('una respuesta sin la lista eventos es un error de formato', () async {
      final fuente = GatewayFuenteAuditoria(
        GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt',
          maxRetries: 0,
          httpClient: MockClient(
            (_) async =>
                http.Response(jsonEncode({'otra': 1}), 200, headers: _json),
          ),
        ),
      );
      await expectLater(fuente.listar(), throwsFormatException);
    });
  });

  group('AuditoriaCubit', () {
    test(
      'carga la primera página y detecta que hay más si vino llena',
      () async {
        final f = _FuenteFalsa(
          paginas: [
            [_e('1'), _e('2')],
          ],
        );
        final cubit = AuditoriaCubit(f, tamanoPagina: 2);
        await cubit.cargar();
        expect(cubit.state.fase, FaseAuditoria.listo);
        expect(cubit.state.eventos.map((e) => e.id), ['1', '2']);
        expect(cubit.state.hayMas, isTrue);
        expect(f.pedidos.single.despuesDe, isNull);
      },
    );

    test(
      'cargar más usa el id del último evento y acumula; una página corta termina la lista',
      () async {
        final f = _FuenteFalsa(
          paginas: [
            [_e('1'), _e('2')],
            [_e('3')],
          ],
        );
        final cubit = AuditoriaCubit(f, tamanoPagina: 2);
        await cubit.cargar();
        await cubit.cargarMas();
        expect(cubit.state.eventos.map((e) => e.id), ['1', '2', '3']);
        expect(cubit.state.hayMas, isFalse);
        expect(f.pedidos.last.despuesDe, '2');
        await cubit.cargarMas();
        expect(
          f.pedidos,
          hasLength(2),
          reason: 'sin más páginas no vuelve a pedir',
        );
      },
    );

    test(
      'un filtro de pago que no es UUID se rechaza sin consultar a Core',
      () async {
        final f = _FuenteFalsa();
        final cubit = AuditoriaCubit(f);
        await cubit.cargar(pagoId: 'no-es-uuid');
        expect(cubit.state.fase, FaseAuditoria.error);
        expect(cubit.state.error, contains('no es válido'));
        expect(f.pedidos, isEmpty);
      },
    );

    test(
      'un pago válido filtra la consulta; un filtro vacío la deja sin filtro',
      () async {
        final f = _FuenteFalsa(paginas: [[], []]);
        final cubit = AuditoriaCubit(f);
        await cubit.cargar(pagoId: _pagoId);
        expect(f.pedidos.last.pagoId, _pagoId);
        await cubit.cargar(pagoId: '  ');
        expect(f.pedidos.last.pagoId, isNull);
      },
    );

    test(
      'C3: un 403 de Core (no es administrador) se muestra y no deja datos',
      () async {
        final f = _FuenteFalsa(
          falla: const GatewayException(
            message: 'No tienes permiso para realizar esta acción.',
            statusCode: 403,
          ),
        );
        final cubit = AuditoriaCubit(f);
        await cubit.cargar();
        expect(cubit.state.fase, FaseAuditoria.error);
        expect(cubit.state.error, contains('No tienes permiso'));
        expect(cubit.state.eventos, isEmpty);
      },
    );

    test('un error de formato da un mensaje genérico', () async {
      final cubit = AuditoriaCubit(
        _FuenteFalsa(falla: const FormatException('x')),
      );
      await cubit.cargar();
      expect(cubit.state.error, contains('No pudimos leer la auditoría'));
    });
  });

  group('AuditoriaView', () {
    Future<void> montar(
      WidgetTester tester,
      _FuenteFalsa f, {
      int pagina = 50,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 2200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => AuditoriaCubit(f, tamanoPagina: pagina)..cargar(),
            child: const AuditoriaView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'muestra el aviso de inmutable y los eventos con quién y cuándo',
      (tester) async {
        await montar(
          tester,
          _FuenteFalsa(
            paginas: [
              [_e('e1')],
            ],
          ),
        );
        expect(find.byKey(const Key('aviso-inmutable')), findsOneWidget);
        expect(find.byKey(const Key('evento-e1')), findsOneWidget);
        expect(find.text('Hizo: Cliente'), findsOneWidget);
        expect(find.textContaining('Pago registrado'), findsOneWidget);
      },
    );

    testWidgets('sin eventos muestra el estado vacío', (tester) async {
      await montar(tester, _FuenteFalsa());
      expect(find.byKey(const Key('auditoria-vacia')), findsOneWidget);
    });

    testWidgets(
      'filtrar por pago consulta con ese id; cargar más agrega la siguiente página',
      (tester) async {
        final f = _FuenteFalsa(
          paginas: [
            [_e('e1')],
            [],
            [_e('e2')],
          ],
        );
        await montar(tester, f, pagina: 1);
        expect(find.byKey(const Key('cargar-mas')), findsOneWidget);

        await tester.enterText(find.byKey(const Key('filtro-pago')), _pagoId);
        await tester.tap(find.byKey(const Key('btn-filtrar')));
        await tester.pumpAndSettle();
        expect(f.pedidos.last.pagoId, _pagoId);
      },
    );

    testWidgets('un error muestra el mensaje y permite reintentar', (
      tester,
    ) async {
      final f = _FuenteFalsa(
        falla: const GatewayException(message: 'Sin permiso', statusCode: 403),
      );
      await montar(tester, f);
      expect(find.byKey(const Key('error-auditoria')), findsOneWidget);
      f
        ..falla = null
        ..paginas = [
          [_e('e9')],
        ];
      await tester.tap(find.byKey(const Key('reintentar-auditoria')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('evento-e9')), findsOneWidget);
    });

    testWidgets('cargar más agrega los eventos siguientes', (tester) async {
      final f = _FuenteFalsa(
        paginas: [
          [_e('a')],
          [_e('b')],
        ],
      );
      await montar(tester, f, pagina: 1);
      await tester.tap(find.byKey(const Key('cargar-mas')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('evento-a')), findsOneWidget);
      expect(find.byKey(const Key('evento-b')), findsOneWidget);
    });
  });
}
