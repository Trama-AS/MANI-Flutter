import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/complaints/data/quejas_datasource.dart';
import 'package:mani/features/complaints/domain/queja.dart';
import 'package:mani/features/metrics/data/metricas_datasource.dart';
import 'package:mani/features/platform/data/tenants_datasource.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> quejaJson({
  String estado = 'ABIERTA',
  List historial = const [],
}) => {
  'id': 'q-1',
  'solicitudId': 'sol-1',
  'categoria': 'Plomería',
  'motivo': 'COBRO_INDEBIDO',
  'descripcion': 'Me cobraron dos veces',
  'estado': estado,
  'respuesta': null,
  'cliente': {'email': 'ana@t.test'},
  'creadaEn': '2026-10-29T15:00:00.000Z',
  'historial': historial,
};

/// M-12: la app llama a Core por el Gateway (nunca a los puertos internos), sin enviar tenant ni rol, y
/// muestra el error de Core tal como lo explica.
void main() {
  late List<http.Request> alGateway;
  late http.Response Function(http.Request) responder;

  GatewayClient gateway() => GatewayClient(
    baseUrl: 'http://gateway.local',
    tokenProvider: () async => 'jwt-de-prueba',
    correlationId: () => 'corr-test',
    httpClient: MockClient((r) async {
      alGateway.add(r);
      return responder(r);
    }),
  );

  Map<String, dynamic> cuerpo([int i = 0]) =>
      jsonDecode(utf8.decode(alGateway[i].bodyBytes)) as Map<String, dynamic>;

  setUp(() => alGateway = []);

  group('SCRUM-895/896 · quejas', () {
    test(
      'registrar envía motivo y descripción a la solicitud; mias y del tenant usan sus rutas',
      () async {
        responder = (r) => r.method == 'POST'
            ? http.Response(
                jsonEncode({'queja': quejaJson()}),
                201,
                headers: _json,
              )
            : http.Response(
                jsonEncode({
                  'quejas': [quejaJson()],
                }),
                200,
                headers: _json,
              );
        final fuente = GatewayFuenteQuejas(gateway());

        final q = await fuente.registrar(
          'sol-1',
          motivo: MotivoQueja.cobroIndebido,
          descripcion: '  Me cobraron dos veces ',
        );
        await fuente.mias();
        await fuente.delTenant(estado: EstadoQueja.abierta);
        await fuente.delTenant();

        expect(alGateway[0].url.path, '/api/v1/core/solicitudes/sol-1/quejas');
        expect(cuerpo(), {
          'motivo': 'COBRO_INDEBIDO',
          'descripcion': 'Me cobraron dos veces',
        });
        expect(q.etiquetaMotivo, 'Cobro indebido');
        expect(alGateway[1].url.path, '/api/v1/core/quejas/mias');
        expect(
          alGateway[2].url.toString(),
          'http://gateway.local/api/v1/core/quejas?estado=ABIERTA',
        );
        expect(alGateway[3].url.queryParameters, isEmpty);
      },
    );

    test(
      'cambiar estado hace PATCH con estado y nota y lee el historial',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'queja': quejaJson(
              estado: 'RESUELTA',
              historial: [
                {
                  'estadoAnterior': null,
                  'estadoNuevo': 'ABIERTA',
                  'actor': {'rol': 'CLIENT'},
                  'fecha': '2026-10-29T15:00:00Z',
                },
                {
                  'estadoAnterior': 'ABIERTA',
                  'estadoNuevo': 'RESUELTA',
                  'actor': {'rol': 'ADMIN'},
                  'nota': 'Reembolso',
                  'fecha': '2026-10-29T16:00:00Z',
                },
              ],
            ),
          }),
          200,
          headers: _json,
        );
        final q = await GatewayFuenteQuejas(
          gateway(),
        ).cambiarEstado('q-1', EstadoQueja.resuelta, nota: 'Reembolso');
        expect(alGateway.single.method, 'PATCH');
        expect(alGateway.single.url.path, '/api/v1/core/quejas/q-1/estado');
        expect(cuerpo(), {'estado': 'RESUELTA', 'nota': 'Reembolso'});
        expect(q.historial.map((h) => h.estadoNuevo), [
          EstadoQueja.abierta,
          EstadoQueja.resuelta,
        ]);
        expect(q.historial.first.estadoAnterior, isNull);
      },
    );

    test(
      'las transiciones de la app son las de Core y la descripción exige 10 caracteres',
      () {
        expect(EstadoQueja.abierta.siguientes, [
          EstadoQueja.enRevision,
          EstadoQueja.resuelta,
          EstadoQueja.rechazada,
        ]);
        expect(EstadoQueja.enRevision.siguientes, [
          EstadoQueja.resuelta,
          EstadoQueja.rechazada,
        ]);
        expect(EstadoQueja.resuelta.siguientes, isEmpty);
        expect(EstadoQueja.rechazada.siguientes, isEmpty);
        expect(descripcionQuejaValida('corta'), isFalse);
        expect(descripcionQuejaValida('  diez letras '), isTrue);
        expect(descripcionQuejaValida('x' * 1001), isFalse);
      },
    );
  });

  group('SCRUM-900 · métricas', () {
    test('pide el periodo y conserva ceros y tasas nulas', () async {
      responder = (_) => http.Response(
        jsonEncode({
          'periodo': {'desde': '2020-01-01', 'hasta': '2020-01-31'},
          'solicitudes': {
            'creadas': 0,
            'porEstado': {},
            'finalizadas': 0,
            'canceladas': 0,
            'tasaCancelacion': null,
          },
          'cotizaciones': {
            'emitidas': 0,
            'aceptadas': 0,
            'tasaAceptacion': null,
          },
          'pagos': {'aprobados': 0, 'montoAprobado': 0},
          'calificaciones': {'total': 0, 'promedio': null},
          'quejas': {'registradas': 0, 'abiertas': 0, 'cerradas': 0},
          'aliadosConServicios': 0,
        }),
        200,
        headers: _json,
      );
      final m = await GatewayFuenteMetricas(
        gateway(),
      ).consultar('2020-01-01', '2020-01-31');
      expect(alGateway.single.url.path, '/api/v1/core/metricas/operativas');
      expect(alGateway.single.url.queryParameters, {
        'desde': '2020-01-01',
        'hasta': '2020-01-31',
      });
      expect(m.solicitudesCreadas, 0);
      expect(m.tasaCancelacion, isNull);
      expect(m.calificacionPromedio, isNull);
    });
  });

  group('SCRUM-901 · tenants', () {
    test('lista, cambia el estado con motivo y lee el historial', () async {
      responder = (r) {
        if (r.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'tenant': {
                'id': 't-2',
                'name': 'Otro',
                'slug': 'otro',
                'status': 'SUSPENDED',
              },
              'cambio': {},
            }),
            200,
            headers: _json,
          );
        }
        if (r.url.path.endsWith('/historial')) {
          return http.Response(
            jsonEncode({
              'cambios': [
                {
                  'estadoAnterior': 'ACTIVE',
                  'estadoNuevo': 'SUSPENDED',
                  'motivo': 'Mora del plan',
                  'fecha': '2026-10-29T15:00:00Z',
                },
              ],
            }),
            200,
            headers: _json,
          );
        }
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 't-2', 'name': 'Otro', 'slug': 'otro', 'status': 'ACTIVE'},
            ],
          }),
          200,
          headers: _json,
        );
      };
      final fuente = GatewayFuenteTenants(gateway());
      final lista = await fuente.listar();
      final t = await fuente.cambiarEstado(
        't-2',
        EstadoTenant.suspendido,
        ' Mora del plan ',
      );
      final historial = await fuente.historial('t-2');

      expect(alGateway[0].url.path, '/api/v1/core/tenants');
      expect(lista.single.estado, EstadoTenant.activo);
      expect(alGateway[1].url.path, '/api/v1/core/tenants/t-2/estado');
      expect(cuerpo(1), {'estado': 'SUSPENDED', 'motivo': 'Mora del plan'});
      expect(t.estado, EstadoTenant.suspendido);
      expect(historial.single.nuevo, EstadoTenant.suspendido);
    });
  });
}
