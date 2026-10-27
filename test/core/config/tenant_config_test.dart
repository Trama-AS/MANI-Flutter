import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/config/tenant_config.dart';

/// El registro de cliente envía el slug del tenant en X-Tenant-Slug. En PROD
/// la pantalla enviaba un UUID fijo y Core rechazaba el registro.
void main() {
  test('usa TENANT_SLUG del .env', () {
    dotenv.testLoad(fileInput: 'TENANT_SLUG=acme-servicios');
    expect(tenantSlugRegistro(), 'acme-servicios');
  });

  test('sin TENANT_SLUG usa el slug por defecto', () {
    dotenv.testLoad(fileInput: 'OTRA=1');
    expect(tenantSlugRegistro(), tenantSlugPorDefecto);
  });

  test('rechaza un UUID en lugar del slug', () {
    expect(
      () => tenantSlugRegistro(valor: 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'),
      throwsStateError,
    );
  });

  test('ninguna pantalla de auth fija el tenant con un UUID literal', () {
    final uuid = RegExp(
      r"'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'",
    );
    final conUuid = <String>[];
    for (final f in Directory(
      'lib/features/auth/presentation/pages',
    ).listSync().whereType<File>()) {
      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        if (lineas[i].contains('enant') && uuid.hasMatch(lineas[i])) {
          conUuid.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(conUuid, isEmpty);
  });

  test('ninguna pantalla fija UUID de la semilla (tenants o categorías)', () {
    final uuid = RegExp(
      r"'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'",
    );
    final conUuid = <String>[];
    for (final f in Directory('lib/features').listSync(recursive: true)) {
      if (f is! File || !f.path.contains('/presentation/')) continue;
      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        if (uuid.hasMatch(lineas[i])) conUuid.add('${f.path}:${i + 1}');
      }
    }
    expect(conUuid, isEmpty);
  });
}
