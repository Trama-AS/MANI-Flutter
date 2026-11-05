import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profile_categories/data/datasources/categories_remote_datasource.dart';
import 'package:mani/features/profile_categories/data/repositories/categories_repository_impl.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';

/// SCRUM-1380: las categorías del aliado salen solo por el API Gateway hacia
/// Core Node; ninguna petición va a las RPC de Supabase (ADR-0027).
void main() {
  late List<http.Request> peticiones;
  late http.Response Function(http.Request) responder;

  http.Response json(Object cuerpo, [int status = 200]) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  CategoriesRemoteDataSource datasource() => GatewayCategoriesDataSource(
    GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-aliado',
      correlationId: () => 'corr-test',
      maxRetries: 0,
      httpClient: MockClient((r) async {
        peticiones.add(r);
        return responder(r);
      }),
    ),
  );

  setUp(() {
    peticiones = [];
    responder = (_) => json({});
  });

  test('lista las categorías disponibles y las entrega con `nombre`', () async {
    responder = (_) => json({
      'categories': [
        {'id': 'c1', 'name': 'Plomería'},
        {'id': 'c2', 'name': 'Electricidad'},
      ],
      'correlationId': 'x',
    });

    final filas = await datasource().listarCategoriasTenant();

    expect(filas, [
      {'id': 'c1', 'nombre': 'Plomería'},
      {'id': 'c2', 'nombre': 'Electricidad'},
    ]);
    final r = peticiones.single;
    expect(r.method, 'GET');
    expect(
      r.url.toString(),
      'http://gateway.local/api/v1/core/profiles/me/categories/available',
    );
    expect(r.headers['Authorization'], 'Bearer jwt-aliado');
  });

  test('obtiene los ids del aliado', () async {
    responder = (_) => json({
      'categoryIds': ['c1', 'c2'],
      'categories': ['c1', 'c2'],
      'correlationId': 'x',
    });

    expect(await datasource().obtenerMisCategorias(), ['c1', 'c2']);
    expect(peticiones.single.url.path, '/api/v1/core/profiles/me/categories');
  });

  test('guarda con PUT y solo envía los ids: nunca tenant ni aliado', () async {
    responder = (_) => json({
      'categoryIds': ['c2'],
      'correlationId': 'x',
    });

    final guardadas = await datasource().guardarMisCategorias(['c2']);

    expect(guardadas, ['c2']);
    final r = peticiones.single;
    expect(r.method, 'PUT');
    expect(r.url.path, '/api/v1/core/profiles/me/categories');
    expect(jsonDecode(r.body), {
      'categoryIds': ['c2'],
    });
    expect(r.url.host, 'gateway.local');
  });

  test(
    'una respuesta sin la lista esperada es un error, no un conjunto vacío',
    () async {
      responder = (_) => json({'mensaje': 'hola'});
      final ds = datasource();
      await expectLater(ds.obtenerMisCategorias(), throwsA(anything));
      await expectLater(ds.listarCategoriasTenant(), throwsA(anything));
      await expectLater(ds.guardarMisCategorias(['c1']), throwsA(anything));
    },
  );

  group('el repositorio traduce el code que devuelve Core', () {
    Future<CategoriesFailure> guardarCon(
      int status,
      Map<String, dynamic> cuerpo,
    ) async {
      responder = (_) => json(cuerpo, status);
      final repo = CategoriesRepositoryImpl(remoteDataSource: datasource());
      try {
        await repo.saveSelectedCategories({'c1'});
      } on CategoriesFailure catch (f) {
        return f;
      }
      fail('debía lanzar CategoriesFailure');
    }

    test('422 MANI-CAT-422C → categoriaNoDisponible', () async {
      final f = await guardarCon(422, {
        'error': 'MANI-CAT-422C: categoría no disponible',
        'code': 'MANI-CAT-422C',
        'correlationId': 'x',
      });
      expect(f.tipo, CategoriesErrorTipo.categoriaNoDisponible);
    });

    test('422 MANI-CAT-422V → seleccionVacia', () async {
      final f = await guardarCon(422, {
        'error': 'MANI-CAT-422V: selecciona al menos una categoría',
        'code': 'MANI-CAT-422V',
        'correlationId': 'x',
      });
      expect(f.tipo, CategoriesErrorTipo.seleccionVacia);
    });

    test('403 MANI-CAT-403 y 403 sin code → noEsAliado', () async {
      expect(
        (await guardarCon(403, {'error': 'x', 'code': 'MANI-CAT-403'})).tipo,
        CategoriesErrorTipo.noEsAliado,
      );
      expect(
        (await guardarCon(403, {'error': 'x'})).tipo,
        CategoriesErrorTipo.noEsAliado,
      );
    });

    test('401 → sinSesion; 500 → desconocido', () async {
      expect(
        (await guardarCon(401, {'error': 'x'})).tipo,
        CategoriesErrorTipo.sinSesion,
      );
      expect(
        (await guardarCon(500, {'error': 'x'})).tipo,
        CategoriesErrorTipo.desconocido,
      );
    });

    test('sin red → sinConexion', () async {
      final repo = CategoriesRepositoryImpl(
        remoteDataSource: GatewayCategoriesDataSource(
          GatewayClient(
            baseUrl: 'http://gateway.local',
            tokenProvider: () async => 'jwt',
            maxRetries: 0,
            httpClient: MockClient(
              (_) async => throw http.ClientException('x'),
            ),
          ),
        ),
      );
      await expectLater(
        repo.getSelectedCategoryIds(),
        throwsA(
          isA<CategoriesFailure>().having(
            (f) => f.tipo,
            'tipo',
            CategoriesErrorTipo.sinConexion,
          ),
        ),
      );
    });
  });
}
