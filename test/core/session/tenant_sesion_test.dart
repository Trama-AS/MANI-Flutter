import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/session/rol_usuario.dart';

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
}
