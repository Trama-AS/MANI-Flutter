import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/direct_employees/data/empleados_directos_remote_datasource.dart';
import 'package:mani/features/profiles/direct_employees/domain/entities/empleado_directo.dart';
import 'package:mani/features/profiles/direct_employees/domain/usecases/registrar_empleado_directo_usecase.dart';
import 'package:mani/features/profiles/direct_employees/presentation/bloc/empleado_directo_cubit.dart';
import 'package:mani/features/profiles/direct_employees/presentation/pages/registrar_empleado_directo_page.dart';

void main() {
  group('SCRUM-850 (US-02.1.5) — Registrar empleado directo', () {
    test(
      'Datasource envía POST /api/v1/allies/direct-employees vía Gateway y retorna estado VERIFICADO y esEmpleadoDirecto=true',
      () async {
        late http.Request capturada;
        final gateway = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-admin-token',
          correlationId: () => 'corr-850',
          httpClient: MockClient((req) async {
            capturada = req;
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 'ally-850',
                  'usuarioId': 'user-850',
                  'tenantId': 'tenant-a',
                  'email': 'tecnico@empresa.co',
                  'nombreCompleto': 'Pedro Gómez',
                  'estadoVerificacion': 'VERIFICADO',
                  'esEmpleadoDirecto': true,
                  'categoriaIds': ['cat-1'],
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final ds = EmpleadosDirectosRemoteDataSource(gateway: gateway);
        final repo = EmpleadosDirectosRepositoryImpl(remoteDataSource: ds);
        final useCase = RegistrarEmpleadoDirectoUseCase(repo);

        final res = await useCase(
          const NuevoEmpleadoDirecto(
            email: ' tecnico@empresa.co ',
            password: 'Password123!',
            nombreCompleto: ' Pedro Gómez ',
            categoriaIds: ['cat-1'],
            telefono: '3001234567',
          ),
        );

        expect(capturada.method, 'POST');
        expect(
          capturada.url.toString(),
          'http://gateway.local/api/v1/allies/direct-employees',
        );
        expect(capturada.headers['Authorization'], 'Bearer jwt-admin-token');

        final body = jsonDecode(capturada.body) as Map<String, dynamic>;
        expect(body['email'], 'tecnico@empresa.co');
        expect(body['nombreCompleto'], 'Pedro Gómez');
        expect(body['categoriaIds'], ['cat-1']);

        expect(res.estadoVerificacion, 'VERIFICADO');
        expect(res.esEmpleadoDirecto, isTrue);
      },
    );

    testWidgets(
      'RegistrarEmpleadoDirectoPage registra un empleado directo y muestra su estado VERIFICADO inmediato',
      (tester) async {
        final gateway = GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-admin-token',
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 'ally-850',
                  'usuarioId': 'user-850',
                  'tenantId': 'tenant-a',
                  'email': 'directo@tenant.co',
                  'nombreCompleto': 'Laura Directa',
                  'estadoVerificacion': 'VERIFICADO',
                  'esEmpleadoDirecto': true,
                  'categoriaIds': ['cat-plomeria'],
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final cubit = EmpleadoDirectoCubit(
          registrarUseCase: RegistrarEmpleadoDirectoUseCase(
            EmpleadosDirectosRepositoryImpl(
              remoteDataSource: EmpleadosDirectosRemoteDataSource(
                gateway: gateway,
              ),
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: cubit,
              child: const RegistrarEmpleadoDirectoPage(
                categoriasDisponibles: {
                  'cat-plomeria': 'Plomería y Redes Hidráulicas',
                },
              ),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const Key('input_nombre_empleado_directo')),
          'Laura Directa',
        );
        await tester.enterText(
          find.byKey(const Key('input_email_empleado_directo')),
          'directo@tenant.co',
        );
        await tester.enterText(
          find.byKey(const Key('input_password_empleado_directo')),
          'Password123!',
        );
        await tester.tap(find.byKey(const Key('chk_categoria_cat-plomeria')));
        await tester.pump();

        final btnFinder = find.byKey(
          const Key('btn_registrar_empleado_directo'),
        );
        await tester.ensureVisible(btnFinder);
        await tester.pumpAndSettle();
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('card_empleado_directo_creado')),
          findsOneWidget,
        );
        expect(find.textContaining('Laura Directa'), findsWidgets);
        expect(find.textContaining('Estado: VERIFICADO'), findsOneWidget);

        await cubit.close();
      },
    );
  });
}
