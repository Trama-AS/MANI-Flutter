import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/notifications/data/avisos_datasource.dart';
import 'package:mani/features/notifications/domain/aviso.dart';
import 'package:mani/features/notifications/presentation/avisos_cubit.dart';
import 'package:mani/features/notifications/presentation/avisos_page.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _item(
  String id,
  String tipo, {
  Map<String, dynamic>? payload,
  String? leido,
}) => {
  'id': id,
  'tipo': tipo,
  'canal': 'PUSH',
  'payload': payload ?? {'requestId': 'sol-1'},
  'enviadoAt': '2026-11-04T15:05:00.000Z',
  'leidoAt': leido,
};

Map<String, dynamic> _bandeja(List<Map<String, dynamic>> items) => {
  'proveedor': 'mock',
  'simulada': true,
  'items': items,
};

class _FuenteFalsa implements FuenteAvisos {
  _FuenteFalsa({this.respuesta, this.falla});

  BandejaAvisos? respuesta;
  Object? falla;
  int llamadas = 0;

  @override
  Future<BandejaAvisos> listar({int limite = 50}) async {
    llamadas++;
    if (falla != null) throw falla!;
    return respuesta!;
  }
}

/// SCRUM-882 y 884: la bandeja de avisos sale por el Gateway a Core.
void main() {
  group('Aviso', () {
    test('mensaje nuevo: título, detalle según el remitente y solicitud', () {
      final a = Aviso.fromJson(
        _item(
          'a1',
          'MENSAJE_NUEVO',
          payload: {'solicitudId': 'sol-9', 'remitenteRol': 'CLIENT'},
        ),
      );
      expect(a.esMensaje, isTrue);
      expect(a.titulo, 'Nuevo mensaje');
      expect(a.detalle, 'Te escribió el cliente.');
      expect(a.solicitudId, 'sol-9');
      expect(a.leido, isFalse);
      expect(a.enviadoEn, isNotNull);
    });

    test(
      'cada tipo de cambio de estado tiene su título; uno desconocido, uno genérico',
      () {
        const esperados = {
          'SOLICITUD_ASIGNADA': 'Un aliado aceptó tu solicitud',
          'SOLICITUD_CANCELADA': 'La solicitud fue cancelada',
          'EJECUCION_INICIADA': 'El servicio comenzó',
          'EJECUCION_FINALIZADA': 'El servicio finalizó',
          'COTIZACION_RECIBIDA': 'Recibiste una cotización',
          'RESPUESTA_COTIZACION': 'El cliente respondió tu cotización',
          'ADICION_SOLICITADA': 'El aliado pidió una adición',
          'ADICION_ACEPTADA': 'Adición aceptada',
          'ADICION_RECHAZADA': 'Adición rechazada',
          'OFERTA_DESPACHO': 'Nueva oferta de servicio',
          'OTRO_TIPO': 'Aviso',
        };
        for (final e in esperados.entries) {
          expect(
            Aviso.fromJson(_item('x', e.key)).titulo,
            e.value,
            reason: e.key,
          );
        }
        expect(
          Aviso.fromJson(_item('x', 'EJECUCION_INICIADA')).detalle,
          'El aliado marcó el inicio del trabajo.',
        );
        expect(
          Aviso.fromJson(_item('x', 'EJECUCION_FINALIZADA')).detalle,
          'El aliado marcó el fin del trabajo.',
        );
        expect(
          Aviso.fromJson(_item('x', 'SOLICITUD_ASIGNADA')).detalle,
          isNotEmpty,
        );
        expect(Aviso.fromJson(_item('x', 'OTRO_TIPO')).detalle, isEmpty);
      },
    );

    test(
      'sin solicitud en el payload no hay a dónde navegar; leído se reconoce',
      () {
        final a = Aviso.fromJson(
          _item(
            'a',
            'MENSAJE_NUEVO',
            payload: {'mensajeId': 'm'},
            leido: '2026-11-04T16:00:00Z',
          ),
        );
        expect(a.solicitudId, isNull);
        expect(a.leido, isTrue);
        expect(
          Aviso.fromJson({'id': 'z', 'payload': 'no-es-mapa'}).payload,
          isEmpty,
        );
      },
    );

    test('la bandeja exige la lista items', () {
      expect(
        () => BandejaAvisos.fromJson({'proveedor': 'mock'}),
        throwsFormatException,
      );
    });
  });

  group('GatewayFuenteAvisos', () {
    test(
      'GET a la bandeja con el límite, sin enviar usuario ni tenant',
      () async {
        late http.Request visto;
        final fuente = GatewayFuenteAvisos(
          GatewayClient(
            baseUrl: 'http://gateway.local',
            tokenProvider: () async => 'jwt-usuario',
            correlationId: () => 'corr-test',
            maxRetries: 0,
            httpClient: MockClient((r) async {
              visto = r;
              return http.Response(
                jsonEncode(_bandeja([_item('a1', 'MENSAJE_NUEVO')])),
                200,
                headers: _json,
              );
            }),
          ),
        );

        final b = await fuente.listar(limite: 20);

        expect(b.items.single.id, 'a1');
        expect(b.simulada, isTrue);
        expect(visto.method, 'GET');
        expect(visto.url.path, '/api/v1/core/profiles/me/inbox');
        expect(visto.url.queryParameters, {'limit': '20'});
        expect(visto.headers['Authorization'], 'Bearer jwt-usuario');
        expect(visto.url.toString().contains('tenant'), isFalse);
      },
    );
  });

  group('AvisosCubit', () {
    test('carga la bandeja', () async {
      final f = _FuenteFalsa(
        respuesta: BandejaAvisos.fromJson(
          _bandeja([_item('a', 'MENSAJE_NUEVO')]),
        ),
      );
      final cubit = AvisosCubit(f);
      await cubit.cargar();
      expect(cubit.state.fase, FaseAvisos.listo);
      expect(cubit.state.bandeja!.items, hasLength(1));
    });

    test(
      'un error del Gateway se muestra con su mensaje; uno de formato, genérico',
      () async {
        final f = _FuenteFalsa(
          falla: const GatewayException(
            message: 'Sin permiso',
            statusCode: 403,
          ),
        );
        final cubit = AvisosCubit(f);
        await cubit.cargar();
        expect(cubit.state.fase, FaseAvisos.error);
        expect(cubit.state.error, 'Sin permiso');

        f.falla = const FormatException('x');
        await cubit.cargar();
        expect(cubit.state.error, contains('No pudimos leer tus avisos'));
      },
    );
  });

  group('AvisosView', () {
    Future<_FuenteFalsa> montar(
      WidgetTester tester,
      _FuenteFalsa f, {
      void Function(Aviso)? onAbrir,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => AvisosCubit(f)..cargar(),
            child: AvisosView(onAbrir: onAbrir),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return f;
    }

    BandejaAvisos bandeja(
      List<Map<String, dynamic>> items, {
      bool simulada = true,
    }) => BandejaAvisos.fromJson({..._bandeja(items), 'simulada': simulada});

    testWidgets('sin avisos muestra el estado vacío', (tester) async {
      await montar(tester, _FuenteFalsa(respuesta: bandeja([])));
      expect(find.byKey(const Key('avisos-vacio')), findsOneWidget);
    });

    testWidgets(
      'muestra mensajes nuevos y cambios de estado, y el aviso de simulado',
      (tester) async {
        await montar(
          tester,
          _FuenteFalsa(
            respuesta: bandeja([
              _item(
                'm1',
                'MENSAJE_NUEVO',
                payload: {'requestId': 's', 'remitenteRol': 'ALLY'},
              ),
              _item(
                'e1',
                'EJECUCION_FINALIZADA',
                leido: '2026-11-04T16:00:00Z',
              ),
            ]),
          ),
        );
        expect(find.text('Nuevo mensaje'), findsOneWidget);
        expect(find.text('El servicio finalizó'), findsOneWidget);
        expect(find.byKey(const Key('aviso-m1')), findsOneWidget);
        expect(find.byKey(const Key('aviso-simulado')), findsOneWidget);
      },
    );

    testWidgets('sin la marca de simulado no la muestra', (tester) async {
      await montar(
        tester,
        _FuenteFalsa(
          respuesta: bandeja([_item('a', 'MENSAJE_NUEVO')], simulada: false),
        ),
      );
      expect(find.byKey(const Key('aviso-simulado')), findsNothing);
    });

    testWidgets(
      'tocar un aviso con solicitud abre su pantalla; uno sin solicitud no hace nada',
      (tester) async {
        final abiertos = <String>[];
        await montar(
          tester,
          _FuenteFalsa(
            respuesta: bandeja([
              _item('con', 'MENSAJE_NUEVO'),
              _item('sin', 'SOLICITUD_CANCELADA', payload: const {}),
            ]),
          ),
          onAbrir: (a) => abiertos.add(a.id),
        );
        await tester.tap(find.byKey(const Key('aviso-con')));
        await tester.tap(find.byKey(const Key('aviso-sin')));
        await tester.pump();
        expect(abiertos, ['con']);
      },
    );

    testWidgets('un error muestra el mensaje y permite reintentar', (
      tester,
    ) async {
      final f = _FuenteFalsa(
        falla: const GatewayException(
          message: 'Sin conexión',
          statusCode: null,
        ),
      );
      await montar(tester, f);
      expect(find.byKey(const Key('error-avisos')), findsOneWidget);
      f
        ..falla = null
        ..respuesta = bandeja([_item('a', 'MENSAJE_NUEVO')]);
      await tester.tap(find.byKey(const Key('reintentar-avisos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-avisos')), findsNothing);
      expect(find.text('Nuevo mensaje'), findsOneWidget);
      expect(f.llamadas, 2);
    });
  });
}
