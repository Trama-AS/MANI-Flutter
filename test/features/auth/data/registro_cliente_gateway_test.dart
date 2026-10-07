import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// US-02.2.1-M2.1: el registro de cliente persona natural sale por el
/// Gateway hacia Core Node, reutilizando el mismo GatewayClient y el mismo
/// endpoint de identidad que el registro de Aliado (CA-2) -- nunca toca
/// Supabase directamente (CA-3: sin .rpc() ni .from()).
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
        return http.Response('{}', 200);
      }),
    );
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => null,
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return AuthRemoteDataSource(client: supabase, gateway: gateway);
  }

  Future<Map<String, dynamic>> registrar(
    IAuthRemoteDataSource ds, {
    String? telefono,
    String? direccionHogar,
  }) => ds.registrarClientePersonaNatural(
    email: '  carlos@correo.co ',
    password: 'Secreta123!',
    nombreCompleto: ' Carlos Andrés Gómez ',
    tenantId: 'tenant-a',
    telefono: telefono,
    direccionHogar: direccionHogar,
  );

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => http.Response(
      jsonEncode({
        'profile': {
          'id': 'u-1',
          'tenantId': 'tenant-a',
          'role': 'CLIENT',
          'fullName': 'Carlos Andrés Gómez',
          'status': 'VERIFIED',
        },
        'tokens': {
          'accessToken': 'jwt-fake',
          'refreshToken': 'refresh-fake',
          'expiresIn': 3600,
        },
      }),
      201,
      headers: {'content-type': 'application/json'},
    );
  });

  group('datasource', () {
    test('una sola petición JSON, al Gateway, ninguna a Supabase', () async {
      await registrar(datasource());

      expect(aSupabase, isEmpty);
      expect(alGateway, hasLength(1));
      final r = alGateway.single;
      expect(r.method, 'POST');
      expect(
        r.url.toString(),
        'http://gateway.local${AuthRemoteDataSource.rutaRegistroClientePersonaNatural}',
      );
      expect(r.headers['content-type'], contains('application/json'));
      expect(r.headers['X-Correlation-ID'], 'corr-test');
    });

    test('envía los datos limpios como JSON (sin multipart)', () async {
      await registrar(datasource(), telefono: ' 3001234567 ');

      final body =
          jsonDecode(utf8.decode(alGateway.single.bodyBytes))
              as Map<String, dynamic>;
      expect(body['email'], 'carlos@correo.co');
      expect(body['fullName'], 'Carlos Andrés Gómez');
      expect(body['phone'], '3001234567');
    });

    test('sin teléfono, el campo phone no se envía', () async {
      await registrar(datasource());

      final body =
          jsonDecode(utf8.decode(alGateway.single.bodyBytes))
              as Map<String, dynamic>;
      expect(body.containsKey('phone'), isFalse);
    });

    test(
      'con direccionHogar, viaja recortada como direccionHogar (US-02.2.1-M2.2)',
      () async {
        await registrar(datasource(), direccionHogar: '  Calle 1 # 2-3  ');

        final body =
            jsonDecode(utf8.decode(alGateway.single.bodyBytes))
                as Map<String, dynamic>;
        expect(body['direccionHogar'], 'Calle 1 # 2-3');
      },
    );

    test('sin direccionHogar (o vacía), el campo no se envía', () async {
      await registrar(datasource());
      await registrar(datasource(), direccionHogar: '   ');

      for (final r in alGateway) {
        final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        expect(body.containsKey('direccionHogar'), isFalse);
      }
    });

    test('el tenant no viaja en el cuerpo, solo como header '
        'de preautenticación (X-Tenant-Slug ADR-0018) (CA-5)', () async {
      await registrar(datasource());

      final r = alGateway.single;
      final body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      expect(body.containsKey('tenantId'), isFalse);
      expect(body.containsKey('tenant_id'), isFalse);
      expect(r.headers[AuthRemoteDataSource.headerTenantSlug], 'tenant-a');
      expect(r.headers.containsKey('X-Tenant-Id'), isFalse);
      expect(r.headers.containsKey('X-Tenant-ID'), isFalse);
    });

    test('mantiene la forma de respuesta que espera la UI', () async {
      final res = await registrar(datasource());

      expect(res['success'], isTrue);
      expect(res['usuario_id'], 'u-1');
      expect(res['rol'], 'CLIENT');
      expect(res['estado'], 'VERIFIED');
    });
  });

  group('repositorio: errores visibles', () {
    Future<AuthFailure> fallo(http.Response respuesta) async {
      responder = (_) => respuesta;
      final repo = AuthRepositoryImpl(remoteDataSource: datasource());
      try {
        await repo.registrarClientePersonaNatural(
          email: 'a@b.co',
          password: 'x',
          nombreCompleto: 'N',
          tenantId: 't',
        );
      } on AuthFailure catch (e) {
        return e;
      }
      fail('debía lanzar AuthFailure');
    }

    http.Response json(int s, Map<String, Object> b) => http.Response(
      jsonEncode(b),
      s,
      headers: {'content-type': 'application/json'},
    );

    test('400 muestra el mensaje de validación', () async {
      final e = await fallo(json(400, {'error': 'email es requerido'}));
      expect(e.message, 'email es requerido');
    });

    test('409 informa el correo duplicado (CA-4)', () async {
      final e = await fallo(
        json(409, {'error': 'Ya existe un usuario registrado con ese email'}),
      );
      expect(e.message, 'Ya existe un usuario registrado con ese email');
    });

    test('5xx da un mensaje genérico sin detalles internos', () async {
      final e = await fallo(json(500, {'error': 'TypeError at line 42'}));
      expect(e.message, isNot(contains('TypeError')));
      expect(e.message, isNot(startsWith('Error en registro')));
    });
  });
}
