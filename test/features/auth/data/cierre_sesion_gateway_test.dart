import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// HU-M02-03: al cerrar sesión se avisa a Core para la auditoría, y el cierre
/// nunca depende de que ese aviso funcione.
void main() {
  late List<http.Request> alGateway;
  late List<http.BaseRequest> aSupabase;
  late http.Response Function(http.Request) responder;

  AuthRemoteDataSource datasource() {
    final supabase = SupabaseClient(
      'http://supabase.local',
      'anon-key',
      httpClient: MockClient((r) async {
        aSupabase.add(r);
        return http.Response('{}', 204);
      }),
    );
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-de-prueba',
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return AuthRemoteDataSource(client: supabase, gateway: gateway);
  }

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => http.Response('', 204);
  });

  test('avisa a Core por el Gateway con el token de la sesión', () async {
    await datasource().signOut();

    expect(alGateway, hasLength(1));
    final r = alGateway.single;
    expect(r.method, 'POST');
    expect(
      r.url.toString(),
      'http://gateway.local${AuthRemoteDataSource.rutaCierreSesion}',
    );
    expect(AuthRemoteDataSource.rutaCierreSesion, '/api/v1/core/auth/logout');
    expect(r.headers['Authorization'], 'Bearer jwt-de-prueba');
  });

  test('si Core responde error, el cierre de sesión no falla', () async {
    for (final status in [401, 500, 503]) {
      alGateway = [];
      responder = (_) => http.Response('{"error":"x"}', status);
      await expectLater(
        datasource().signOut(),
        completes,
        reason: 'estado $status',
      );
    }
  });

  test('sin red hacia Core, el cierre de sesión no falla', () async {
    responder = (_) => throw http.ClientException('sin red');
    await expectLater(datasource().signOut(), completes);
  });
}
