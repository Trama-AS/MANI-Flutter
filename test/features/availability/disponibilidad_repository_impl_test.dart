import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/availability/data/datasources/disponibilidad_remote_datasource.dart';
import 'package:mani/features/availability/data/repositories/disponibilidad_repository_impl.dart';
import 'package:mani/features/availability/domain/entities/ausencia.dart';
import 'package:mani/features/availability/domain/failures/disponibilidad_failure.dart';

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

DisponibilidadRepositoryImpl _repo(MockClientHandler handler) =>
    DisponibilidadRepositoryImpl(
      remoteDataSource: GatewayDisponibilidadDataSource(
        GatewayClient(
          baseUrl: 'http://gateway.local',
          tokenProvider: () async => 'jwt-aliado',
          httpClient: MockClient(handler),
          correlationId: () => 'corr-1',
          initialRetryDelay: Duration.zero,
          maxRetries: 0,
        ),
      ),
    );

const _ausenciaJson = {
  'id': '11111111-1111-4111-8111-111111111111',
  'startsAt': '2026-10-20T13:00:00.000Z',
  'endsAt': '2026-10-25T23:00:00.000Z',
  'reason': 'VACACIONES',
  'note': 'Viaje',
  'active': false,
};

final _borrador = BorradorAusencia(
  inicio: DateTime.utc(2026, 10, 20, 13),
  fin: DateTime.utc(2026, 10, 25, 23),
  motivo: MotivoAusencia.enfermedad,
  nota: '  Gripa  ',
);

Future<void> _esperaFalla(
  Future<void> Function() op,
  DisponibilidadErrorTipo tipo,
) async {
  await expectLater(
    op(),
    throwsA(isA<DisponibilidadFailure>().having((f) => f.tipo, 'tipo', tipo)),
  );
}

void main() {
  test('obtener lee las ausencias y availableNow vía el Gateway', () async {
    late http.Request recibida;
    final repo = _repo((r) async {
      recibida = r;
      return _json(200, {
        'availableNow': false,
        'data': [_ausenciaJson],
      });
    });

    final datos = await repo.obtener();

    expect(
      recibida.url.toString(),
      'http://gateway.local/api/v1/core/profiles/me/unavailability',
    );
    expect(recibida.method, 'GET');
    expect(recibida.headers['Authorization'], 'Bearer jwt-aliado');
    expect(datos.disponibleAhora, isFalse);
    expect(datos.ausencias.single.motivo, MotivoAusencia.vacaciones);
    expect(datos.ausencias.single.inicio.isUtc, isFalse);
    expect(
      datos.ausencias.single.inicio.toUtc(),
      DateTime.utc(2026, 10, 20, 13),
    );
  });

  test(
    'crear envía fechas en UTC, el código del motivo y la nota limpia',
    () async {
      late http.Request recibida;
      final repo = _repo((r) async {
        recibida = r;
        return _json(201, {'data': _ausenciaJson});
      });

      await repo.crear(_borrador);

      expect(recibida.method, 'POST');
      expect(jsonDecode(recibida.body), {
        'startsAt': '2026-10-20T13:00:00.000Z',
        'endsAt': '2026-10-25T23:00:00.000Z',
        'reason': 'ENFERMEDAD',
        'note': 'Gripa',
      });
    },
  );

  test('editar usa PATCH sobre el id y eliminar usa DELETE', () async {
    final llamadas = <String>[];
    final repo = _repo((r) async {
      llamadas.add('${r.method} ${r.url.path}');
      return r.method == 'DELETE'
          ? http.Response('', 204)
          : _json(200, {'data': _ausenciaJson});
    });

    await repo.editar('aus-1', _borrador);
    await repo.eliminar('aus-1');

    expect(llamadas, [
      'PATCH /api/v1/core/profiles/me/unavailability/aus-1',
      'DELETE /api/v1/core/profiles/me/unavailability/aus-1',
    ]);
  });

  test('traduce los errores de Core a DisponibilidadFailure', () async {
    final casos = <int, (String, DisponibilidadErrorTipo)>{
      401: (
        'Encabezado Authorization requerido',
        DisponibilidadErrorTipo.sinSesion,
      ),
      403: ('MANI-AUS-403: solo un aliado', DisponibilidadErrorTipo.noEsAliado),
      404: (
        'MANI-AUS-404: ausencia no encontrada',
        DisponibilidadErrorTipo.noEncontrada,
      ),
      409: (
        'MANI-AUS-409: el intervalo se cruza',
        DisponibilidadErrorTipo.solapamiento,
      ),
      500: ('Error interno', DisponibilidadErrorTipo.desconocido),
    };
    for (final MapEntry(key: status, value: (mensaje, tipo)) in casos.entries) {
      final repo = _repo((_) async => _json(status, {'error': mensaje}));
      await _esperaFalla(() => repo.crear(_borrador), tipo);
    }
  });

  test('distingue 422H (horario) de 422V (datos)', () async {
    await _esperaFalla(
      () => _repo(
        (_) async => _json(422, {'error': 'MANI-AUS-422H: horario inválido'}),
      ).crear(_borrador),
      DisponibilidadErrorTipo.horarioInvalido,
    );
    await _esperaFalla(
      () => _repo(
        (_) async => _json(422, {'error': 'MANI-AUS-422V: reason inválido'}),
      ).crear(_borrador),
      DisponibilidadErrorTipo.datosInvalidos,
    );
  });

  test('un fallo de red se reporta como sinConexion', () async {
    final repo = _repo((_) async => throw http.ClientException('sin red'));

    await _esperaFalla(repo.obtener, DisponibilidadErrorTipo.sinConexion);
  });
}
