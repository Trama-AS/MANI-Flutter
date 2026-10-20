import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/site_rules/data/reglas_sitio_remote_datasource.dart';
import 'package:mani/features/profiles/site_rules/domain/entities/reglas_sitio.dart';
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
                        'horario': {
                          'inicio': '07:00',
                          'fin': '16:00',
                          'diasPermitidos': ['LUN', 'MAR', 'SAB'],
                        },
                        'permisosRequeridos': ['ARL vigente', 'Cédula'],
                        'elementosProteccion': ['Casco dieléctrico'],
                        'requiereAprobacionPrevia': true,
                        'contactoAcceso': {
                          'nombre': 'Portería',
                          'telefono': '6011234567',
                        },
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
            'http://gateway.local/api/v1/core/sites/site-101/rules',
          );
          expect(
            find.textContaining('Usar casco dieléctrico y botas con puntera'),
            findsWidgets,
          );

          // El PUT envía solo el formato SiteRules de Core (MANI-Node#12) y conserva lo no editado.
          final enviado =
              (jsonDecode(peticiones.last.body)
                      as Map<String, dynamic>)['reglas']
                  as Map<String, dynamic>;
          expect(enviado.keys.toSet(), {
            'horario',
            'permisosRequeridos',
            'elementosProteccion',
            'instruccionesIngreso',
            'requiereAprobacionPrevia',
            'contactoAcceso',
          });
          expect(enviado['horario'], {
            'inicio': '07:00',
            'fin': '16:00',
            'diasPermitidos': ['LUN', 'MAR', 'SAB'],
          });
          expect(enviado['elementosProteccion'], ['Casco dieléctrico']);
          expect(enviado['requiereAprobacionPrevia'], true);

          await cubit.close();
        },
      );
    },
  );

  group('ReglasContextualesSitio.toPayload', () {
    test(
      'sin horario no inventa uno: el sitio queda sin restricción horaria',
      () {
        const reglas = ReglasContextualesSitio(siteId: 's1');

        final payload = reglas.toPayload()['reglas'] as Map<String, dynamic>;

        expect(payload.containsKey('horario'), isFalse);
        expect(payload.containsKey('requiereEpp'), isFalse);
        expect(payload.containsKey('horarioPermitido'), isFalse);
        expect(payload.containsKey('documentosRequeridos'), isFalse);
      },
    );

    test(
      'convierte el horario de texto al objeto de Core y lee el mismo formato de vuelta',
      () {
        const reglas = ReglasContextualesSitio(
          siteId: 's1',
          horarioPermitido: '8:00 - 17:30',
          permisosRequeridos: ['ARL'],
        );

        final payload = reglas.toPayload();
        final leido = ReglasContextualesSitio.fromJson('s1', payload);

        expect((payload['reglas'] as Map)['horario'], {
          'inicio': '08:00',
          'fin': '17:30',
          'diasPermitidos': ReglasContextualesSitio.diasHabiles,
        });
        expect(leido.horarioPermitido, '08:00 - 17:30');
        expect(leido.permisosRequeridos, ['ARL']);
      },
    );
  });
}
