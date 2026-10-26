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

import '../fakes.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _solicitud = 'sol-001';
const _tenant = 'tenant-a';

Matcher _falla(AsignacionErrorTipo tipo) =>
    throwsA(isA<AsignacionFailure>().having((f) => f.tipo, 'tipo', tipo));

/// Lo que llega a Dispatch por el Gateway.
class _Peticion {
  _Peticion(this.metodo, this.ruta, this.cuerpo);
  final String metodo;
  final String ruta;
  final Map<String, dynamic> cuerpo;
}

void main() {
  late ServidorAsignacionFake servidor;
  late List<_Peticion> peticiones;

  setUp(() {
    peticiones = [];
    servidor = ServidorAsignacionFake()
      ..publicar(id: _solicitud, tenantId: _tenant)
      ..registrarAliado('aliado-a', AliadoFake(tenantId: _tenant));
  });

  /// Repositorio real sobre el datasource del Gateway. [dispatch] decide la
  /// respuesta de Dispatch; el listado sale de la RPC simulada.
  AsignacionRepositoryImpl repo(
    Future<http.Response> Function(http.Request) dispatch, {
    AsignacionRemoteDataSource? rpc,
  }) {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.test',
      tokenProvider: () async => 'token',
      maxRetries: 0,
      httpClient: MockClient((req) async {
        peticiones.add(
          _Peticion(
            req.method,
            req.url.path,
            req.body.isEmpty
                ? const {}
                : jsonDecode(req.body) as Map<String, dynamic>,
          ),
        );
        return dispatch(req);
      }),
    );
    return AsignacionRepositoryImpl(
      GatewayAsignacionDataSource(
        gateway,
        rpc: rpc ?? servidor.sesion('aliado-a'),
      ),
      logger: StructuredLogger(canal: 'test', sink: (_) {}),
    );
  }

  /// Dispatch que de verdad asigna en la "BD" compartida, como el UPDATE
  /// condicional del repositorio de Dispatch.
  Future<http.Response> dispatchQueAsigna(http.Request req) async {
    await servidor.sesion('aliado-a').aceptar(_solicitud);
    return http.Response(
      jsonEncode({
        'requestId': _solicitud,
        'assignedAllyId': 'aliado-a',
        'status': 'ASSIGNED',
      }),
      200,
      headers: _json,
    );
  }

  http.Response error(int status, String error) => http.Response(
    jsonEncode({'error': error, 'status': status}),
    status,
    headers: _json,
  );

  group('TEC-18 (SCRUM-1465) · aceptar por Dispatch', () {
    test(
      'POST a /dispatch/requests/{id}/accept sin datos del aliado',
      () async {
        await repo(dispatchQueAsigna).aceptar(_solicitud);

        final p = peticiones.single;
        expect(p.metodo, 'POST');
        expect(p.ruta, '/api/v1/dispatch/requests/sol-001/accept');
        // Tenant y aliado salen del JWT en Dispatch (T4), no del cuerpo.
        expect(p.cuerpo, isEmpty);
      },
    );

    test('tras ganarla relee la bandeja y ya trae la dirección', () async {
      final asignada = await repo(dispatchQueAsigna).aceptar(_solicitud);

      expect(asignada.id, _solicitud);
      expect(asignada.estado, EstadoSolicitud.asignada);
      expect(asignada.esMia, isTrue);
      expect(asignada.direccion, 'Calle Colima 120, Apto 401');
      expect(asignada.categoria, 'Plomería');
    });

    test('si la relectura falla, la aceptación confirmada no se vuelve '
        'error', () async {
      final asignada = await repo(
        dispatchQueAsigna,
        rpc: _RpcQueFallaAlReleer(servidor.sesion('aliado-a')),
      ).aceptar(_solicitud);

      expect(asignada.id, _solicitud);
      expect(asignada.estado, EstadoSolicitud.asignada);
      expect(asignada.esMia, isTrue);
    });

    test('409 de Dispatch: otro aliado la tomó primero', () async {
      await expectLater(
        repo(
          (_) async =>
              error(409, 'La solicitud ya fue aceptada por otro profesional.'),
        ).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.yaNoDisponible),
      );
    });

    test('403 con MANI-SOL-403V: aliado sin verificar', () async {
      await expectLater(
        repo(
          (_) async => error(
            403,
            'MANI-SOL-403V: tu registro como aliado aún no está verificado.',
          ),
        ).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.aliadoNoVerificado),
      );
    });

    test('403 sin código: el rol no es aliado', () async {
      await expectLater(
        repo(
          (_) async => error(
            403,
            'Rol no autorizado: únicamente los aliados pueden aceptar solicitudes.',
          ),
        ).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.noEsAliado),
      );
    });

    test('404 de otro tenant o inexistente: ya no existe', () async {
      await expectLater(
        repo(
          (_) async => error(404, 'Solicitud no encontrada para el tenant.'),
        ).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.noEncontrada),
      );
    });

    test('401: la sesión expiró', () async {
      await expectLater(
        repo((_) async => error(401, 'Token inválido')).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.sinSesion),
      );
    });

    test(
      '503 de Dispatch no se disfraza de éxito ni de conflicto (T2)',
      () async {
        await expectLater(
          repo(
            (_) async => error(503, 'Indisponibilidad de la base de datos'),
          ).aceptar(_solicitud),
          _falla(AsignacionErrorTipo.servicioNoDisponible),
        );
        expect(servidor.fila(_solicitud)['aliado_id'], isNull);
      },
    );

    test('sin red: sin conexión', () async {
      await expectLater(
        repo(
          (_) async => throw http.ClientException('sin red'),
        ).aceptar(_solicitud),
        _falla(AsignacionErrorTipo.sinConexion),
      );
    });
  });

  group('TEC-18 (SCRUM-1465) · rechazar por Dispatch', () {
    Future<http.Response> ok(http.Request _) async => http.Response(
      jsonEncode({'requestId': _solicitud, 'status': 'REJECTED'}),
      200,
      headers: _json,
    );

    test('envía el código del motivo elegido', () async {
      await repo(ok).rechazar(_solicitud, motivo: MotivoRechazo.fueraDeZona);

      final p = peticiones.single;
      expect(p.metodo, 'POST');
      expect(p.ruta, '/api/v1/dispatch/requests/sol-001/reject');
      expect(p.cuerpo, {'motivo': 'FUERA_DE_ZONA'});
    });

    test('sin motivo no inventa uno', () async {
      await repo(ok).rechazar(_solicitud);

      expect(peticiones.single.cuerpo, isEmpty);
    });

    test(
      'un error de Dispatch llega como fallo, no como rechazo hecho',
      () async {
        await expectLater(
          repo(
            (_) async => error(503, 'Indisponibilidad de la base de datos'),
          ).rechazar(_solicitud),
          _falla(AsignacionErrorTipo.servicioNoDisponible),
        );
      },
    );
  });

  test('el listado sigue por la RPC: no llama al Gateway', () async {
    final lista = await repo(dispatchQueAsigna).listar();

    expect(lista.map((s) => s.id), [_solicitud]);
    expect(peticiones, isEmpty);
  });
}

/// La primera lectura funciona; la relectura tras aceptar falla.
class _RpcQueFallaAlReleer implements AsignacionRemoteDataSource {
  _RpcQueFallaAlReleer(this._real);
  final AsignacionRemoteDataSource _real;

  @override
  Future<List<Map<String, dynamic>>> listar() =>
      Future.error(Exception('bandeja caída'));

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) =>
      _real.aceptar(solicitudId);

  @override
  Future<void> rechazar(String solicitudId, String? motivo) =>
      _real.rechazar(solicitudId, motivo);

  @override
  String? get tenantIdSesion => _real.tenantIdSesion;
}
