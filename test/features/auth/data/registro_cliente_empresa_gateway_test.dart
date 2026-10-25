import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/features/auth/domain/entities/registro_cliente_empresa.dart';

/// HU-M02-07: el registro de cliente empresa sale por el Gateway hacia Core
/// (`/auth/register/client/company`), sin tocar Supabase y sin sitios.
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
  }) => ds.registrarClienteEmpresa(
    RegistroClienteEmpresa(
      email: ' compras@andina.co ',
      password: 'Secreta123!',
      razonSocial: ' Constructora Andina SAS ',
      nit: '900123456-7',
      nombreRepresentante: ' Laura Gómez ',
      tenantId: 'tenant-a',
      telefono: telefono,
    ),
  );

  Map<String, dynamic> cuerpo() =>
      jsonDecode(utf8.decode(alGateway.single.bodyBytes))
          as Map<String, dynamic>;

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => http.Response(
      jsonEncode({
        'profile': {
          'id': 'u-9',
          'tenantId': 'tenant-a',
          'role': 'CLIENT',
          'fullName': 'Constructora Andina SAS',
          'status': 'VERIFIED',
        },
        'company': {'clienteId': 'c-1', 'tipo': 'PERSONA_JURIDICA'},
        'tokens': {
          'accessToken': 'jwt-fake',
          'refreshToken': 'r',
          'expiresIn': 3600,
        },
      }),
      201,
      headers: {'content-type': 'application/json'},
    );
  });

  group('datasource', () {
    test(
      'una sola petición JSON a la ruta de cliente empresa del Gateway',
      () async {
        await registrar(datasource());

        expect(aSupabase, isEmpty);
        expect(alGateway, hasLength(1));
        final r = alGateway.single;
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          'http://gateway.local${AuthRemoteDataSource.rutaRegistroClienteEmpresa}',
        );
        expect(
          AuthRemoteDataSource.rutaRegistroClienteEmpresa,
          '/api/v1/core/auth/register/client/company',
        );
        expect(r.headers['content-type'], contains('application/json'));
      },
    );

    test('envía los datos limpios, acceptsTerms y ningún sitio', () async {
      await registrar(datasource(), telefono: ' 6011234567 ');

      final body = cuerpo();
      expect(body['email'], 'compras@andina.co');
      expect(body['razonSocial'], 'Constructora Andina SAS');
      expect(body['nit'], '900123456-7');
      expect(body['nombreRepresentante'], 'Laura Gómez');
      expect(body['phone'], '6011234567');
      expect(body['acceptsTerms'], isTrue);
      expect(body.containsKey('sitios'), isFalse);
    });

    test('sin teléfono no envía phone', () async {
      await registrar(datasource());
      expect(cuerpo().containsKey('phone'), isFalse);
    });

    test('el tenant viaja solo en X-Tenant-Slug (ADR-0018)', () async {
      await registrar(datasource());

      final r = alGateway.single;
      expect(cuerpo().containsKey('tenantId'), isFalse);
      expect(r.headers[AuthRemoteDataSource.headerTenantSlug], 'tenant-a');
    });

    test(
      'no llama después a /legal/consents: Core ya registra la aceptación',
      () async {
        await registrar(datasource());
        expect(
          alGateway.where((r) => r.url.path.contains('legal/consents')),
          isEmpty,
        );
      },
    );

    test('devuelve la forma que espera la UI', () async {
      final res = await registrar(datasource());

      expect(res['success'], isTrue);
      expect(res['usuario_id'], 'u-9');
      expect(res['rol'], 'CLIENT');
      expect(res['company']['tipo'], 'PERSONA_JURIDICA');
    });
  });

  group('repositorio: errores visibles', () {
    Future<AuthFailure> fallo(http.Response respuesta) async {
      responder = (_) => respuesta;
      final repo = AuthRepositoryImpl(remoteDataSource: datasource());
      try {
        await repo.registrarClienteEmpresa(
          const RegistroClienteEmpresa(
            email: 'a@b.co',
            password: 'x',
            razonSocial: 'R',
            nit: '900123456',
            nombreRepresentante: 'N',
            tenantId: 't',
          ),
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

    test('409 informa el NIT ya registrado', () async {
      final e = await fallo(
        json(409, {
          'error': 'La empresa ya está registrada con ese NIT en este tenant',
          'code': 'COMPANY_ALREADY_REGISTERED',
        }),
      );
      expect(
        e.message,
        'La empresa ya está registrada con ese NIT en este tenant',
      );
    });

    test('5xx da un mensaje genérico sin detalles internos', () async {
      final e = await fallo(json(500, {'error': 'TypeError at line 42'}));
      expect(e.message, isNot(contains('TypeError')));
    });
  });
}
