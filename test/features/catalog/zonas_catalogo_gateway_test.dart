import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/catalog/data/zonas_catalogo_remote_datasource.dart';

/// HU-M04-04: el catálogo geográfico se consume por el Gateway
/// (`/api/v1/core/catalog/zones`), nunca contra el puerto interno de Core ni
/// con una lista de zonas fija en el código.
void main() {
  late List<http.Request> alGateway;
  late http.Response Function(http.Request) responder;

  // El Gateway responde siempre con content-type JSON; el doble debe hacer
  // lo mismo o el cliente no decodifica el cuerpo.
  http.Response json(String body, [int status = 200]) =>
      http.Response(body, status, headers: const {
        'content-type': 'application/json; charset=utf-8',
      });

  ZonasCatalogoRemoteDataSource datasource({String? token}) {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => token,
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return ZonasCatalogoRemoteDataSource(gateway: gateway);
  }

  // Respuesta con la forma real del contrato: árbol anidado, lista plana y
  // el reporte de inconsistencias.
  String arbolDeEjemplo({bool conInactiva = false}) => jsonEncode({
    'zones': const [],
    'tree': [
      {
        'id': 'zona-ciudad',
        'name': 'Bogotá D.C.',
        'level': 'CIUDAD',
        'parentId': null,
        'active': true,
        'selectable': true,
        'children': [
          {
            'id': 'zona-chapinero',
            'name': 'Chapinero',
            'level': 'LOCALIDAD',
            'parentId': 'zona-ciudad',
            'active': true,
            'selectable': true,
            'children': [
              {
                'id': 'zona-chico',
                'name': 'Chicó Norte',
                'level': 'BARRIO',
                'parentId': 'zona-chapinero',
                'active': true,
                'selectable': true,
                'children': const [],
              },
            ],
          },
          if (conInactiva)
            {
              'id': 'zona-retirada',
              'name': 'Zona Retirada',
              'level': 'LOCALIDAD',
              'parentId': 'zona-ciudad',
              'active': false,
              'selectable': false,
              'children': const [],
            },
        ],
      },
    ],
    'inconsistencies': const [],
  });

  setUp(() {
    alGateway = [];
    responder = (_) => json(arbolDeEjemplo());
  });

  test('la consulta sale por el Gateway, no contra el puerto interno de Core', () async {
    await datasource().consultarJerarquia();

    expect(alGateway, hasLength(1));
    final uri = alGateway.single.url;
    expect(uri.host, 'gateway.local');
    expect(uri.path, '/api/v1/core/catalog/zones');
    expect(uri.queryParameters['onlyActive'], 'true');
  });

  test('propaga el JWT de la sesión y un X-Correlation-ID', () async {
    await datasource(token: 'jwt-de-la-sesion').consultarJerarquia();

    final headers = alGateway.single.headers;
    expect(headers['Authorization'], 'Bearer jwt-de-la-sesion');
    expect(headers[GatewayClient.headerCorrelationId], isNotEmpty);
  });

  test('arma la jerarquía anidada que devuelve el contrato', () async {
    final jerarquia = await datasource().consultarJerarquia();

    expect(jerarquia, hasLength(1));
    final ciudad = jerarquia.single;
    expect(ciudad.nombre, 'Bogotá D.C.');
    expect(ciudad.nivel, 'CIUDAD');
    expect(ciudad.zonaPadreId, isNull);
    final localidad = ciudad.hijos.single;
    expect(localidad.nombre, 'Chapinero');
    expect(localidad.hijos.single.nombre, 'Chicó Norte');
  });

  test('las opciones del desplegable llevan la etiqueta jerárquica completa', () async {
    final opciones = await datasource().opcionesSeleccionables();

    expect(opciones['zona-ciudad'], 'Bogotá D.C.');
    expect(opciones['zona-chapinero'], 'Bogotá D.C. · Chapinero');
    expect(opciones['zona-chico'], 'Bogotá D.C. · Chapinero · Chicó Norte');
  });

  test('una zona no seleccionable no se ofrece como opción', () async {
    responder = (_) => json(arbolDeEjemplo(conInactiva: true));

    final opciones = await datasource().opcionesSeleccionables();

    expect(opciones.containsKey('zona-retirada'), isFalse);
    expect(opciones.containsKey('zona-chapinero'), isTrue);
  });

  test('se puede pedir solo un nivel de la jerarquía', () async {
    final opciones = await datasource().opcionesSeleccionables(nivel: 'BARRIO');

    expect(opciones.keys, ['zona-chico']);
  });

  test('un catálogo sin zonas devuelve vacío en vez de inventar opciones', () async {
    responder = (_) =>
        json(jsonEncode({'zones': [], 'tree': [], 'inconsistencies': []}));

    expect(await datasource().opcionesSeleccionables(), isEmpty);
  });

  test('un rechazo del Gateway se propaga como GatewayException', () async {
    responder = (_) => json(
      jsonEncode({'error': 'UNAUTHORIZED', 'message': 'sin token'}),
      401,
    );

    expect(
      () => datasource().consultarJerarquia(),
      throwsA(isA<GatewayException>()),
    );
  });
}
