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

void main() {
  group('SCRUM-852 (US-02.2.2) — Cliente empresa con múltiples sitios', () {
    testWidgets(
      'Lista las sedes existentes del cliente empresa y permite agregar una nueva sucursal vía Gateway',
      (tester) async {
        final peticiones = <http.Request>[];
        final gateway = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-cliente-empresa',
          httpClient: MockClient((req) async {
            peticiones.add(req);
            if (req.method == 'GET') {
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'sede-1',
                      'clienteId': 'cli-corp-1',
                      'tenantId': 'tenant-a',
                      'nombre': 'Sede Principal Centro',
                      'direccion': 'Calle 72 # 10-07',
                      'zonaId': 'z-chapinero',
                      'activo': true,
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 'sede-2',
                  'clienteId': 'cli-corp-1',
                  'tenantId': 'tenant-a',
                  'nombre': body['nombre'],
                  'direccion': body['direccion'],
                  'zonaId': body['zonaId'],
                  'activo': true,
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final repo = SedesEmpresaRepositoryImpl(
          remoteDataSource: SedesEmpresaRemoteDataSource(gateway: gateway),
        );
        final cubit = SedesEmpresaCubit(
          listarUseCase: ListarSedesEmpresaUseCase(repo),
          agregarUseCase: AgregarSedeEmpresaUseCase(repo),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: cubit,
              child: const GestionSedesEmpresaPage(clienteId: 'cli-corp-1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sede_card_sede-1')), findsOneWidget);
        expect(find.text('Sede Principal Centro'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('input_nombre_sede')),
          'Sucursal Norte Usaquén',
        );
        await tester.enterText(
          find.byKey(const Key('input_direccion_sede')),
          'Carrera 15 # 119-40',
        );

        final btn = find.byKey(const Key('btn_agregar_sede'));
        await tester.ensureVisible(btn);
        await tester.pumpAndSettle();
        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(peticiones, hasLength(2));
        expect(
          peticiones.last.url.toString(),
          'http://gateway.local/api/v1/core/clients/cli-corp-1/sites',
        );
        expect(find.byKey(const Key('sede_card_sede-2')), findsOneWidget);
        expect(find.text('Sucursal Norte Usaquén'), findsOneWidget);

        await cubit.close();
      },
    );
  });
}
