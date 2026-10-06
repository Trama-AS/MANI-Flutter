import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

GatewayClient _cliente(
  MockClientHandler handler, {
  String? token = 'jwt-abc',
  String baseUrl = 'http://gateway.local',
}) => GatewayClient(
  baseUrl: baseUrl,
  tokenProvider: () async => token,
  httpClient: MockClient(handler),
  correlationId: () => 'corr-1',
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
    });

    test('401 pide iniciar sesión', () async {
      final e = await fallo(_json(401, {'error': 'jwt expired'}));
      expect(e.message, contains('Inicia sesión'));
    });

    test('409 sin detalle da un mensaje de duplicado', () async {
      final e = await fallo(http.Response('', 409));
      expect(e.message, 'Ya existe un registro con estos datos.');
    });

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

    test('fallo de red se traduce sin status', () async {
      final c = _cliente((_) async => throw http.ClientException('offline'));
      await expectLater(
        c.postJson('/x', {}),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.message, 'message', contains('conectar')),
        ),
      );
    });

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
