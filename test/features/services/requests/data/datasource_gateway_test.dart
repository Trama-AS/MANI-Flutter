import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/requests/data/datasources/solicitudes_cliente_remote_datasource.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes.dart';

/// SCRUM-1072: crear la solicitud sale por el Gateway hacia Core en una sola
/// petición multipart; la app ya no llama a `crear_solicitud` ni sube fotos a
/// Storage (ADR-0027).
void main() {
  late List<http.Request> alGateway;
  late List<http.BaseRequest> aSupabase;
  late http.Response Function(http.Request) responder;

  SolicitudesClienteRemoteDataSource datasource({DateTime Function()? ahora}) {
    final supabase = SupabaseClient(
      'http://supabase.local',
      'anon-key',
      httpClient: MockClient((r) async {
        aSupabase.add(r);
        return http.Response('{}', 200);
      }),
    );
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-cliente',
      correlationId: () => 'corr-test',
      initialRetryDelay: Duration.zero,
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return SolicitudesClienteRemoteDataSourceImpl(
      supabase,
      gateway,
      ahora: ahora,
    );
  }

  final solicitudCore = {
    'id': 'sol-1',
    'estado': 'PENDIENTE',
    'categoriaId': 'cat-plo',
    'categoria': 'Plomería',
    'flujoOperativo': 'COTIZACION_PREVIA',
    'descripcion': descripcionValida,
    'sitioId': 'sitio-1',
    'direccion': 'Calle Colima 120',
    'zonaId': 'z-roma',
    'zona': 'Roma Norte',
    'zonaPadre': 'Cuauhtémoc',
    'fotos': 2,
    'createdAt': '2026-10-19T15:00:00.000Z',
  };

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => http.Response(
      jsonEncode({'solicitud': solicitudCore, 'correlationId': 'corr-test'}),
      201,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Future<Map<String, dynamic>> crear(
    SolicitudesClienteRemoteDataSource ds, {
    String? sitioId,
    String? direccion = 'Calle Colima 120',
    String? zonaId = 'z-roma',
  }) => ds.crear(
    categoriaId: 'cat-plo',
    descripcion: descripcionValida,
    fotos: [
      FotoAdjunta.crear(nombre: 'fuga.JPEG', bytes: pngMinimo),
      FotoAdjunta.crear(nombre: 'tubo.png', bytes: pngMinimo),
    ],
    claveIdempotencia: '00000000-0000-4000-8000-000000000001',
    sitioId: sitioId,
    direccion: direccion,
    zonaId: zonaId,
  );

  test('POST multipart a /api/v1/core/solicitudes con los campos del '
      'contrato, las fotos con su MIME y la clave de idempotencia', () async {
    final res = await crear(datasource());

    expect(aSupabase, isEmpty, reason: 'ni .rpc() ni .storage.from()');
    final r = alGateway.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'http://gateway.local/api/v1/core/solicitudes');
    expect(r.headers['Authorization'], 'Bearer jwt-cliente');
    expect(
      r.headers['Idempotency-Key'],
      '00000000-0000-4000-8000-000000000001',
    );
    final cuerpo = latin1.decode(r.bodyBytes);
    for (final campo in [
      'categoriaId',
      'descripcion',
      'claveIdempotencia',
      'direccion',
      'zonaId',
    ]) {
      expect(cuerpo, contains('name="$campo"'), reason: campo);
    }
    expect(cuerpo, isNot(contains('name="sitioId"')));
    expect(cuerpo, isNot(contains('tenant')), reason: 'el tenant va en el JWT');
    expect(cuerpo, contains('name="fotos"; filename="1.jpg"'));
    expect(cuerpo, contains('name="fotos"; filename="2.png"'));
    expect(cuerpo, contains('content-type: image/jpeg'));
    expect(cuerpo, contains('content-type: image/png'));

    expect(res, solicitudCore, reason: 'devuelve el objeto solicitud');
  });

  test('con sitio existente envía sitioId y no la dirección', () async {
    await crear(
      datasource(),
      sitioId: 'sitio-1',
      direccion: null,
      zonaId: null,
    );

    final cuerpo = latin1.decode(alGateway.single.bodyBytes);
    expect(cuerpo, contains('name="sitioId"'));
    expect(cuerpo, isNot(contains('name="direccion"')));
    expect(cuerpo, isNot(contains('name="zonaId"')));
  });

  test('el 422 de Core llega con su código MANI-SOL', () async {
    responder = (_) => http.Response(
      jsonEncode({
        'error': 'MANI-SOL-422Z: zona no disponible',
        'code': 'MANI-SOL-422Z',
      }),
      422,
    );

    await expectLater(
      crear(datasource()),
      throwsA(
        isA<GatewayException>()
            .having((e) => e.statusCode, 'status', 422)
            .having((e) => e.message, 'message', startsWith('MANI-SOL-422Z')),
      ),
    );
  });

  test('un 503 se reintenta: la clave hace la creación idempotente', () async {
    var n = 0;
    responder = (_) => ++n == 1
        ? http.Response('{"error":"Core no disponible"}', 503)
        : http.Response(
            jsonEncode({'solicitud': solicitudCore}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );

    final res = await crear(datasource());

    expect(alGateway, hasLength(2));
    expect(res['id'], 'sol-1');
  });

  test('una respuesta sin solicitud es un error', () async {
    responder = (_) => http.Response('{}', 201);

    await expectLater(crear(datasource()), throwsFormatException);
  });
  group('SCRUM-1465: categorías y sitios por Core, sin RPC', () {
    http.Response json(Object cuerpo, [int status = 200]) => http.Response(
      jsonEncode(cuerpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    test(
      'GET /api/v1/core/solicitudes/categorias sin ids del cliente',
      () async {
        responder = (_) => json({
          'categorias': [
            {
              'id': 'cat-plo',
              'nombre': 'Plomería',
              'flujoOperativo': 'COTIZACION_PREVIA',
            },
          ],
          'correlationId': 'corr-test',
        });

        final res = await datasource().listarCategorias();

        expect(alGateway.single.method, 'GET');
        expect(
          alGateway.single.url.path,
          '/api/v1/core/solicitudes/categorias',
        );
        expect(alGateway.single.url.query, isEmpty);
        expect(alGateway.single.headers['Authorization'], 'Bearer jwt-cliente');
        expect(res.single['flujoOperativo'], 'COTIZACION_PREVIA');
        expect(aSupabase, isEmpty);
      },
    );

    test(
      'GET /api/v1/core/solicitudes/sitios trae zona y zona padre',
      () async {
        responder = (_) => json({
          'sitios': [
            {
              'id': 'sitio-1',
              'nombre': 'Calle Colima 120',
              'direccion': 'Calle Colima 120',
              'zonaId': 'z-roma',
              'zona': 'Roma Norte',
              'zonaPadre': 'Cuauhtémoc',
            },
          ],
        });

        final res = await datasource().listarSitios();

        expect(alGateway.single.url.path, '/api/v1/core/solicitudes/sitios');
        expect(res.single['zonaPadre'], 'Cuauhtémoc');
        expect(aSupabase, isEmpty);
      },
    );

    test(
      'un 403 de Core llega como GatewayException, no como lista vacía',
      () async {
        responder = (_) => json({
          'error':
              'MANI-SOL-403C: solo un cliente activo puede publicar solicitudes',
          'code': 'MANI-SOL-403C',
        }, 403);

        await expectLater(
          datasource().listarSitios(),
          throwsA(
            isA<GatewayException>().having((e) => e.statusCode, 'status', 403),
          ),
        );
      },
    );

    test(
      'una respuesta sin la lista es un error, no una lista vacía',
      () async {
        responder = (_) => json({'correlationId': 'corr-test'});

        await expectLater(
          datasource().listarCategorias(),
          throwsFormatException,
        );
      },
    );
  });

  test(
    'avisar a los aliados: POST orchestrate a Dispatch con la solicitud y la clave',
    () async {
      var n = 0;
      responder = (_) => ++n == 1
          ? http.Response('{"code":"CORE_SERVICE_UNAVAILABLE"}', 503)
          : http.Response('{"notified":2}', 200);

      await datasource().avisarAliados('sol-1', clave: 'clave-1');

      final r = alGateway.last;
      expect(r.method, 'POST');
      expect(r.url.path, '/api/v1/dispatch/requests/orchestrate');
      expect(r.headers['Authorization'], 'Bearer jwt-cliente');
      expect(r.headers['Idempotency-Key'], 'clave-1');
      expect(jsonDecode(r.body), {'requestId': 'sol-1'});
      expect(alGateway, hasLength(2), reason: 'el 503 se reintenta');
      expect(aSupabase, isEmpty);
    },
  );

  group('SCRUM-1465: búsqueda de zonas en el catálogo de Core, sin RPC', () {
    Map<String, dynamic> zona(
      String id,
      String nombre,
      String nivel,
      String? padre, {
      bool activa = true,
    }) => {
      'id': id,
      'name': nombre,
      'level': nivel,
      'parentId': padre,
      'active': activa,
      'selectable': activa,
    };

    final catalogo = [
      zona('z-cdmx', 'Ciudad de México', 'CIUDAD', null),
      zona('z-cuau', 'Cuauhtémoc', 'LOCALIDAD', 'z-cdmx', activa: false),
      zona('z-roma', 'Roma Norte', 'BARRIO', 'z-cuau'),
      zona('z-romas', 'Roma Sur', 'BARRIO', 'z-cuau', activa: false),
      zona('z-condesa', 'Condesa', 'BARRIO', 'z-cuau'),
      zona('z-romero', 'Romero de Terreros', 'BARRIO', 'z-cdmx'),
    ];

    http.Response respuestaCatalogo([List<Map<String, dynamic>>? zonas]) =>
        http.Response(
          jsonEncode({
            'zones': zonas ?? catalogo,
            'tree': const [],
            'inconsistencies': const [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    test(
      'GET /api/v1/core/catalog/zones con el JWT y filtra como la RPC',
      () async {
        responder = (_) => respuestaCatalogo();

        final res = await datasource().buscarZonas('  ROM ');

        expect(alGateway.single.method, 'GET');
        expect(alGateway.single.url.path, '/api/v1/core/catalog/zones');
        expect(alGateway.single.url.query, isEmpty);
        expect(alGateway.single.headers['Authorization'], 'Bearer jwt-cliente');
        expect(aSupabase, isEmpty);
        // Sin la ciudad (no tiene padre), sin Roma Sur (inactiva) y ordenadas.
        expect(res, [
          {'id': 'z-roma', 'nombre': 'Roma Norte', 'zonaPadre': 'Cuauhtémoc'},
          {
            'id': 'z-romero',
            'nombre': 'Romero de Terreros',
            'zonaPadre': 'Ciudad de México',
          },
        ]);
      },
    );

    test('con menos de 2 caracteres no llama al Gateway', () async {
      expect(await datasource().buscarZonas(' r '), isEmpty);
      expect(alGateway, isEmpty);
    });

    test('devuelve como máximo 20 zonas', () async {
      responder = (_) => respuestaCatalogo([
        zona('z-cdmx', 'Ciudad de México', 'CIUDAD', null),
        for (var i = 10; i < 40; i++)
          zona('z-$i', 'Barrio $i', 'BARRIO', 'z-cdmx'),
      ]);

      final res = await datasource().buscarZonas('barrio');

      expect(res, hasLength(20));
      expect(res.first['nombre'], 'Barrio 10');
    });

    test('relee el catálogo solo cuando pasan 5 minutos', () async {
      var ahora = DateTime(2026, 10, 27, 10);
      responder = (_) => respuestaCatalogo();
      final ds = datasource(ahora: () => ahora);

      await ds.buscarZonas('roma');
      await ds.buscarZonas('condesa');
      expect(alGateway, hasLength(1));

      ahora = ahora.add(const Duration(minutes: 5));
      await ds.buscarZonas('roma');
      expect(alGateway, hasLength(2));
    });

    test(
      'un error de Core llega como GatewayException y no se guarda',
      () async {
        var n = 0;
        responder = (_) => ++n == 1
            ? http.Response(
                jsonEncode({
                  'error': 'Token inválido',
                  'code': 'TOKEN_INVALID',
                }),
                401,
              )
            : respuestaCatalogo();
        final ds = datasource();

        await expectLater(
          ds.buscarZonas('roma'),
          throwsA(
            isA<GatewayException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(await ds.buscarZonas('roma'), hasLength(1));
      },
    );

    test('una respuesta sin `zones` es un error, no una lista vacía', () async {
      responder = (_) => http.Response(jsonEncode({'tree': const []}), 200);

      await expectLater(
        datasource().buscarZonas('roma'),
        throwsFormatException,
      );
    });
  });
}
