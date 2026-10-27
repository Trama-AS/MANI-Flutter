import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/company_sites/data/sedes_empresa_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/domain/usecases/sedes_empresa_usecases.dart';
import 'package:mani/features/profiles/company_sites/presentation/bloc/sedes_empresa_cubit.dart';
import 'package:mani/features/profiles/company_sites/presentation/pages/gestion_sedes_empresa_page.dart';

/// `agregarNuevaSede` añadía la sede creada a la lista que ya tenía el estado.
/// Si una recarga traía esa misma sede antes del emit, quedaba dos veces y el
/// Column de la pantalla lanzaba "Duplicate keys found", porque cada tarjeta
/// usa `Key('sede_card_<id>')`. Reproducido contra el Gateway en local.
void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  const zona = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a13';
  const sedeNueva = {
    'id': 'sede-nueva',
    'clienteId': 'cli-1',
    'tenantId': 'tenant-a',
    'nombre': 'Sede Chapinero',
    'direccion': 'Calle 72 # 10-07',
    'zonaId': zona,
    'activo': true,
  };

  SedesEmpresaCubit cubitQueYaTieneLaSede() {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((req) async {
        // Core ya tiene la sede: es el caso en que la recarga se adelanta al
        // emit del alta.
        if (req.method == 'GET')
          return json({
            'sitios': const [sedeNueva],
          });
        return json({'sitio': sedeNueva}, 201);
      }),
    );
    final repo = SedesEmpresaRepositoryImpl(
      remoteDataSource: SedesEmpresaRemoteDataSource(gateway: gateway),
    );
    return SedesEmpresaCubit(
      listarUseCase: ListarSedesEmpresaUseCase(repo),
      agregarUseCase: AgregarSedeEmpresaUseCase(repo),
    );
  }

  test(
    'agregar una sede que la recarga ya trajo no la duplica en el estado',
    () async {
      final cubit = cubitQueYaTieneLaSede();
      addTearDown(cubit.close);

      await cubit.cargarSedes('cli-1');
      expect(cubit.state.sedes, hasLength(1));

      await cubit.agregarNuevaSede(
        clienteId: 'cli-1',
        nombre: 'Sede Chapinero',
        direccion: 'Calle 72 # 10-07',
        zonaId: zona,
      );

      expect(cubit.state.sedes, hasLength(1), reason: 'la sede no se repite');
      expect(cubit.state.sedes.single.id, 'sede-nueva');
    },
  );

  testWidgets('la pantalla no lanza "Duplicate keys found" en ese caso', (
    tester,
  ) async {
    final cubit = cubitQueYaTieneLaSede();
    addTearDown(cubit.close);
    await cubit.cargarSedes('cli-1');

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const GestionSedesEmpresaPage(
            clienteId: 'cli-1',
            zonasDisponibles: {zona: 'Bogotá D.C. · Chapinero'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await cubit.agregarNuevaSede(
      clienteId: 'cli-1',
      nombre: 'Sede Chapinero',
      direccion: 'Calle 72 # 10-07',
      zonaId: zona,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sede_card_sede-nueva')), findsOneWidget);
  });
}
