import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/coverage/data/datasources/cobertura_remote_datasource.dart';
import 'package:mani/features/profiles/coverage/data/repositories/cobertura_repository_impl.dart';
import 'package:mani/features/profiles/coverage/domain/failures/cobertura_failure.dart';

/// SCRUM-1380: la cobertura del aliado sale solo por el API Gateway hacia Core
/// Node. Las zonas vienen de `GET /catalog/zones` y la cobertura propia de
/// `/profiles/me/coverage`; ninguna petición va a las RPC de Supabase.
void main() {
  late List<http.Request> peticiones;
  late Map<String, http.Response Function(http.Request)> rutas;
  var ahora = DateTime(2026, 10, 27, 12);

  http.Response json(Object cuerpo, [int status = 200]) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> zona(
    String id,
    String name,
    String level, {
    String? parentId,
    bool active = true,
  }) => {
    'id': id,
    'name': name,
    'level': level,
    'parentId': parentId,
    'active': active,
    'selectable': active,
  };

  final catalogo = [
    zona('bog', 'Bogotá', 'CIUDAD'),
    zona('med', 'Medellín', 'CIUDAD'),
    zona('chap', 'Chapinero', 'LOCALIDAD', parentId: 'bog'),
    zona('usa', 'Usaquén', 'LOCALIDAD', parentId: 'bog', active: false),
    zona('rosales', 'El Rosal', 'BARRIO', parentId: 'chap'),
    zona('pob', 'El Poblado', 'LOCALIDAD', parentId: 'med'),
    zona('rosalia', 'La Rosalía', 'BARRIO', parentId: 'pob'),
  ];

  GatewayCoberturaDataSource datasource() => GatewayCoberturaDataSource(
    GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-aliado',
      correlationId: () => 'corr-test',
      maxRetries: 0,
      httpClient: MockClient((r) async {
        peticiones.add(r);
        final h = rutas['${r.method} ${r.url.path}'];
        return h == null ? json({'error': 'sin ruta'}, 404) : h(r);
      }),
    ),
    ahora: () => ahora,
  );

  int pedidasDelCatalogo() =>
      peticiones.where((r) => r.url.path.endsWith('/catalog/zones')).length;

  setUp(() {
    peticiones = [];
    ahora = DateTime(2026, 10, 27, 12);
    rutas = {
      'GET /api/v1/core/catalog/zones': (_) =>
          json({'zones': catalogo, 'tree': [], 'inconsistencies': []}),
    };
  });

  test(
    'listarZonas(null) devuelve las ciudades activas con tiene_hijas',
    () async {
      final filas = await datasource().listarZonas(null);

      expect(filas.map((f) => f['id']), ['bog', 'med']);
      expect(filas.first, {
        'id': 'bog',
        'nombre': 'Bogotá',
        'nivel': 'CIUDAD',
        'zona_padre_id': null,
        'ancestros': <String>[],
        'tiene_hijas': true,
        'estado': 'activa',
      });
      final r = peticiones.single;
      expect(r.headers['Authorization'], 'Bearer jwt-aliado');
      expect(r.url.host, 'gateway.local');
    },
  );

  test(
    'listarZonas(padre) devuelve solo las hijas activas, con sus ancestros',
    () async {
      final filas = await datasource().listarZonas('bog');

      expect(filas.map((f) => f['id']), [
        'chap',
      ], reason: 'Usaquén está inactiva');
      expect(filas.single['ancestros'], ['bog']);
      expect(filas.single['tiene_hijas'], isTrue);
      expect((await datasource().listarZonas('chap')).single['ancestros'], [
        'chap',
        'bog',
      ]);
    },
  );

  test(
    'el catálogo se descarga una vez y se renueva pasados 10 minutos',
    () async {
      final ds = datasource();
      await ds.listarZonas(null);
      await ds.listarZonas('bog');
      await ds.buscarZonas('bog', 'rosal');
      expect(pedidasDelCatalogo(), 1);

      ahora = ahora.add(const Duration(minutes: 11));
      await ds.listarZonas(null);
      expect(pedidasDelCatalogo(), 2);
    },
  );

  test(
    'buscarZonas busca dentro de la ciudad, sin tildes ni mayúsculas',
    () async {
      final ds = datasource();

      expect((await ds.buscarZonas('bog', 'ROSAL')).map((f) => f['id']), [
        'rosales',
      ]);
      expect((await ds.buscarZonas('med', 'rosalia')).map((f) => f['id']), [
        'rosalia',
      ]);
      expect(await ds.buscarZonas('bog', 'usaquen'), isEmpty);
      expect(await ds.buscarZonas('bog', '  '), isEmpty);
    },
  );

  test(
    'obtenerMiCobertura arma las filas con ancestros y marca la zona desactivada',
    () async {
      rutas['GET /api/v1/core/profiles/me/coverage'] = (_) => json({
        'zoneIds': ['rosales', 'usa'],
        'zones': [
          {
            'id': 'rosales',
            'name': 'El Rosal',
            'level': 'BARRIO',
            'parentId': 'chap',
            'active': true,
          },
          {
            'id': 'usa',
            'name': 'Usaquén',
            'level': 'LOCALIDAD',
            'parentId': 'bog',
            'active': false,
          },
        ],
        'correlationId': 'x',
      });

      final filas = await datasource().obtenerMiCobertura();

      expect(filas.map((f) => [f['id'], f['estado']]), [
        ['rosales', 'activa'],
        ['usa', 'inactiva'],
      ]);
      expect(filas.first['ancestros'], ['chap', 'bog']);
    },
  );

  test('sin cobertura declarada no se descarga el catálogo', () async {
    rutas['GET /api/v1/core/profiles/me/coverage'] = (_) =>
        json({'zoneIds': [], 'zones': [], 'correlationId': 'x'});

    expect(await datasource().obtenerMiCobertura(), isEmpty);
    expect(pedidasDelCatalogo(), 0);
  });

  test(
    'declararCobertura envía PUT con solo los ids de zona y devuelve los guardados',
    () async {
      rutas['PUT /api/v1/core/profiles/me/coverage'] = (_) => json({
        'zoneIds': ['chap'],
        'zones': [],
        'correlationId': 'x',
      });

      final filas = await datasource().declararCobertura(['chap']);

      expect(filas, [
        {'zona_id': 'chap'},
      ]);
      final r = peticiones.single;
      expect(r.method, 'PUT');
      expect(jsonDecode(r.body), {
        'zoneIds': ['chap'],
      });
    },
  );

  group('el repositorio traduce el code que devuelve Core', () {
    Future<CoberturaFailure> declararCon(
      int status,
      Map<String, dynamic> cuerpo,
    ) async {
      rutas['PUT /api/v1/core/profiles/me/coverage'] = (_) =>
          json(cuerpo, status);
      final repo = CoberturaRepositoryImpl(datasource());
      try {
        await repo.declararCobertura({'chap'});
      } on CoberturaFailure catch (f) {
        return f;
      }
      fail('debía lanzar CoberturaFailure');
    }

    test('cada código MANI-COB-* llega a su tipo', () async {
      const esperados = {
        'MANI-COB-403R': CoberturaErrorTipo.aliadoRechazado,
        'MANI-COB-403': CoberturaErrorTipo.noEsAliado,
        'MANI-COB-422V': CoberturaErrorTipo.seleccionVacia,
        'MANI-COB-422L': CoberturaErrorTipo.limiteExcedido,
        'MANI-COB-422Z': CoberturaErrorTipo.zonaInvalida,
      };
      for (final e in esperados.entries) {
        final status = e.key.startsWith('MANI-COB-403') ? 403 : 422;
        final f = await declararCon(status, {
          'error': '${e.key}: texto',
          'code': e.key,
          'correlationId': 'x',
        });
        expect(f.tipo, e.value, reason: e.key);
      }
    });

    test(
      '401 → sinSesion; 403 sin code → noEsAliado; 500 → desconocido',
      () async {
        expect(
          (await declararCon(401, {'error': 'x'})).tipo,
          CoberturaErrorTipo.sinSesion,
        );
        expect(
          (await declararCon(403, {'error': 'x'})).tipo,
          CoberturaErrorTipo.noEsAliado,
        );
        expect(
          (await declararCon(500, {'error': 'x'})).tipo,
          CoberturaErrorTipo.desconocido,
        );
      },
    );
  });
}
