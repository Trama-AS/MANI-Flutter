import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

GatewayClient _cliente(
  MockClientHandler handler, {
  String? token = 'jwt-abc',
  String baseUrl = 'http://gateway.local',
  int maxRetries = 3,
  Duration initialRetryDelay = Duration.zero,
  TokenRefreshCallback? onTokenExpired,
  StructuredLogger? logger,
}) => GatewayClient(
  baseUrl: baseUrl,
  tokenProvider: () async => token,
  httpClient: MockClient(handler),
  correlationId: () => 'corr-1',
  maxRetries: maxRetries,
  initialRetryDelay: initialRetryDelay,
  onTokenExpired: onTokenExpired,
  logger: logger,
);

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('cabeceras', () {
    test('envía Bearer y X-Correlation-ID a la URL del Gateway', () async {
      late http.Request recibida;
      final c = _cliente((r) async {
        recibida = r;
        return _json(200, {'ok': true});
      });

      final res = await c.postJson('/api/v1/core/ping', {'a': 1});

      expect(res, {'ok': true});
      expect(recibida.url.toString(), 'http://gateway.local/api/v1/core/ping');
      expect(recibida.headers['Authorization'], 'Bearer jwt-abc');
      expect(recibida.headers['X-Correlation-ID'], 'corr-1');
      expect(jsonDecode(recibida.body), {'a': 1});
    });

    test('sin sesión no envía Authorization', () async {
      late http.Request recibida;
      final c = _cliente((r) async {
        recibida = r;
        return _json(201, {});
      }, token: null);

      await c.postJson('/x', {});

      expect(recibida.headers.containsKey('Authorization'), isFalse);
    });

    test('respeta el path base del Gateway', () async {
      late Uri url;
      final c = _cliente((r) async {
        url = r.url;
        return _json(200, {});
      }, baseUrl: 'https://qa.mani.co/gw/');

      await c.postJson('/api/v1/core/x', {});

      expect(url.toString(), 'https://qa.mani.co/gw/api/v1/core/x');
    });
  });

  group('métodos HTTP y queryParameters', () {
    test(
      'get envía verbo GET y codifica queryParameters correctamente',
      () async {
        late http.Request recibida;
        final c = _cliente((r) async {
          recibida = r;
          return _json(200, {'items': []});
        });

        final res = await c.get(
          '/api/v1/core/servicios',
          queryParameters: {'tenant': 'cali', 'page': 1, 'activo': true},
          headers: {'X-Tenant-Slug': 'cali'},
        );

        expect(res, {'items': []});
        expect(recibida.method, 'GET');
        expect(recibida.headers['X-Tenant-Slug'], 'cali');
        expect(recibida.url.path, '/api/v1/core/servicios');
        expect(recibida.url.queryParameters, {
          'tenant': 'cali',
          'page': '1',
          'activo': 'true',
        });
      },
    );

    test('put envía verbo PUT con cuerpo JSON', () async {
      late http.Request recibida;
      final c = _cliente((r) async {
        recibida = r;
        return _json(200, {'actualizado': true});
      });

      final res = await c.put(
        '/api/v1/core/aliados/123',
        {'nombre': 'Aliado Actualizado'},
        headers: {'X-Custom': 'val'},
      );

      expect(res, {'actualizado': true});
      expect(recibida.method, 'PUT');
      expect(recibida.headers['X-Custom'], 'val');
      expect(recibida.headers['content-type'], contains('application/json'));
      expect(jsonDecode(recibida.body), {'nombre': 'Aliado Actualizado'});
    });

    test('patch envía verbo PATCH con cuerpo JSON', () async {
      late http.Request recibida;
      final c = _cliente((r) async {
        recibida = r;
        return _json(200, {'parcheado': true});
      });

      final res = await c.patch('/api/v1/core/aliados/123', {'activo': false});

      expect(res, {'parcheado': true});
      expect(recibida.method, 'PATCH');
      expect(jsonDecode(recibida.body), {'activo': false});
    });

    test('delete envía verbo DELETE y soporta queryParameters', () async {
      late http.Request recibida;
      final c = _cliente((r) async {
        recibida = r;
        return _json(200, {'eliminado': true});
      });

      final res = await c.delete(
        '/api/v1/core/aliados/123',
        queryParameters: {'motivo': 'baja'},
      );

      expect(res, {'eliminado': true});
      expect(recibida.method, 'DELETE');
      expect(recibida.url.queryParameters, {'motivo': 'baja'});
    });
  });

  test('multipart incluye campos y archivos', () async {
    late http.Request recibida;
    final c = _cliente((r) async {
      recibida = r;
      return _json(201, {'id': '1'});
    });

    await c.postMultipart(
      '/up',
      campos: {'nit': '900'},
      archivos: [
        ArchivoMultipart(
          campo: 'camara_comercio',
          nombre: 'camara.pdf',
          bytes: Uint8List.fromList(utf8.encode('PDF-CAMARA')),
        ),
      ],
    );

    expect(recibida.headers['content-type'], startsWith('multipart/form-data'));
    final cuerpo = utf8.decode(recibida.bodyBytes);
    expect(cuerpo, contains('name="nit"'));
    expect(cuerpo, contains('name="camara_comercio"; filename="camara.pdf"'));
    expect(cuerpo, contains('PDF-CAMARA'));
  });

  group('reintentos y backoff exponencial (idempotencia)', () {
    test('GET reintenta ante 502/503/504 y tiene éxito en reintento', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        if (llamadas == 1) return _json(502, {'error': 'bad gateway'});
        if (llamadas == 2) return _json(503, {'error': 'service unavailable'});
        return _json(200, {'ok': true});
      });

      final res = await c.get('/api/v1/core/ping');

      expect(res, {'ok': true});
      expect(llamadas, 3);
    });

    test('GET reintenta ante ClientException de red y tiene éxito', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        if (llamadas == 1) throw http.ClientException('Network down');
        return _json(200, {'ok': true});
      });

      final res = await c.get('/api/v1/core/ping');

      expect(res, {'ok': true});
      expect(llamadas, 2);
    });

    test(
      'GET agota reintentos ante 503 continuo y lanza GatewayException',
      () async {
        int llamadas = 0;
        final c = _cliente((_) async {
          llamadas++;
          return _json(503, {'error': 'unavailable'});
        }, maxRetries: 2);

        await expectLater(
          c.get('/api/v1/core/ping'),
          throwsA(
            isA<GatewayException>().having((e) => e.statusCode, 'status', 503),
          ),
        );
        // 1 inicial + 2 reintentos = 3 llamadas en total
        expect(llamadas, 3);
      },
    );

    test('petición con cabecera Idempotency-Key reintenta ante 504', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        if (llamadas == 1) return _json(504, {'error': 'gateway timeout'});
        return _json(201, {'creado': true});
      });

      final res = await c.postJson(
        '/api/v1/core/operacion',
        {'x': 1},
        headers: {'Idempotency-Key': 'idem-123'},
      );

      expect(res, {'creado': true});
      expect(llamadas, 2);
    });

    test('POST sin clave de idempotencia NO reintenta ante 502', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        return _json(502, {'error': 'upstream failure'});
      });

      await expectLater(
        c.postJson('/api/v1/core/operacion', {'x': 1}),
        throwsA(
          isA<GatewayException>().having((e) => e.statusCode, 'status', 502),
        ),
      );
      // Operación no idempotente no debe reintentarse
      expect(llamadas, 1);
    });

    test(
      'POST sin clave de idempotencia NO reintenta ante fallo de red',
      () async {
        int llamadas = 0;
        final c = _cliente((_) async {
          llamadas++;
          throw http.ClientException('Conexión cerrada');
        });

        await expectLater(
          c.postJson('/api/v1/core/operacion', {'x': 1}),
          throwsA(
            isA<GatewayException>().having(
              (e) => e.statusCode,
              'status',
              isNull,
            ),
          ),
        );
        expect(llamadas, 1);
      },
    );

    test('GET ante 500 (Internal Server Error) no se reintenta', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        return _json(500, {'error': 'bug interno'});
      });

      await expectLater(
        c.get('/api/v1/core/ping'),
        throwsA(
          isA<GatewayException>().having((e) => e.statusCode, 'status', 500),
        ),
      );
      expect(llamadas, 1);
    });

    test('GET ante 400 Bad Request no se reintenta', () async {
      int llamadas = 0;
      final c = _cliente((_) async {
        llamadas++;
        return _json(400, {'message': 'parámetro inválido'});
      });

      await expectLater(
        c.get('/api/v1/core/ping'),
        throwsA(
          isA<GatewayException>().having((e) => e.statusCode, 'status', 400),
        ),
      );
      expect(llamadas, 1);
    });
  });

  group('manejo de 401 y refresco de sesión (onTokenExpired)', () {
    test(
      '401 con onTokenExpired exitoso refresca sesión y reintenta',
      () async {
        int llamadas = 0;
        String tokenActual = 'token-expirado';
        bool callbackEjecutado = false;

        final c = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => tokenActual,
          httpClient: MockClient((request) async {
            llamadas++;
            if (request.headers['Authorization'] == 'Bearer token-expirado') {
              return _json(401, {'error': 'jwt expired'});
            }
            return _json(200, {
              'ok': true,
              'auth': request.headers['Authorization'],
            });
          }),
          correlationId: () => 'corr-1',
          initialRetryDelay: Duration.zero,
          onTokenExpired: () async {
            callbackEjecutado = true;
            tokenActual = 'token-nuevo-refrescado';
            return true;
          },
        );

        final res = await c.get('/api/v1/core/perfil');

        expect(callbackEjecutado, isTrue);
        expect(llamadas, 2);
        expect(res['ok'], isTrue);
        expect(res['auth'], 'Bearer token-nuevo-refrescado');
      },
    );

    test(
      '401 con onTokenExpired que devuelve false lanza GatewayException',
      () async {
        int llamadas = 0;
        final c = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'token-invalido',
          httpClient: MockClient((_) async {
            llamadas++;
            return _json(401, {'error': 'refresh token failed'});
          }),
          correlationId: () => 'corr-1',
          initialRetryDelay: Duration.zero,
          onTokenExpired: () async => false,
        );

        await expectLater(
          c.get('/api/v1/core/perfil'),
          throwsA(
            isA<GatewayException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(llamadas, 1);
      },
    );

    test(
      '401 que tras refresco sigue devolviendo 401 no produce bucle infinito',
      () async {
        int llamadas = 0;
        int refrescos = 0;
        final c = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'token-siempre-invalido',
          httpClient: MockClient((_) async {
            llamadas++;
            return _json(401, {'error': 'unauthorized'});
          }),
          correlationId: () => 'corr-1',
          initialRetryDelay: Duration.zero,
          onTokenExpired: () async {
            refrescos++;
            return true;
          },
        );

        await expectLater(
          c.get('/api/v1/core/perfil'),
          throwsA(
            isA<GatewayException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(refrescos, 1);
        expect(llamadas, 2);
      },
    );
  });

  group('structured logging', () {
    test('emite logs estructurados con correlationId como traceId', () async {
      final logs = <Map<String, dynamic>>[];
      final logger = StructuredLogger(
        canal: 'test_canal',
        sink: (linea) => logs.add(jsonDecode(linea) as Map<String, dynamic>),
      );

      final c = _cliente((_) async => _json(200, {'ok': true}), logger: logger);

      await c.get('/api/v1/core/ping');

      expect(logs, isNotEmpty);
      expect(logs.any((l) => l['trace_id'] == 'corr-1'), isTrue);
      expect(
        logs.any((l) => l['message'].toString().contains('HTTP GET')),
        isTrue,
      );
    });
  });

  group('errores (CA-4)', () {
    Future<GatewayException> fallo(http.Response r) async {
      final c = _cliente((_) async => r);
      try {
        await c.postJson('/x', {});
      } on GatewayException catch (e) {
        return e;
      }
      fail('debía lanzar GatewayException');
    }

    test('400 usa el detalle del servicio', () async {
      final e = await fallo(_json(400, {'message': 'Falta el campo nit'}));
      expect(e.statusCode, 400);
      expect(e.message, 'Falta el campo nit');
      expect(e.correlationId, 'corr-1');
      expect(e.isConflict, isFalse);
      expect(e.isUnauthorized, isFalse);
      expect(e.isForbidden, isFalse);
      expect(e.isConnectionError, isFalse);
    });

    test('401 pide iniciar sesión y tiene helper isUnauthorized', () async {
      final e = await fallo(_json(401, {'error': 'jwt expired'}));
      expect(e.message, contains('Inicia sesión'));
      expect(e.isUnauthorized, isTrue);
    });

    test('403 tiene helper isForbidden', () async {
      final e = await fallo(_json(403, {'error': 'forbidden'}));
      expect(e.isForbidden, isTrue);
      expect(e.message, contains('permiso'));
    });

    test(
      '409 sin detalle da un mensaje de duplicado y tiene helper isConflict',
      () async {
        final e = await fallo(http.Response('', 409));
        expect(e.message, 'Ya existe un registro con estos datos.');
        expect(e.isConflict, isTrue);
      },
    );

    test('5xx no filtra el error interno', () async {
      final e = await fallo(_json(502, {'message': 'upstream core-service'}));
      expect(e.statusCode, 502);
      expect(e.message, isNot(contains('upstream')));
      expect(e.message, contains('no está disponible'));
    });

    test('cuerpo no JSON no rompe el manejo de errores', () async {
      final e = await fallo(http.Response('<html>Bad Gateway</html>', 502));
      expect(e.statusCode, 502);
    });

    test(
      'fallo de red se traduce sin status y tiene helper isConnectionError',
      () async {
        final c = _cliente((_) async => throw http.ClientException('offline'));
        await expectLater(
          c.postJson('/x', {}),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.statusCode, 'statusCode', isNull)
                .having((e) => e.isConnectionError, 'isConnectionError', isTrue)
                .having((e) => e.message, 'message', contains('conectar')),
          ),
        );
      },
    );

    test('timeout se traduce sin quedarse esperando', () async {
      final c = GatewayClient(
        baseUrl: 'http://gateway.local',
        tokenProvider: () async => null,
        httpClient: MockClient(
          (_) =>
              Future.delayed(const Duration(seconds: 5), () => _json(200, {})),
        ),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        c.postJson('/x', {}),
        throwsA(
          isA<GatewayException>().having(
            (e) => e.message,
            'message',
            contains('tardó'),
          ),
        ),
      );
    });
  });
}
