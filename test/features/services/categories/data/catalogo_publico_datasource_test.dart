import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/categories/data/datasources/catalogo_publico_datasource.dart';

/// Los registros de aliado leen las especialidades del catálogo público del
/// tenant en vez de UUID fijos de la semilla de desarrollo.
void main() {
  late http.Request capturada;

  CatalogoPublicoDataSource datasource(http.Response Function() responder) =>
      CatalogoPublicoDataSource(
        GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => null,
          correlationId: () => 'corr-cat',
          httpClient: MockClient((r) async {
            capturada = r;
            return responder();
          }),
        ),
      );

  test('GET /api/v1/core/catalog con X-Tenant-Slug y sin token', () async {
    await datasource(
      () => http.Response(jsonEncode({'categories': []}), 200),
    ).categoriasActivas('acme-servicios');

    expect(capturada.method, 'GET');
    expect(capturada.url.path, '/api/v1/core/catalog');
    expect(capturada.headers['X-Tenant-Slug'], 'acme-servicios');
    expect(capturada.headers.containsKey('Authorization'), isFalse);
  });

  test('devuelve solo las categorías activas con id y nombre', () async {
    final categorias = await datasource(
      () => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'categories': [
              {'id': 'c-1', 'name': 'Plomería', 'active': true},
              {'id': 'c-2', 'name': 'Inactiva', 'active': false},
              {'id': 'c-3', 'name': 'Sin campo active'},
              {'name': 'Sin id', 'active': true},
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ).categoriasActivas('acme-servicios');

    expect(categorias.map((c) => c.id), ['c-1', 'c-3']);
    expect(categorias.first.nombre, 'Plomería');
  });

  test('una respuesta sin "categories" es un error, no un catálogo vacío', () {
    expect(
      datasource(
        () => http.Response(jsonEncode({'data': []}), 200),
      ).categoriasActivas('acme-servicios'),
      throwsA(isA<GatewayException>()),
    );
  });

  test('un tenant inexistente propaga el error de Core', () {
    expect(
      datasource(
        () => http.Response(
          jsonEncode({
            'error': 'El tenant no existe',
            'code': 'TENANT_NOT_FOUND',
          }),
          400,
        ),
      ).categoriasActivas('no-existe'),
      throwsA(isA<GatewayException>()),
    );
  });
}
