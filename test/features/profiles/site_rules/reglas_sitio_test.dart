import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/site_rules/data/reglas_sitio_remote_datasource.dart';
import 'package:mani/features/profiles/site_rules/domain/usecases/reglas_sitio_usecases.dart';
import 'package:mani/features/profiles/site_rules/presentation/bloc/reglas_sitio_cubit.dart';
import 'package:mani/features/profiles/site_rules/presentation/pages/reglas_sitio_page.dart';

void main() {
  group(
    'SCRUM-853 (US-02.2.3) — Reglas contextuales del sitio visibles al aliado',
    () {
      testWidgets(
        'Permite consultar las reglas visibles para el aliado (GET) y actualizarlas como cliente corporativo (PUT) vía Gateway',
        (tester) async {
          final peticiones = <http.Request>[];
          final gateway = GatewayClient(
            baseUrl: 'http://gateway.local',
            tokenProvider: () async => 'jwt-cliente-corp',
            httpClient: MockClient((req) async {
              peticiones.add(req);
              if (req.method == 'GET') {
                return http.Response(
                  jsonEncode({
                    'data': {
                      'id': 'site-101',
                      'reglas': {
                        'requiereEpp': true,
                        'horarioPermitido': '08:00 - 17:00',
                        'documentosRequeridos': ['ARL vigente', 'Cédula'],
                        'instruccionesIngreso':
                            'Anunciarse en recepción torre B',
                      },
                    },
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              final body = jsonDecode(req.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'data': {'id': 'site-101', 'reglas': body['reglas']},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );

          final repo = ReglasSitioRepositoryImpl(
            remoteDataSource: ReglasSitioRemoteDataSource(gateway: gateway),
          );
          final cubit = ReglasSitioCubit(
            obtenerUseCase: ObtenerReglasSitioUseCase(repo),
            configurarUseCase: ConfigurarReglasSitioUseCase(repo),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: BlocProvider.value(
                value: cubit,
                child: const ReglasSitioPage(siteId: 'site-101'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('card_reglas_visibles_aliado')),
            findsOneWidget,
          );
          expect(find.textContaining('ARL vigente'), findsWidgets);
          expect(
            find.textContaining('Anunciarse en recepción torre B'),
            findsWidgets,
          );

          await tester.enterText(
            find.byKey(const Key('input_instrucciones_reglas_sitio')),
            'Usar casco dieléctrico y botas con puntera',
          );

          final btn = find.byKey(const Key('btn_guardar_reglas_sitio'));
          await tester.ensureVisible(btn);
          await tester.pumpAndSettle();
          await tester.tap(btn);
          await tester.pumpAndSettle();

          expect(peticiones, hasLength(2));
          expect(peticiones.last.method, 'PUT');
          expect(
            peticiones.last.url.toString(),
            'http://gateway.local/api/v1/sites/site-101/rules',
          );
          expect(
            find.textContaining('Usar casco dieléctrico y botas con puntera'),
            findsWidgets,
          );

          await cubit.close();
        },
      );
    },
  );
}
