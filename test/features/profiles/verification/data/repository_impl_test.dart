import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/profiles/verification/data/models/solicitud_aliado_model.dart';
import 'package:mani/features/profiles/verification/data/repositories/verificacion_aliados_repository_impl.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/domain/entities/documento_kyc.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';

import '../fakes.dart';

Matcher _falla(VerificacionErrorTipo tipo) =>
    throwsA(isA<VerificacionFailure>().having((f) => f.tipo, 'tipo', tipo));

void main() {
  group('SolicitudAliadoModel.fromJson', () {
    test('mapea el JSON de _ver_aliado_json con documentos y categorías', () {
      final m = SolicitudAliadoModel.fromJson({
        'id': 'a1',
        'tipo': 'PERSONA_JURIDICA',
        'nombre': 'Servicios Técnicos SAS',
        'email': 'contacto@st.com',
        'estado_verificacion': 'RECHAZADO',
        'fecha_registro': '2026-09-20T15:00:00Z',
        'motivo_rechazo': 'Cámara de comercio vencida',
        'fecha_verificacion': '2026-09-21T10:00:00Z',
        'categorias': ['Electricidad', 'Plomería'],
        'documentos': [
          {
            'id': 'd1',
            'tipo_documento': 'CAMARA_COMERCIO',
            'ruta_storage': 'kyc/t/camara.pdf',
            'estado': 'RECHAZADO',
            'fecha_carga': '2026-09-20T15:00:00Z',
          },
        ],
      });

      expect(m.tipo, TipoAliado.empresa);
      expect(m.estado, EstadoVerificacion.rechazado);
      expect(m.fechaRegistro.toUtc(), DateTime.utc(2026, 9, 20, 15));
      expect(m.categorias, ['Electricidad', 'Plomería']);
      expect(m.motivoRechazo, 'Cámara de comercio vencida');
      expect(m.documentos.single.tipo, TipoDocumentoKyc.camaraComercio);
      expect(m.documentos.single.estado, EstadoDocumentoKyc.rechazado);
    });

    test('tolera campos opcionales ausentes', () {
      final m = SolicitudAliadoModel.fromJson({
        'id': 'a1',
        'fecha_registro': '2026-09-20T15:00:00Z',
      });
      expect(m.documentos, isEmpty);
      expect(m.categorias, isEmpty);
      expect(m.estado, EstadoVerificacion.pendiente);
      expect(m.fechaVerificacion, isNull);
    });
  });

  group('mapearMensaje', () {
    test('traduce cada código MANI-VER-* de la RPC', () {
      const casos = {
        'MANI-VER-401: sesión': VerificacionErrorTipo.sinSesion,
        'MANI-VER-403: rol': VerificacionErrorTipo.noAutorizado,
        'MANI-VER-404: x': VerificacionErrorTipo.noEncontrado,
        'MANI-VER-409: x': VerificacionErrorTipo.yaResuelta,
        'MANI-VER-422D: x': VerificacionErrorTipo.decisionInvalida,
        'MANI-VER-422M: x': VerificacionErrorTipo.motivoInvalido,
        'MANI-VER-422K: x': VerificacionErrorTipo.sinDocumentos,
        'JWT expired': VerificacionErrorTipo.sinSesion,
        'permission denied for function': VerificacionErrorTipo.sinSesion,
        'algo raro': VerificacionErrorTipo.desconocido,
      };
      casos.forEach((mensaje, tipo) {
        expect(
          VerificacionAliadosRepositoryImpl.mapearMensaje(mensaje).tipo,
          tipo,
          reason: mensaje,
        );
      });
    });
  });

  group('VerificacionAliadosRepositoryImpl', () {
    late ServidorVerificacionFake servidor;
    late List<Map<String, dynamic>> logs;
    late VerificacionAliadosRepositoryImpl repo;

    setUp(() {
      servidor = ServidorVerificacionFake()
        ..registrarAliado(
          id: 'a1',
          tenantId: 'tenant-a',
          nombre: 'Carlos Mendoza',
          email: 'carlos@correo.com',
          documentos: [
            (
              id: 'd1',
              tipo: 'CEDULA_CIUDADANIA',
              ruta: 'kyc/tenant-a/cedula.pdf',
            ),
          ],
        );
      logs = [];
      repo = VerificacionAliadosRepositoryImpl(
        servidor,
        logger: StructuredLogger(
          canal: 'test',
          sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
        ),
      );
    });

    test(
      'aprobar envía VERIFICADO y devuelve la entidad actualizada',
      () async {
        final r = await repo.resolver(
          'a1',
          const DecisionVerificacion.aprobar(),
        );
        expect(r.estado, EstadoVerificacion.aprobado);
        expect(servidor.estadoDe('a1'), 'VERIFICADO');
        expect(r.documentos.single.estado, EstadoDocumentoKyc.verificado);
      },
    );

    test('rechazar envía RECHAZADO con el motivo', () async {
      final r = await repo.resolver(
        'a1',
        DecisionVerificacion.rechazar('Documento ilegible'),
      );
      expect(r.estado, EstadoVerificacion.rechazado);
      expect(r.motivoRechazo, 'Documento ilegible');
      expect(servidor.notificaciones.single['decision'], 'RECHAZADO');
    });

    test(
      'registra un log estructurado sin datos personales al resolver',
      () async {
        await repo.resolver('a1', const DecisionVerificacion.aprobar());

        final log = logs.single;
        expect(log['level'], 'INFO');
        expect(log['message'], 'verificacion_resuelta');
        expect(log['event'], 'US-02.1.3.resolver_verificacion');
        expect(log['tenant_id'], 'tenant-a');
        expect(log['decision'], 'VERIFICADO');
        expect(log['trace_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
        final texto = jsonEncode(log);
        expect(texto, isNot(contains('Carlos')));
        expect(texto, isNot(contains('carlos@correo.com')));
      },
    );

    test('ante un 409 lanza yaResuelta y registra el error', () async {
      await repo.resolver('a1', const DecisionVerificacion.aprobar());
      logs.clear();

      await expectLater(
        repo.resolver(
          'a1',
          DecisionVerificacion.rechazar('Documento ilegible'),
        ),
        _falla(VerificacionErrorTipo.yaResuelta),
      );
      expect(logs.single['level'], 'ERROR');
      expect(logs.single['error'], 'yaResuelta');
    });

    test('un aliado de otro tenant responde noEncontrado', () async {
      servidor.registrarAliado(id: 'b1', tenantId: 'tenant-b', nombre: 'Otro');
      await expectLater(
        repo.obtenerDetalle('b1'),
        _falla(VerificacionErrorTipo.noEncontrado),
      );
      expect((await repo.listarSolicitudes()).map((a) => a.id), ['a1']);
    });

    test('sin rol de admin lanza noAutorizado', () async {
      servidor.rolSesion = 'ALIADO';
      await expectLater(
        repo.listarSolicitudes(),
        _falla(VerificacionErrorTipo.noAutorizado),
      );
    });

    test('errores de red se traducen a sinConexion', () async {
      servidor.errorDeRed = TimeoutException('lento');
      await expectLater(
        repo.listarSolicitudes(),
        _falla(VerificacionErrorTipo.sinConexion),
      );
    });

    test(
      'urlDocumento devuelve la URL firmada de un archivo existente',
      () async {
        servidor.archivosSubidos.add('kyc/tenant-a/cedula.pdf');
        final url = await repo.urlDocumento(
          doc('d1', ruta: 'kyc/tenant-a/cedula.pdf'),
        );
        expect(url.queryParameters['token'], 'abc');
      },
    );

    test(
      'urlDocumento de un archivo inexistente lanza documentoNoDisponible',
      () async {
        await expectLater(
          repo.urlDocumento(doc('d1', ruta: 'kyc/tenant-a/no-existe.pdf')),
          _falla(VerificacionErrorTipo.documentoNoDisponible),
        );
      },
    );

    test('urlDocumento sin red conserva sinConexion', () async {
      servidor.errorDeRed = TimeoutException('lento');
      await expectLater(
        repo.urlDocumento(doc('d1')),
        _falla(VerificacionErrorTipo.sinConexion),
      );
    });
  });
}
