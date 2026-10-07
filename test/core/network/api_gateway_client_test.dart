import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mani/core/network/api_gateway_client.dart';

class FakeHttpClient extends http.BaseClient {
  http.Request? lastRequest;
  int statusCode;
  String responseBody;
  Map<String, String> responseHeaders;

  FakeHttpClient({
    this.statusCode = 200,
    this.responseBody = '{"status":"OK"}',
    this.responseHeaders = const {'content-type': 'application/json'},
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastRequest = request;
    }
    final stream = Stream.value(utf8.encode(responseBody));
    return http.StreamedResponse(stream, statusCode, headers: responseHeaders);
  }
}

void main() {
  group('ApiGatewayClient Tests', () {
    test(
      'Adjunta encabezados requeridos X-Correlation-ID y Content-Type',
      () async {
        final fakeClient = FakeHttpClient(
          statusCode: 200,
          responseBody: '{"message":"success"}',
        );
        final client = ApiGatewayClient(
          baseUrl: 'http://gateway.test',
          httpClient: fakeClient,
        );

        final res = await client.get('/api/v1/core/health');

        expect(res['message'], 'success');
        expect(
          fakeClient.lastRequest?.headers['Content-Type'],
          contains('application/json'),
        );
        expect(fakeClient.lastRequest?.headers['X-Correlation-ID'], isNotEmpty);
      },
    );

    test(
      'Lanza ApiGatewayAuthException en respuesta HTTP 401 del Gateway',
      () async {
        final fakeClient = FakeHttpClient(
          statusCode: 401,
          responseBody:
              '{"error":"UNAUTHORIZED","message":"Token inválido o falta claim tenant_id"}',
        );
        final client = ApiGatewayClient(
          baseUrl: 'http://gateway.test',
          httpClient: fakeClient,
        );

        expect(
          () => client.get('/api/v1/core/profiles/me'),
          throwsA(
            isA<ApiGatewayAuthException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.error, 'error', 'UNAUTHORIZED'),
          ),
        );
      },
    );
  });
}
