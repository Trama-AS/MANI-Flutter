import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/catalog/data/zonas_catalogo_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/data/sedes_empresa_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/domain/usecases/sedes_empresa_usecases.dart';
import 'package:mani/features/profiles/company_sites/presentation/bloc/sedes_empresa_cubit.dart';
import 'package:mani/features/profiles/company_sites/presentation/pages/gestion_sedes_empresa_page.dart';

/// HU-M04-04, C1: las zonas activas del catálogo se pueden seleccionar en las
/// interfaces que lo consumen.
///
/// La pantalla de sedes traía una lista de zonas fija en el código con ids
/// inventados (`z-chapinero`), que la base rechaza al crear la sede. Acá se
/// comprueba que el desplegable se arma con los ids y las etiquetas que
/// devuelve el catálogo, y que la sede se crea con el id real.
void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  final catalogo = {
    'zones': const [],
    'tree': [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Bogotá D.C.',
        'level': 'CIUDAD',
        'parentId': null,
        'active': true,
        'selectable': true,
        'children': [
          {
            'id': '22222222-2222-4222-8222-222222222222',
            'name': 'Chapinero',
            'level': 'LOCALIDAD',
            'parentId': '11111111-1111-4111-8111-111111111111',
            'active': true,
            'selectable': true,
            'children': const [],
          },
          {
            'id': '33333333-3333-4333-8333-333333333333',
            'name': 'Zona Retirada',
            'level': 'LOCALIDAD',
            'parentId': '11111111-1111-4111-8111-111111111111',
            'active': false,
            'selectable': false,
            'children': const [],
          },
        ],
      },
    ],
    'inconsistencies': const [],
  };

  testWidgets(
    'el desplegable de zonas se arma con el catálogo y la sede se crea con el id real',
    (tester) async {
      final peticiones = <http.Request>[];
      final gateway = GatewayClient(
        baseUrl: 'http://gateway.local',
        tokenProvider: () async => 'jwt-cliente-empresa',
        httpClient: MockClient((req) async {
          peticiones.add(req);
          if (req.url.path.endsWith('/catalog/zones')) {
            return json(catalogo);
          }
          if (req.method == 'GET') {
            return json({'data': const []});
          }
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return json({
            'data': {
              'id': 'sede-nueva',
              'clienteId': 'cli-corp-1',
              'tenantId': 'tenant-a',
              'nombre': body['nombre'],
              'direccion': body['direccion'],
              'zonaId': body['zonaId'],
              'activo': true,
            },
          }, 201);
        }),
      );

      final zonas = await ZonasCatalogoRemoteDataSource(
        gateway: gateway,
      ).opcionesSeleccionables();

      // Solo las seleccionables, con la etiqueta jerárquica del contrato.
      expect(zonas, {
        '11111111-1111-4111-8111-111111111111': 'Bogotá D.C.',
        '22222222-2222-4222-8222-222222222222': 'Bogotá D.C. · Chapinero',
      });

      final repo = SedesEmpresaRepositoryImpl(
        remoteDataSource: SedesEmpresaRemoteDataSource(gateway: gateway),
      );
      final cubit = SedesEmpresaCubit(
        listarUseCase: ListarSedesEmpresaUseCase(repo),
        agregarUseCase: AgregarSedeEmpresaUseCase(repo),
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: GestionSedesEmpresaPage(
              clienteId: 'cli-corp-1',
              zonasDisponibles: zonas,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La etiqueta del catálogo se ve en la pantalla; la zona inactiva no.
      expect(find.text('Bogotá D.C.'), findsWidgets);
      expect(find.text('Zona Retirada'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('input_nombre_sede')),
        'Sede Chapinero',
      );
      await tester.enterText(
        find.byKey(const Key('input_direccion_sede')),
        'Calle 72 # 10-07',
      );
      await tester.tap(find.byKey(const Key('dropdown_zona_sede')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bogotá D.C. · Chapinero').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_agregar_sede')));
      await tester.pumpAndSettle();

      final alta = peticiones.firstWhere((p) => p.method == 'POST');
      final enviado = jsonDecode(alta.body) as Map<String, dynamic>;
      expect(
        enviado['zonaId'],
        '22222222-2222-4222-8222-222222222222',
        reason:
            'se envía el id del catálogo, no un id inventado como z-chapinero',
      );
    },
  );
}
