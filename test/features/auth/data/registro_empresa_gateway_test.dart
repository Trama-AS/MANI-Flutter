import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// US-02.1.2-M3: el registro de aliado empresa sale por el Gateway y nunca
/// toca Supabase directamente.
void main() {
  late List<http.Request> alGateway;
  late List<http.BaseRequest> aSupabase;
  late http.Response Function(http.Request) responder;

  AuthRemoteDataSource datasource() {
    final supabase = SupabaseClient(
      'http://supabase.local',
      'anon-key',
      httpClient: MockClient((r) async {
        aSupabase.add(r);
        return http.Response('{}', 200);
      }),
    );
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => null,
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return AuthRemoteDataSource(client: supabase, gateway: gateway);
  }

  Map<String, String> doc(String tipo, String nombre, String contenido) => {
    'tipo_documento': tipo,
    'nombre_archivo': nombre,
    'contenido_base64': base64Encode(utf8.encode(contenido)),
  };

  Future<Map<String, dynamic>> registrar(
    IAuthRemoteDataSource ds, {
    List<Map<String, String>>? documentos,
    String? telefono = '3001234567',
  }) => ds.registrarAliadoEmpresa(
    email: '  admin@plomeria.co ',
    password: 'Secreta123!',
    razonSocial: ' Plomería SAS ',
    nit: '900123456-7',
    tenantId: 'tenant-a',
    nombreRepresentante: 'Ana Gómez',
    docRepresentante: '',
    telefonoContacto: telefono,
    categoriaId: 'cat-1',
    documentosKYC:
        documentos ??
        [
          doc('CAMARA_COMERCIO', 'camara.pdf', 'PDF-CAMARA'),
          doc('RUT_EMPRESA', 'rut.pdf', 'PDF-RUT'),
        ],
  );

  setUp(() {
    alGateway = [];
    aSupabase = [];
    responder = (_) => http.Response(
      jsonEncode({'usuario_id': 'u-1', 'estado_verificacion': 'PENDIENTE'}),
      201,
      headers: {'content-type': 'application/json'},
    );
  });

  group('datasource', () {
    test(
      'CC-1/CA-1: una sola petición, al Gateway, ninguna a Supabase',
      () async {
        await registrar(datasource());

        expect(aSupabase, isEmpty);
        expect(alGateway, hasLength(1));
        final r = alGateway.single;
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          'http://gateway.local${AuthRemoteDataSource.rutaRegistroEmpresa}',
        );
        expect(r.headers['X-Correlation-ID'], 'corr-test');
      },
    );

    test('CA-3: los documentos viajan como archivos en el multipart', () async {
      await registrar(datasource());

      final cuerpo = utf8.decode(alGateway.single.bodyBytes);
      expect(cuerpo, contains('name="camara_comercio"; filename="camara.pdf"'));
      expect(cuerpo, contains('PDF-CAMARA'));
      expect(cuerpo, contains('name="rut_empresa"; filename="rut.pdf"'));
      expect(cuerpo, contains('PDF-RUT'));
      expect(cuerpo, isNot(contains('ruta_storage')));
    });

    test('envía los datos limpios y omite los opcionales vacíos', () async {
      await registrar(datasource(), telefono: null);

      final cuerpo = utf8.decode(alGateway.single.bodyBytes);
      String campo(String n) => RegExp(
        'name="$n"(?:\r\n[^\r]+)*\r\n\r\n([^\r]*)',
      ).firstMatch(cuerpo)!.group(1)!;
      expect(campo('email'), 'admin@plomeria.co');
      expect(campo('razon_social'), 'Plomería SAS');
      expect(campo('nit'), '900123456-7');
      expect(campo('nombre_representante'), 'Ana Gómez');
      expect(campo('categoria_id'), 'cat-1');
      expect(cuerpo, isNot(contains('name="doc_representante"')));
      expect(cuerpo, isNot(contains('name="telefono_contacto"')));
    });

    test('CC-2/CA-6: el tenant no viaja en el cuerpo, solo como slug '
        'de preautenticación (X-Tenant-Slug ADR-0018)', () async {
      await registrar(datasource());

      final r = alGateway.single;
      final cuerpo = utf8.decode(r.bodyBytes);
      expect(cuerpo, isNot(contains('tenant')));
      expect(r.headers[AuthRemoteDataSource.headerTenantSlug], 'tenant-a');
      expect(r.headers.containsKey('X-Tenant-Id'), isFalse);
      expect(r.headers.containsKey('X-Tenant-ID'), isFalse);
    });

    test('mantiene la forma de respuesta que espera la UI', () async {
      final res = await registrar(datasource());

      expect(res['success'], isTrue);
      expect(res['usuario_id'], 'u-1');
      expect(res['estado_verificacion'], 'PENDIENTE');
    });

    test('documento sin contenido no se envía', () async {
      final sinContenido = {
        'tipo_documento': 'CAMARA_COMERCIO',
        'nombre_archivo': 'camara.pdf',
        'contenido_base64': '',
      };

      await expectLater(
        registrar(datasource(), documentos: [sinContenido]),
        throwsA(anything),
      );
      expect(alGateway, isEmpty);
    });
  });

  group('repositorio: errores visibles (CA-4)', () {
    Future<AuthFailure> fallo(http.Response respuesta) async {
      responder = (_) => respuesta;
      final repo = AuthRepositoryImpl(remoteDataSource: datasource());
      try {
        await repo.registrarAliadoEmpresa(
          email: 'a@b.co',
          password: 'x',
          razonSocial: 'R',
          nit: '1',
          tenantId: 't',
          nombreRepresentante: 'N',
          documentosKYC: [doc('CAMARA_COMERCIO', 'c.pdf', 'C')],
        );
      } on AuthFailure catch (e) {
        return e;
      }
      fail('debía lanzar AuthFailure');
    }

    http.Response json(int s, Map<String, Object> b) => http.Response(
      jsonEncode(b),
      s,
      headers: {'content-type': 'application/json'},
    );

    test('400 muestra el campo faltante', () async {
      final e = await fallo(json(400, {'message': 'Falta camara_comercio'}));
      expect(e.message, 'Falta camara_comercio');
    });

    test('401 pide volver a iniciar sesión', () async {
      final e = await fallo(json(401, {'error': 'invalid token'}));
      expect(e.message, contains('Inicia sesión'));
    });

    test('409 informa la empresa duplicada', () async {
      final e = await fallo(
        json(409, {'message': 'La empresa ya está registrada'}),
      );
      expect(e.message, 'La empresa ya está registrada');
    });

    test('5xx da un mensaje genérico sin detalles internos', () async {
      final e = await fallo(json(500, {'message': 'TypeError at line 42'}));
      expect(e.message, isNot(contains('TypeError')));
      expect(e.message, isNot(startsWith('Error en registro')));
    });
  });
}
