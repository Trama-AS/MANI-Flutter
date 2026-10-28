import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/session/tenant_sesion.dart';
import 'package:mani/features/profiles/coverage/data/datasources/cobertura_remote_datasource.dart';
import 'package:mani/features/profiles/verification/data/datasources/verificacion_remote_datasource.dart';
import 'package:mani/features/services/categories/data/datasources/categorias_remote_datasource.dart';
import 'package:mani/features/services/requests/data/datasources/solicitudes_cliente_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

String _token(Map<String, dynamic> payload) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'ES256'})}.${b64(payload)}.firma';
}

/// SCRUM-1380, C3: el tenant sale del claim del token verificado, nunca de datos que el usuario pueda editar.
void main() {
  test('lee el tenant de app_metadata del token', () {
    final token = _token({
      'app_metadata': {'tenant_id': 'tenant-a', 'user_role': 'cliente'},
    });
    expect(tenantDesdeAccessToken(token), 'tenant-a');
  });

  test(
    'ignora user_metadata: un usuario que se edita el tenant no lo cambia',
    () {
      final token = _token({
        'app_metadata': {'tenant_id': 'tenant-a'},
        'user_metadata': {'tenant_id': 'tenant-ajeno', 'role': 'admin'},
      });
      expect(tenantDesdeAccessToken(token), 'tenant-a');
      expect(
        rolDesdeAccessToken(token),
        RolUsuario.desconocido,
        reason: 'tampoco toma el rol de user_metadata',
      );
    },
  );

  test('sin tenant en app_metadata no inventa uno desde user_metadata', () {
    final token = _token({
      'user_metadata': {'tenant_id': 'tenant-ajeno'},
    });
    expect(tenantDesdeAccessToken(token), isNull);
  });

  test(
    'tokens ausentes, mal formados o con tenant vacío o no textual dan null',
    () {
      expect(tenantDesdeAccessToken(null), isNull);
      expect(tenantDesdeAccessToken(''), isNull);
      expect(tenantDesdeAccessToken('no-es-un-jwt'), isNull);
      expect(tenantDesdeAccessToken('a.%%%.c'), isNull);
      expect(
        tenantDesdeAccessToken(
          _token({
            'app_metadata': {'tenant_id': ''},
          }),
        ),
        isNull,
      );
      expect(
        tenantDesdeAccessToken(
          _token({
            'app_metadata': {'tenant_id': 7},
          }),
        ),
        isNull,
      );
      expect(tenantDesdeAccessToken(_token({'app_metadata': 'texto'})), isNull);
    },
  );

  group('tenantIdDeSesion y los datasources que lo usan', () {
    Future<SupabaseClient> clienteConSesion({
      required Map<String, dynamic> claimsDelToken,
      Map<String, dynamic> appMetadataDelUsuario = const {},
      Map<String, dynamic> userMetadataDelUsuario = const {},
    }) async {
      final cliente = SupabaseClient(
        'http://localhost:54321',
        'clave-de-prueba',
      );
      await cliente.auth.setInitialSession(
        jsonEncode({
          'access_token': _token(claimsDelToken),
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
          'refresh_token': 'r',
          'user': {
            'id': 'u-1',
            'aud': 'authenticated',
            'created_at': '2026-10-27T00:00:00Z',
            'app_metadata': appMetadataDelUsuario,
            'user_metadata': userMetadataDelUsuario,
          },
        }),
      );
      return cliente;
    }

    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => null,
    );
    final conTenantEnElToken = {
      'app_metadata': {'tenant_id': 'tenant-token'},
    };

    test('toma el tenant del claim del token', () async {
      final c = await clienteConSesion(claimsDelToken: conTenantEnElToken);
      expect(tenantIdDeSesion(c.auth), 'tenant-token');
    });

    test(
      'si el token no lo trae, usa app_metadata del usuario (que solo escribe el servidor)',
      () async {
        final c = await clienteConSesion(
          claimsDelToken: const {},
          appMetadataDelUsuario: {'tenant_id': 'tenant-app'},
        );
        expect(tenantIdDeSesion(c.auth), 'tenant-app');
      },
    );

    test(
      'C3: nunca usa user_metadata, aunque sea lo único que traiga el tenant',
      () async {
        final c = await clienteConSesion(
          claimsDelToken: const {},
          userMetadataDelUsuario: {'tenant_id': 'tenant-ajeno'},
        );
        expect(tenantIdDeSesion(c.auth), isNull);
      },
    );

    test('sin sesión no hay tenant', () {
      expect(
        tenantIdDeSesion(
          SupabaseClient('http://localhost:54321', 'clave-de-prueba').auth,
        ),
        isNull,
      );
    });

    test(
      'los cuatro datasources que registran el tenant en las trazas lo toman del token',
      () async {
        final c = await clienteConSesion(
          claimsDelToken: conTenantEnElToken,
          userMetadataDelUsuario: {'tenant_id': 'tenant-ajeno'},
        );
        expect(
          SolicitudesClienteRemoteDataSourceImpl(c, gateway).tenantIdSesion,
          'tenant-token',
        );
        expect(
          GatewayCategoriasDataSource(gateway, sesion: c).tenantIdSesion,
          'tenant-token',
        );
        expect(
          GatewayVerificacionDataSource(gateway, sesion: c).tenantIdSesion,
          'tenant-token',
        );
        expect(SupabaseCoberturaDataSource(c).tenantIdSesion, 'tenant-token');
      },
    );

    test(
      'sin sesión inyectada o sin sesión abierta, ningún datasource inventa un tenant',
      () {
        final vacio = SupabaseClient(
          'http://localhost:54321',
          'clave-de-prueba',
        );
        expect(GatewayCategoriasDataSource(gateway).tenantIdSesion, isNull);
        expect(GatewayVerificacionDataSource(gateway).tenantIdSesion, isNull);
        expect(
          SolicitudesClienteRemoteDataSourceImpl(vacio, gateway).tenantIdSesion,
          isNull,
        );
        expect(SupabaseCoberturaDataSource(vacio).tenantIdSesion, isNull);
      },
    );
  });
}
