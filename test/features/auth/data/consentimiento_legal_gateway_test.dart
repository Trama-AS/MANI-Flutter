import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SCRUM-856: el consentimiento se envía a Core por el Gateway después del registro.
/// Si falla, el registro no se revierte (la cuenta ya existe), pero el fallo queda en el log.
void main() {
  late List<http.Request> alGateway;
  late List<String> logs;

  AuthRemoteDataSource datasource(int statusConsentimiento) {
    final supabase = SupabaseClient(
      'http://supabase.local',
      'anon-key',
      httpClient: MockClient((r) async => http.Response('{}', 200)),
    );
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => null,
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return http.Response(
          jsonEncode({'ok': statusConsentimiento < 300}),
          statusConsentimiento,
        );
      }),
    );
    return AuthRemoteDataSource(
      client: supabase,
      gateway: gateway,
      logger: StructuredLogger(canal: 'test', sink: logs.add),
    );
  }

  setUp(() {
    alGateway = [];
    logs = [];
  });

  test(
    'envía POST /api/v1/core/legal/consents con el token de la sesión recién creada',
    () async {
      await datasource(201).registrarConsentimientoLegal(token: 'token-nuevo');

      expect(alGateway, hasLength(1));
      expect(alGateway.single.method, 'POST');
      expect(alGateway.single.url.path, '/api/v1/core/legal/consents');
      expect(alGateway.single.headers['Authorization'], 'Bearer token-nuevo');
      expect(logs, isEmpty);
    },
  );

  test(
    'si Core rechaza el consentimiento no se lanza, pero queda un log ERROR sin datos personales',
    () async {
      await datasource(500).registrarConsentimientoLegal(token: 'token-nuevo');

      expect(logs, hasLength(1));
      final linea = jsonDecode(logs.single) as Map<String, dynamic>;
      expect(linea['level'], 'ERROR');
      expect(linea['message'], contains('consentimiento legal'));
      expect(logs.single, isNot(contains('token-nuevo')));
    },
  );
}
