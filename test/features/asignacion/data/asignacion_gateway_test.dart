import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/asignacion/data/datasources/asignacion_remote_datasource.dart';
import 'package:mani/features/asignacion/data/repositories/asignacion_repository_impl.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _id = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _oferta({bool mia = false}) => {
  'id': _id,
  'estado': mia ? 'ASIGNADA' : 'PENDIENTE',
  'esMia': mia,
  'categoria': 'Plomería',
  'flujoOperativo': 'COTIZACION_PREVIA',
  'descripcion': 'Gotea el lavaplatos',
  'fotos': 2,
  'zona': 'Chapinero',
  'zonaPadre': 'Bogotá',
  'reglasSitio': {'mascotas': false},
  'direccion': mia ? 'Calle 1 # 2-3' : null,
  'creadaEn': '2026-10-27T10:00:00.000Z',
  'asignadaEn': mia ? '2026-10-27T10:05:00.000Z' : null,
};

http.Response _error(int status, String code) => http.Response(
  jsonEncode({'error': code, 'code': code, 'status': status}),
  status,
  headers: _json,
);

/// SCRUM-1402/1403/1404 (decisión 6A): la bandeja del aliado va por el
/// Gateway a Dispatch, no por las RPC de Supabase.
void main() {
  late List<http.Request> alGateway;
  late http.Response Function(http.Request) responder;
  var claves = 0;

  GatewayAsignacionDataSource fuente() => GatewayAsignacionDataSource(
    GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-de-prueba',
      correlationId: () => 'corr-test',
      maxRetries: 0,
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    ),
    tenantIdSesion: () => 'tenant-a',
    generarClave: () => 'clave-${++claves}',
  );

  AsignacionRepositoryImpl repo() => AsignacionRepositoryImpl(
    fuente(),
    logger: StructuredLogger(canal: 'test', sink: (_) {}),
  );

  Map<String, dynamic> cuerpo(http.Request r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  setUp(() {
    alGateway = [];
    claves = 0;
    responder = (_) => http.Response(
      jsonEncode({
        'items': [_oferta()],
        'total': 1,
        'correlationId': 'c',
      }),
      200,
      headers: _json,
    );
  });

  test('listar: GET /api/v1/dispatch/offers/me con el JWT, sin ids', () async {
    final items = await repo().listar();

    final r = alGateway.single;
    expect(r.method, 'GET');
    expect(r.url.toString(), 'http://gateway.local/api/v1/dispatch/offers/me');
    expect(r.headers['Authorization'], 'Bearer jwt-de-prueba');
    expect(r.headers['X-Correlation-ID'], 'corr-test');
    final s = items.single;
    expect(s.id, _id);
    expect(s.estaDisponible, isTrue);
    expect(s.descripcion, 'Gotea el lavaplatos');
    expect(s.cantidadFotos, 2);
    expect(s.direccion, isNull);
  });

  test('un 200 sin items no se toma como bandeja vacía', () async {
    responder = (_) => http.Response('{"total":0}', 200, headers: _json);

    await expectLater(
      repo().listar(),
      throwsA(
        isA<AsignacionFailure>().having(
          (f) => f.tipo,
          'tipo',
          AsignacionErrorTipo.desconocido,
        ),
      ),
    );
  });

  test('aceptar: POST accept con cuerpo vacío y una Idempotency-Key por toque; '
      'luego lee la bandeja para traer la dirección', () async {
    responder = (r) => r.method == 'POST'
        ? http.Response(
            jsonEncode({
              'requestId': _id,
              'status': 'ASSIGNED',
              'isRetry': false,
            }),
            200,
            headers: _json,
          )
        : http.Response(
            jsonEncode({
              'items': [_oferta(mia: true)],
            }),
            200,
            headers: _json,
          );

    final r1 = repo();
    final asignada = await r1.aceptar(_id);
    await r1.aceptar(_id);

    final posts = alGateway.where((r) => r.method == 'POST').toList();
    expect(posts.first.url.path, '/api/v1/dispatch/requests/$_id/accept');
    expect(cuerpo(posts.first), isEmpty);
    expect(posts.map((r) => r.headers['Idempotency-Key']), [
      'clave-1',
      'clave-2',
    ]);
    expect(asignada.esMia, isTrue);
    expect(asignada.estado, EstadoSolicitud.asignada);
    expect(asignada.direccion, 'Calle 1 # 2-3');
  });

  test('rechazar: POST reject con el código del motivo', () async {
    responder = (_) => http.Response('{"status":"REJECTED"}', 200);

    await repo().rechazar(_id, motivo: MotivoRechazo.fueraDeZona);
    await repo().rechazar(_id);

    expect(alGateway.first.url.path, '/api/v1/dispatch/requests/$_id/reject');
    expect(cuerpo(alGateway.first), {'motivo': 'FUERA_DE_ZONA'});
    expect(cuerpo(alGateway.last), {'motivo': null});
  });

  test('los errores de Dispatch se traducen por code', () async {
    final casos = <http.Response, AsignacionErrorTipo>{
      _error(409, 'MANI-SOL-409'): AsignacionErrorTipo.yaNoDisponible,
      _error(409, 'MANI-DSP-409R'): AsignacionErrorTipo.yaRechazada,
      _error(409, 'MANI-DSP-409E'): AsignacionErrorTipo.yaNoDisponible,
      _error(403, 'MANI-SOL-403V'): AsignacionErrorTipo.aliadoNoVerificado,
      _error(404, 'MANI-SOL-404'): AsignacionErrorTipo.noEncontrada,
      _error(503, 'CORE_SERVICE_UNAVAILABLE'):
          AsignacionErrorTipo.servicioNoDisponible,
    };
    for (final caso in casos.entries) {
      responder = (_) => caso.key;
      await expectLater(
        repo().aceptar(_id),
        throwsA(
          isA<AsignacionFailure>().having((f) => f.tipo, 'tipo', caso.value),
        ),
        reason: caso.key.body,
      );
    }
  });

  test('sin red: sinConexion', () async {
    final ds = GatewayAsignacionDataSource(
      GatewayClient(
        baseUrl: 'http://gateway.local',
        tokenProvider: () async => null,
        maxRetries: 0,
        httpClient: MockClient((_) => throw http.ClientException('caída')),
      ),
    );

    await expectLater(
      AsignacionRepositoryImpl(
        ds,
        logger: StructuredLogger(canal: 'test', sink: (_) {}),
      ).listar(),
      throwsA(
        isA<AsignacionFailure>().having(
          (f) => f.tipo,
          'tipo',
          AsignacionErrorTipo.sinConexion,
        ),
      ),
    );
    expect(ds.tenantIdSesion, isNull);
  });
}
