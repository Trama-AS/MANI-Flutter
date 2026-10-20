import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/services/categories/data/datasources/categorias_remote_datasource.dart';
import 'package:mani/features/services/categories/data/repositories/categorias_repository_impl.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/entities/nueva_categoria.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';

/// US-03.1.2 (SCRUM-858): la gestión de categorías sale solo por el API
/// Gateway hacia Core Node; ninguna petición va a las RPC de Supabase
/// (ADR-0022).
void main() {
  late List<http.Request> peticiones;
  late http.Response Function(http.Request) responder;

  http.Response json(Object cuerpo, [int status = 200]) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> categoria({
    String id = 'cat-1',
    String name = 'Plomería',
    bool active = true,
    int alliesCount = 2,
  }) => {
    'id': id,
    'name': name,
    'active': active,
    'description': '',
    'tenantId': 't-1',
    'flujoOperativo': 'COTIZACION_PREVIA',
    'createdAt': '2026-10-01T12:00:00.000Z',
    'alliesCount': alliesCount,
  };

  CategoriasRemoteDataSource datasource() => GatewayCategoriasDataSource(
    GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-admin',
      correlationId: () => 'corr-test',
      maxRetries: 0,
      httpClient: MockClient((r) async {
        peticiones.add(r);
        return responder(r);
      }),
    ),
  );

  CategoriasRepositoryImpl repositorio() => CategoriasRepositoryImpl(
    datasource(),
    logger: StructuredLogger(canal: 'test', sink: (_) {}),
  );

  setUp(() {
    peticiones = [];
    responder = (_) => json({'categories': <Object>[]});
  });

  test('listar: GET al Gateway y mapea alliesCount y createdAt', () async {
    responder = (_) => json({
      'categories': [
        categoria(alliesCount: 3),
        categoria(id: 'cat-2', name: 'Cerrajería', active: false),
      ],
    });

    final lista = await repositorio().listar();

    expect(peticiones.single.method, 'GET');
    expect(
      peticiones.single.url.toString(),
      'http://gateway.local/api/v1/core/catalog/categories',
    );
    expect(peticiones.single.headers['Authorization'], 'Bearer jwt-admin');
    expect(peticiones.single.headers['X-Correlation-ID'], 'corr-test');
    expect(lista.first.aliadosAsociados, 3);
    expect(lista.first.fechaCreacion?.toUtc(), DateTime.utc(2026, 10, 1, 12));
    expect(lista.last.activa, isFalse);
  });

  test('crear activa: un solo POST con name y flujoOperativo', () async {
    responder = (_) => json({'category': categoria(alliesCount: 0)}, 201);

    final creada = await repositorio().crear(
      NuevaCategoria.crear(
        nombre: 'Plomería',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: true,
      ),
    );

    expect(peticiones, hasLength(1));
    expect(peticiones.single.method, 'POST');
    expect(jsonDecode(peticiones.single.body), {
      'name': 'Plomería',
      'flujoOperativo': 'COTIZACION_PREVIA',
    });
    expect(creada.activa, isTrue);
  });

  test('crear oculta: POST y luego PATCH deactivate de la nueva', () async {
    responder = (r) => r.method == 'POST'
        ? json({'category': categoria(id: 'nueva')}, 201)
        : json({'category': categoria(id: 'nueva', active: false)});

    final creada = await repositorio().crear(
      NuevaCategoria.crear(
        nombre: 'Plomería',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: false,
      ),
    );

    expect(peticiones.map((r) => '${r.method} ${r.url.path}'), [
      'POST /api/v1/core/catalog/categories',
      'PATCH /api/v1/core/catalog/categories/nueva/deactivate',
    ]);
    expect(creada.activa, isFalse);
  });

  test(
    'crear oculta: si falla el PATCH devuelve el estado real (activa)',
    () async {
      responder = (r) => r.method == 'POST'
          ? json({'category': categoria(id: 'nueva')}, 201)
          : json({'error': 'caído'}, 503);

      final creada = await repositorio().crear(
        NuevaCategoria.crear(
          nombre: 'Plomería',
          flujo: FlujoOperativo.cotizacionPrevia,
          activa: false,
        ),
      );

      expect(creada.activa, isTrue);
    },
  );

  test(
    'cambiarEstado: PATCH deactivate y conserva el conteo de aliados',
    () async {
      responder = (_) => json({'category': categoria(active: false)});

      final c = await repositorio().cambiarEstado(
        categoriaId: 'cat-1',
        activa: false,
      );

      expect(peticiones.single.method, 'PATCH');
      expect(
        peticiones.single.url.path,
        '/api/v1/core/catalog/categories/cat-1/deactivate',
      );
      expect(c.activa, isFalse);
      expect(c.aliadosAsociados, 2);
    },
  );

  test('cambiarEstado: PATCH activate', () async {
    responder = (_) => json({'category': categoria()});

    await repositorio().cambiarEstado(categoriaId: 'cat-1', activa: true);

    expect(
      peticiones.single.url.path,
      '/api/v1/core/catalog/categories/cat-1/activate',
    );
  });

  group('errores de Core', () {
    Future<CategoriaErrorTipo> tipoDe(http.Response r) async {
      responder = (_) => r;
      try {
        await repositorio().crear(
          NuevaCategoria.crear(
            nombre: 'Plomería',
            flujo: FlujoOperativo.tarifaEstandar,
            activa: true,
          ),
        );
      } on CategoriaFailure catch (f) {
        return f.tipo;
      }
      fail('se esperaba CategoriaFailure');
    }

    test('Rules rechaza el nombre (violations MANI-CAT-422N)', () async {
      expect(
        await tipoDe(
          json({
            'error': 'La categoría no cumple las reglas de negocio: nombre',
            'code': 'VALIDATION_ERROR',
            'violations': [
              {'code': 'MANI-CAT-422N', 'field': 'name', 'message': 'nombre'},
            ],
          }, 400),
        ),
        CategoriaErrorTipo.nombreInvalido,
      );
    });

    test('Rules rechaza el flujo (violations MANI-CAT-422F)', () async {
      expect(
        await tipoDe(
          json({
            'error': 'La categoría no cumple las reglas de negocio',
            'code': 'VALIDATION_ERROR',
            'violations': [
              {'code': 'MANI-CAT-422F', 'field': 'flujoOperativo'},
            ],
          }, 400),
        ),
        CategoriaErrorTipo.flujoInvalido,
      );
    });

    test('409 CATEGORY_NAME_ALREADY_EXISTS → nombreDuplicado', () async {
      expect(
        await tipoDe(
          json({
            'error': 'Ya existe',
            'code': 'CATEGORY_NAME_ALREADY_EXISTS',
          }, 409),
        ),
        CategoriaErrorTipo.nombreDuplicado,
      );
    });

    test('403 → noAutorizado', () async {
      expect(
        await tipoDe(json({'error': 'FORBIDDEN'}, 403)),
        CategoriaErrorTipo.noAutorizado,
      );
    });
  });

  test('ninguna operación llama RPC de Supabase', () async {
    responder = (r) => switch (r.method) {
      'GET' => json({'categories': <Object>[]}),
      'POST' => json({'category': categoria()}, 201),
      _ => json({'category': categoria(active: false)}),
    };
    final repo = repositorio();

    await repo.listar();
    await repo.crear(
      NuevaCategoria.crear(
        nombre: 'Plomería',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: false,
      ),
    );
    await repo.cambiarEstado(categoriaId: 'cat-1', activa: true);

    expect(peticiones.map((r) => r.url.host).toSet(), {'gateway.local'});
    expect(peticiones.any((r) => r.url.path.contains('/rpc/')), isFalse);
  });
}
