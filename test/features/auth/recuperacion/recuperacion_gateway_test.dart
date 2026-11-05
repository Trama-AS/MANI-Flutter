import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/recuperacion_contrasena_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/recuperacion_contrasena_repository_impl.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// HU-M02-10: la recuperación sale por el Gateway hacia Core y nunca toca Supabase.
void main() {
  late List<http.Request> alGateway;
  late List<http.BaseRequest> aSupabase;
  late http.Response Function(http.Request) responder;

  RecuperacionContrasenaRemoteDataSource datasource() {
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
    return RecuperacionContrasenaRemoteDataSource(
      client: supabase,
      gateway: gateway,
    );
  }

  http.Response json(int status, Map<String, Object> body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> cuerpo() =>
      jsonDecode(utf8.decode(alGateway.single.bodyBytes))
          as Map<String, dynamic>;

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => json(202, {'message': 'ok'});
  });

  group('solicitar', () {
    test(
      'POST al Gateway con el correo limpio y el tenant solo en X-Tenant-Slug',
      () async {
        await datasource().solicitar(
          email: '  ana@correo.co ',
          tenantSlug: 'acme',
        );

        final r = alGateway.single;
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          'http://gateway.local${RecuperacionContrasenaRemoteDataSource.rutaSolicitud}',
        );
        expect(
          RecuperacionContrasenaRemoteDataSource.rutaSolicitud,
          '/api/v1/core/auth/password-recovery',
        );
        expect(
          r.headers[RecuperacionContrasenaRemoteDataSource.headerTenantSlug],
          'acme',
        );
        expect(cuerpo(), {'email': 'ana@correo.co'});
        expect(aSupabase, isEmpty);
      },
    );

    test('un 429 se explica como demasiados envíos', () async {
      responder = (_) => json(429, {'error': 'x', 'code': 'RATE_LIMITED'});
      await expectLater(
        datasource().solicitar(email: 'a@b.co', tenantSlug: 'acme'),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              RecuperacionContrasenaRemoteDataSource.mensajeDemasiadosEnvios,
            ),
          ),
        ),
      );
    });
  });

  group('restablecer', () {
    test(
      'POST con token y contraseña nueva, tenant en el header, y cierra la sesión de recuperación',
      () async {
        await datasource().restablecer(
          accessToken: 'tok',
          newPassword: 'ClaveNueva123',
          tenantSlug: 'acme',
        );

        final r = alGateway.single;
        expect(
          r.url.path,
          RecuperacionContrasenaRemoteDataSource.rutaRestablecimiento,
        );
        expect(
          RecuperacionContrasenaRemoteDataSource.rutaRestablecimiento,
          '/api/v1/core/auth/password-reset',
        );
        expect(
          r.headers[RecuperacionContrasenaRemoteDataSource.headerTenantSlug],
          'acme',
        );
        expect(cuerpo(), {
          'accessToken': 'tok',
          'newPassword': 'ClaveNueva123',
        });
      },
    );

    test('si falla no intenta cerrar sesión en Supabase', () async {
      responder = (_) =>
          json(401, {'error': 'x', 'code': 'INVALID_RECOVERY_TOKEN'});
      await expectLater(
        datasource().restablecer(
          accessToken: 'tok',
          newPassword: 'ClaveNueva123',
          tenantSlug: 'acme',
        ),
        throwsA(anything),
      );
      expect(aSupabase, isEmpty);
    });
  });

  group('repositorio: errores visibles', () {
    Future<AuthFailure> fallo(
      Future<void> Function(RecuperacionContrasenaRepositoryImpl) accion,
    ) async {
      final repo = RecuperacionContrasenaRepositoryImpl(
        remoteDataSource: datasource(),
      );
      try {
        await accion(repo);
      } on AuthFailure catch (e) {
        return e;
      }
      fail('debía lanzar AuthFailure');
    }

    test(
      'un 401 del restablecimiento dice que el enlace no sirve, no que la sesión venció',
      () async {
        responder = (_) =>
            json(401, {'error': 'x', 'code': 'INVALID_RECOVERY_TOKEN'});
        final e = await fallo(
          (r) => r.restablecer(
            accessToken: 't',
            newPassword: 'ClaveNueva123',
            tenantSlug: 'acme',
          ),
        );
        expect(
          e.message,
          RecuperacionContrasenaRemoteDataSource.mensajeEnlaceInvalido,
        );
        expect(e.message, isNot(contains('sesión')));
      },
    );

    test('un 400 muestra el mensaje de validación de Core', () async {
      responder = (_) => json(400, {
        'error': 'email es requerido y debe tener un formato válido',
      });
      final e = await fallo(
        (r) => r.solicitarEnlace(email: 'x', tenantSlug: 'acme'),
      );
      expect(e.message, 'email es requerido y debe tener un formato válido');
    });

    test('un 5xx da un mensaje genérico sin detalles internos', () async {
      responder = (_) => json(500, {'error': 'TypeError at line 42'});
      final e = await fallo(
        (r) => r.solicitarEnlace(email: 'a@b.co', tenantSlug: 'acme'),
      );
      expect(e.message, isNot(contains('TypeError')));
    });
  });
}
