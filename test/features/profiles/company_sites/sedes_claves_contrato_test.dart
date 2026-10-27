import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/company_sites/data/sedes_empresa_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';

/// Core responde las sedes en `sitios` (listado) y `sitio` (alta), no en
/// `data` ni `sites`. Con las claves anteriores la pantalla se veía vacía
/// aunque el cliente tuviera sedes, verificado contra el Gateway en local.
void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  SedesEmpresaRemoteDataSource datasourceQueResponde(
    http.Response Function(http.Request) responder,
  ) => SedesEmpresaRemoteDataSource(
    gateway: GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((r) async => responder(r)),
    ),
  );

  const sitio = {
    'id': 'sede-1',
    'clienteId': 'cli-1',
    'tenantId': 'tenant-a',
    'nombre': 'Sede Principal',
    'direccion': 'Carrera 11 # 93-45',
    'zonaId': 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14',
    'activo': true,
  };

  test('el listado lee la clave `sitios` que devuelve Core', () async {
    final ds = datasourceQueResponde(
      (_) => json({
        'clienteId': 'cli-1',
        'razonSocial': 'Inversiones Guayacán SAS',
        'totalSitios': 1,
        'sitios': const [sitio],
      }),
    );

    final sedes = await ds.listarSedes('cli-1');

    expect(sedes, hasLength(1));
    expect(sedes.single.nombre, 'Sede Principal');
    expect(sedes.single.zonaId, 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14');
  });

  test('el alta lee la clave `sitio` que devuelve Core', () async {
    final ds = datasourceQueResponde(
      (_) => json({
        'message': 'Sitio agregado exitosamente.',
        'correlationId': 'corr-1',
        'sitio': sitio,
      }, 201),
    );

    final creada = await ds.agregarSede(
      'cli-1',
      const NuevaSedeEmpresa(
        nombre: 'Sede Principal',
        direccion: 'Carrera 11 # 93-45',
        zonaId: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14',
      ),
    );

    expect(creada.id, 'sede-1');
    expect(creada.zonaId, 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14');
  });

  test('se conserva `data` como respaldo de respuestas anteriores', () async {
    final ds = datasourceQueResponde((_) => json({'data': const [sitio]}));

    expect(await ds.listarSedes('cli-1'), hasLength(1));
  });
}
