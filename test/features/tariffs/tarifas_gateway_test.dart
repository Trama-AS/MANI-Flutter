import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import 'package:mani/features/tariffs/data/tarifas_datasource.dart';
import 'package:mani/features/tariffs/domain/evaluacion_tarifa.dart';
import 'package:mani/features/tariffs/domain/tarifa.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> tarifaJson({
  int version = 1,
  String estado = 'ACTIVA',
}) => {
  'id': 'tar-$version',
  'categoriaId': 'cat-1',
  'categoriaNombre': 'Plomería',
  'valorMin': 80000,
  'valorTipico': 120000,
  'valorMax': 180000.5,
  'moneda': 'COP',
  'vigenciaDesde': '2026-01-01',
  'vigenciaHasta': null,
  'condiciones': 'Incluye visita',
  'version': version,
  'estado': estado,
  'auditoria': {'creadaEn': '2026-10-29T15:00:00.000Z', 'actorRol': 'ADMIN'},
};

/// M-10: la app llama a Core por el Gateway (nunca a los puertos internos), sin enviar tenant ni rol, y
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

  group('SCRUM-885/886/887 · tarifario', () {
    test(
      'crear envía la categoría y los valores; no envía tenant ni actor',
      () async {
        responder = (_) => http.Response(
          jsonEncode({'tarifa': tarifaJson()}),
          201,
          headers: _json,
        );
        final t = await GatewayFuenteTarifas(gateway()).crear(
          'cat-1',
          const DatosTarifa(
            valorMin: 80000,
            valorTipico: 120000,
            valorMax: 180000.5,
            vigenciaDesde: '2026-01-01',
          ),
        );

        expect(alGateway.single.method, 'POST');
        expect(alGateway.single.url.path, '/api/v1/core/tarifas');
        expect(
          alGateway.single.headers['Authorization'],
          'Bearer jwt-de-prueba',
        );
        expect(cuerpo(), {
          'categoriaId': 'cat-1',
          'valorMin': 80000.0,
          'valorTipico': 120000.0,
          'valorMax': 180000.5,
          'moneda': 'COP',
          'vigenciaDesde': '2026-01-01',
        });
        expect(cuerpo().containsKey('tenantId'), isFalse);
        expect(t.valorMax, 180000.5);
        expect(t.vigencia, 'Desde 2026-01-01 (sin fin)');
      },
    );

    test(
      'editar hace PUT sobre la versión y el historial lee todas las versiones',
      () async {
        responder = (r) => r.method == 'PUT'
            ? http.Response(
                jsonEncode({'tarifa': tarifaJson(version: 2)}),
                200,
                headers: _json,
              )
            : http.Response(
                jsonEncode({
                  'versiones': [
                    tarifaJson(version: 2),
                    tarifaJson(version: 1, estado: 'REEMPLAZADA'),
                  ],
                }),
                200,
                headers: _json,
              );
        final fuente = GatewayFuenteTarifas(gateway());
        final v2 = await fuente.editar(
          'tar-1',
          const DatosTarifa(valorMin: 1, valorTipico: 2, valorMax: 3),
        );
        final historial = await fuente.historial('cat-1');

        expect(alGateway[0].method, 'PUT');
        expect(alGateway[0].url.path, '/api/v1/core/tarifas/tar-1');
        expect(v2.version, 2);
        expect(
          alGateway[1].url.path,
          '/api/v1/core/tarifas/categorias/cat-1/historial',
        );
        expect(historial.map((t) => [t.version, t.activa]), [
          [2, true],
          [1, false],
        ]);
      },
    );

    test(
      'la referencia sin tarifa vigente es "no disponible", sin valores',
      () async {
        responder = (_) => http.Response(
          jsonEncode({'disponible': false, 'tarifa': null}),
          200,
          headers: _json,
        );
        final r = await GatewayFuenteTarifas(gateway()).referencia('sol-9');
        expect(
          alGateway.single.url.path,
          '/api/v1/core/solicitudes/sol-9/tarifa-referencia',
        );
        expect(r.disponible, isFalse);
        expect(r.tarifa, isNull);
      },
    );

    test(
      '866: la evaluación de una cotización va por el Gateway, sin tenant ni rol, y lee la referencia',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'cotizacionId': 'cot-1',
            'solicitudId': 'sol-1',
            'version': 2,
            'total': 270000,
            'resultado': 'POR_ENCIMA',
            'alerta': true,
            'desviacionPorcentaje': 50,
            'tarifa': {
              'id': 'tar-1',
              'version': 1,
              'valorMin': 80000,
              'valorTipico': 120000,
              'valorMax': 180000,
              'moneda': 'COP',
            },
            'reglasVersion': 'rates-v1',
            'correlationId': 'corr-test',
          }),
          200,
          headers: _json,
        );
        final e = await GatewayFuenteTarifas(gateway()).evaluacion('cot-1');
        expect(alGateway.single.method, 'GET');
        expect(
          alGateway.single.url.toString(),
          'http://gateway.local/api/v1/core/cotizaciones/cot-1/evaluacion-tarifa',
        );
        expect(
          alGateway.single.headers['Authorization'],
          'Bearer jwt-de-prueba',
        );
        expect(
          alGateway.single.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-tenant-id')),
        );
        expect(e.resultado, ResultadoTarifa.porEncima);
        expect(e.alerta, isTrue);
        expect(
          [e.valorMin, e.valorTipico, e.valorMax],
          [80000, 120000, 180000],
        );
        expect(e.desviacionPorcentaje, 50);
      },
    );

    test(
      'el reporte pide el periodo y lee las cotizaciones fuera de rango',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'periodo': {'desde': '2026-10-01', 'hasta': '2026-10-31'},
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
                'categoria': {'id': 'cat-1', 'nombre': 'Plomería'},
                'aliado': {'id': 'a-1', 'nombre': 'Ana'},
                'tarifa': {
                  'id': 'tar-1',
                  'version': 1,
                  'valorMin': 80000,
                  'valorTipico': 120000,
                  'valorMax': 180000,
                },
                'resultado': 'POR_ENCIMA',
                'desviacionPorcentaje': 38.89,
              },
            ],
          }),
          200,
          headers: _json,
        );
        final r = await GatewayFuenteTarifas(
          gateway(),
        ).reporteFueraDeRango('2026-10-01', '2026-10-31');
        expect(
          alGateway.single.url.path,
          '/api/v1/core/reportes/cotizaciones-fuera-de-rango',
        );
        expect(alGateway.single.url.queryParameters, {
          'desde': '2026-10-01',
          'hasta': '2026-10-31',
        });
        expect(r.sinTarifa, 1);
        expect(r.cotizaciones.single.porEncima, isTrue);
        expect(r.cotizaciones.single.desviacionPorcentaje, 38.89);
      },
    );

    test(
      'un 503 de Rules se muestra como motor no disponible, sin valores calculados',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'error': 'El servicio de reglas no está disponible',
            'code': 'RULES_SERVICE_UNAVAILABLE',
            'correlationId': 'c',
          }),
          503,
          headers: _json,
        );
        try {
          await GatewayFuenteTarifas(
            gateway(),
          ).reporteFueraDeRango('2026-10-01', '2026-10-31');
          fail('debía fallar');
        } on GatewayException catch (e) {
          expect(
            mensajeErrorGateway(e),
            contains('motor de reglas no está disponible'),
          );
        }
      },
    );

    test('un 409 de Core se muestra sin su código', () {
      const e = GatewayException(
        message: 'x',
        statusCode: 409,
        cuerpo: {
          'error':
              'MANI-TAR-409V: la vigencia se cruza con otra tarifa activa de la categoría',
          'code': 'MANI-TAR-409V',
        },
      );
      expect(
        mensajeErrorGateway(e),
        'la vigencia se cruza con otra tarifa activa de la categoría',
      );
    });
  });
}
