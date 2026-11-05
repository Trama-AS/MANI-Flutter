import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/profiles/verification/data/datasources/verificacion_remote_datasource.dart';
import 'package:mani/features/profiles/verification/data/repositories/verificacion_aliados_repository_impl.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';

import '../fakes.dart';

/// US-02.1.3 (SCRUM-1384): la bandeja de verificación sale solo por el API
/// Gateway hacia Core Node; ninguna petición va a las RPC ni al Storage de
/// Supabase (ADR-0027). El tenant lo deriva Core del JWT.
void main() {
  late List<http.Request> peticiones;
  late http.Response Function(http.Request) responder;

  http.Response json(Object cuerpo, [int status = 200]) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  /// Cuerpo de error tal como lo serializa `errorHandler.middleware.js`.
  http.Response errorCore(int status, String code) => json({
    'error': '$code: detalle',
    'code': code,
    'correlationId': 'corr-test',
  }, status);

  Map<String, dynamic> vista({
    String id = 'a1',
    String estado = 'PENDIENTE',
    String? motivo,
  }) => {
    'id': id,
    'tipo': 'PERSONA_NATURAL',
    'nombre': 'Carlos Mendoza',
    'email': 'carlos@correo.com',
    'estado_verificacion': estado,
    'fecha_registro': '2026-10-20T15:00:00.000Z',
    'motivo_rechazo': motivo,
    'fecha_verificacion': null,
    'categorias': ['Plomería'],
    'documentos': [
      {
        'id': 'd1',
        'tipo_documento': 'CEDULA_CIUDADANIA',
        'ruta_storage': 'kyc/tenant-a/a1/cedula.pdf',
        'estado': estado,
        'fecha_carga': '2026-10-20T15:00:00.000Z',
      },
    ],
  };

  VerificacionRemoteDataSource datasource() => GatewayVerificacionDataSource(
    GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-admin',
      correlationId: () => 'corr-test',
      maxRetries: 0,
      httpClient: MockClient((r) async {
        peticiones.add(r);
        return responder(r);
      }),
    ),
  );

  VerificacionAliadosRepositoryImpl repositorio() =>
      VerificacionAliadosRepositoryImpl(
        datasource(),
        logger: StructuredLogger(canal: 'test', sink: (_) {}),
      );

  Matcher falla(VerificacionErrorTipo tipo) =>
      throwsA(isA<VerificacionFailure>().having((f) => f.tipo, 'tipo', tipo));

  setUp(() {
    peticiones = [];
    responder = (_) => json(<Object>[]);
  });

  group('C1 - operaciones por el Gateway', () {
    test('listar: GET con JWT y X-Correlation-ID, mapea la vista', () async {
      responder = (_) => json([vista(), vista(id: 'a2', estado: 'VERIFICADO')]);

      final lista = await repositorio().listarSolicitudes();

      final r = peticiones.single;
      expect(r.method, 'GET');
      expect(
        r.url.toString(),
        'http://gateway.local/api/v1/core/aliados/verificacion',
      );
      expect(r.headers['Authorization'], 'Bearer jwt-admin');
      expect(r.headers['X-Correlation-ID'], 'corr-test');
      expect(lista.map((a) => a.id), ['a1', 'a2']);
      expect(lista.last.estado, EstadoVerificacion.aprobado);
      expect(lista.first.documentos.single.aliadoId, 'a1');
    });

    test('detalle: GET /aliados/:id/verificacion', () async {
      responder = (_) => json(vista());

      final a = await repositorio().obtenerDetalle('a1');

      expect(peticiones.single.method, 'GET');
      expect(
        peticiones.single.url.path,
        '/api/v1/core/aliados/a1/verificacion',
      );
      expect(a.nombre, 'Carlos Mendoza');
    });

    test('aprobar: PATCH con decision VERIFICADO y sin motivo', () async {
      responder = (_) => json(vista(estado: 'VERIFICADO'));

      final a = await repositorio().resolver(
        'a1',
        const DecisionVerificacion.aprobar(),
      );

      final r = peticiones.single;
      expect(r.method, 'PATCH');
      expect(r.url.path, '/api/v1/core/aliados/a1/verificacion');
      expect(jsonDecode(r.body), {'decision': 'VERIFICADO'});
      expect(a.estado, EstadoVerificacion.aprobado);
    });

    test('rechazar: PATCH con decision RECHAZADO y el motivo', () async {
      responder = (_) =>
          json(vista(estado: 'RECHAZADO', motivo: 'Documento ilegible'));

      final a = await repositorio().resolver(
        'a1',
        DecisionVerificacion.rechazar('Documento ilegible'),
      );

      expect(jsonDecode(peticiones.single.body), {
        'decision': 'RECHAZADO',
        'motivo': 'Documento ilegible',
      });
      expect(a.motivoRechazo, 'Documento ilegible');
    });

    test(
      'urlDocumento: GET /aliados/:id/documentos/:documentoId/url',
      () async {
        responder = (_) => json({
          'url': 'https://storage.test/sign/cedula.pdf?token=abc',
          'signedUrl': 'https://storage.test/sign/cedula.pdf?token=abc',
          'expiresIn': 300,
        });

        final url = await repositorio().urlDocumento(
          doc('d1', ruta: 'kyc/tenant-a/a1/cedula.pdf', aliadoId: 'a1'),
        );

        expect(peticiones.single.method, 'GET');
        expect(
          peticiones.single.url.path,
          '/api/v1/core/aliados/a1/documentos/d1/url',
        );
        expect(url.queryParameters['token'], 'abc');
      },
    );
  });

  group('C2 - escenarios negativos', () {
    test('409 MANI-VER-409 se traduce a yaResuelta', () async {
      responder = (_) => errorCore(409, 'MANI-VER-409');
      await expectLater(
        repositorio().resolver('a1', const DecisionVerificacion.aprobar()),
        falla(VerificacionErrorTipo.yaResuelta),
      );
    });

    test('422 MANI-VER-422M se traduce a motivoInvalido', () async {
      responder = (_) => errorCore(422, 'MANI-VER-422M');
      await expectLater(
        // El dominio ya exige 10..500 caracteres; aquí se prueba que, si Core
        // aun así lo rechaza, el código del servidor llega bien traducido.
        repositorio().resolver(
          'a1',
          DecisionVerificacion.rechazar('Documento ilegible'),
        ),
        falla(VerificacionErrorTipo.motivoInvalido),
      );
    });

    test('422 MANI-VER-422K se traduce a sinDocumentos', () async {
      responder = (_) => errorCore(422, 'MANI-VER-422K');
      await expectLater(
        repositorio().resolver('a1', const DecisionVerificacion.aprobar()),
        falla(VerificacionErrorTipo.sinDocumentos),
      );
    });

    test('documento inexistente se traduce a documentoNoDisponible', () async {
      responder = (_) => errorCore(404, 'MANI-VER-404');
      await expectLater(
        repositorio().urlDocumento(doc('d9', aliadoId: 'a1')),
        falla(VerificacionErrorTipo.documentoNoDisponible),
      );
    });

    test(
      'documento sin aliado no llama al Gateway y no está disponible',
      () async {
        await expectLater(
          repositorio().urlDocumento(doc('d1')),
          falla(VerificacionErrorTipo.documentoNoDisponible),
        );
        expect(peticiones, isEmpty);
      },
    );

    test('respuesta sin URL se trata como documento no disponible', () async {
      responder = (_) => json({'expiresIn': 300});
      await expectLater(
        repositorio().urlDocumento(doc('d1', aliadoId: 'a1')),
        falla(VerificacionErrorTipo.documentoNoDisponible),
      );
    });

    test('lista con forma inesperada lanza desconocido', () async {
      responder = (_) => json({'items': 'no es lista'});
      await expectLater(
        repositorio().listarSolicitudes(),
        falla(VerificacionErrorTipo.desconocido),
      );
    });

    test('caída de red se traduce a sinConexion', () async {
      responder = (_) => throw http.ClientException('sin red');
      await expectLater(
        repositorio().listarSolicitudes(),
        falla(VerificacionErrorTipo.sinConexion),
      );
    });

    test('sin code de negocio, se decide por el status HTTP', () {
      VerificacionErrorTipo tipo(int status) =>
          VerificacionAliadosRepositoryImpl.mapearGateway(
            GatewayException.fromStatus(status),
          ).tipo;
      expect(tipo(401), VerificacionErrorTipo.sinSesion);
      expect(tipo(403), VerificacionErrorTipo.noAutorizado);
      expect(tipo(404), VerificacionErrorTipo.noEncontrado);
      expect(tipo(409), VerificacionErrorTipo.yaResuelta);
      expect(tipo(500), VerificacionErrorTipo.desconocido);
    });
  });

  group('C3 - permisos y aislamiento de tenant', () {
    test('403 MANI-VER-403 (rol distinto de admin) es noAutorizado', () async {
      responder = (_) => errorCore(403, 'MANI-VER-403');
      await expectLater(
        repositorio().listarSolicitudes(),
        falla(VerificacionErrorTipo.noAutorizado),
      );
    });

    test('401 del Gateway (sin sesión o JWT inválido) es sinSesion', () async {
      responder = (_) => json({'error': 'Unauthorized'}, 401);
      await expectLater(
        repositorio().listarSolicitudes(),
        falla(VerificacionErrorTipo.sinSesion),
      );
    });

    test(
      'aliado de otro tenant responde 404 y se ve como noEncontrado',
      () async {
        responder = (_) => errorCore(404, 'MANI-VER-404');
        await expectLater(
          repositorio().obtenerDetalle('aliado-de-otro-tenant'),
          falla(VerificacionErrorTipo.noEncontrado),
        );
      },
    );

    test('ninguna petición envía tenant_id: Core lo toma del JWT', () async {
      final repo = repositorio();
      responder = (_) => json(<Object>[]);
      await repo.listarSolicitudes();
      responder = (_) => json(vista());
      await repo.obtenerDetalle('a1');
      responder = (_) => json(vista(estado: 'RECHAZADO'));
      await repo.resolver(
        'a1',
        DecisionVerificacion.rechazar('Documento ilegible'),
      );
      responder = (_) => json({'url': 'https://storage.test/x'});
      await repo.urlDocumento(doc('d1', aliadoId: 'a1'));

      expect(peticiones, hasLength(4));
      for (final r in peticiones) {
        expect(r.url.host, 'gateway.local');
        expect(r.url.path, startsWith('/api/v1/core/aliados/'));
        expect(r.url.toString().toLowerCase(), isNot(contains('tenant')));
        expect(r.body.toLowerCase(), isNot(contains('tenant')));
      }
    });
  });
}
