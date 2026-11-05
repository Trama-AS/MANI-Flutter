import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/company_sites/data/sedes_empresa_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';
import 'package:mani/features/profiles/company_sites/domain/usecases/sedes_empresa_usecases.dart';
import 'package:mani/features/profiles/company_sites/presentation/bloc/sedes_empresa_cubit.dart';

/// SCRUM-1625: `agregar` emitía `[...state.sedes, creada]`. Si una recarga
/// traía esa misma sede entre el POST y el emit, quedaba dos veces en el
/// estado, y como cada tarjeta usa `Key('sede_card_<id>')`, el Column de la
/// pantalla lanzaba "Duplicate keys found" y la vista dejaba de construirse.
void main() {
  const rutaZonas = '/api/v1/core/catalog/zones';

  const zonas = [
    {'id': 'z-chap', 'name': 'Chapinero', 'parentId': null, 'selectable': true},
  ];
  const sedeNueva = {
    'id': 'sede-nueva',
    'nombre': 'Sede Chapinero',
    'direccion': 'Calle 72 # 10-07',
    'zonaId': 'z-chap',
    'contactoNombre': null,
    'contactoTelefono': null,
  };

  http.Response json(Object cuerpo, int status) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: const {'content-type': 'application/json'},
  );

  SedesEmpresaCubit cubitConLaSedeYaListada() {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((req) async {
        if (req.url.path == rutaZonas) {
          return json({'zones': zonas}, 200);
        }
        // Core ya devuelve la sede en el listado: es el caso en que la
        // recarga se adelanta al emit del alta.
        if (req.method == 'GET') {
          return json({
            'sitios': const [sedeNueva],
          }, 200);
        }
        return json({'sitio': sedeNueva}, 201);
      }),
    );
    final repo = SedesEmpresaRepositoryImpl(
      remoteDataSource: SedesEmpresaRemoteDataSource(gateway: gateway),
    );
    return SedesEmpresaCubit(
      listarUseCase: ListarSedesEmpresaUseCase(repo),
      agregarUseCase: AgregarSedeEmpresaUseCase(repo),
      editarUseCase: EditarSedeEmpresaUseCase(repo),
      listarZonasUseCase: ListarZonasSedeUseCase(repo),
    );
  }

  test('agregar una sede que el listado ya trajo no la duplica', () async {
    final cubit = cubitConLaSedeYaListada();
    addTearDown(cubit.close);

    await cubit.cargar();
    expect(cubit.state.sedes, hasLength(1));

    await cubit.agregar(
      const NuevaSedeEmpresa(
        nombre: 'Sede Chapinero',
        direccion: 'Calle 72 # 10-07',
        zonaId: 'z-chap',
      ),
    );

    expect(cubit.state.sedes, hasLength(1), reason: 'la sede no se repite');
    expect(cubit.state.sedes.single.id, 'sede-nueva');
    expect(
      cubit.state.sedes.map((s) => s.id).toSet(),
      hasLength(cubit.state.sedes.length),
      reason: 'ningún id repetido: dos Key iguales rompen el Column',
    );
  });
}
