import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/asignacion/data/datasources/asignacion_remote_datasource.dart';
import 'package:mani/features/asignacion/data/repositories/asignacion_repository_impl.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';

import 'fakes.dart';

Matcher _falla(AsignacionErrorTipo tipo) =>
    throwsA(isA<AsignacionFailure>().having((f) => f.tipo, 'tipo', tipo));

void main() {
  const solicitudId = 'sol-001';
  const tenant = 'tenant-a';

  late ServidorAsignacionFake servidor;
  late List<Map<String, dynamic>> logs;

  AsignacionRepositoryImpl repoDe(String? aliadoId) => AsignacionRepositoryImpl(
    servidor.sesion(aliadoId),
    logger: StructuredLogger(
      canal: 'test',
      sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
    ),
  );

  setUp(() {
    logs = [];
    servidor = ServidorAsignacionFake(latencia: const Duration(milliseconds: 5))
      ..publicar(
        id: solicitudId,
        tenantId: tenant,
        reglas: {'mascotas': false, 'parqueadero': true},
      );
    for (final id in ['aliado-a', 'aliado-b', 'c', 'd', 'e']) {
      servidor.registrarAliado(id, AliadoFake(tenantId: tenant));
    }
  });

  group('RF-14 · aceptación de solicitud', () {
    test('el primer aliado en aceptar se queda con la solicitud', () async {
      final resultado = await repoDe('aliado-a').aceptar(solicitudId);

      expect(resultado.estado, EstadoSolicitud.asignada);
      expect(resultado.esMia, isTrue);
      expect(servidor.fila(solicitudId)['aliado_id'], 'aliado-a');
    });

    test('un segundo aliado recibe ya_no_disponible', () async {
      await repoDe('aliado-a').aceptar(solicitudId);

      await expectLater(
        repoDe('aliado-b').aceptar(solicitudId),
        _falla(AsignacionErrorTipo.yaNoDisponible),
      );
    });

    test('el reintento del mismo aliado es idempotente', () async {
      final repo = repoDe('aliado-a');
      final primera = await repo.aceptar(solicitudId);

      final reintento = await repo.aceptar(solicitudId);

      expect(reintento, primera);
      expect(servidor.eventos, hasLength(1), reason: 'sin efectos duplicados');
    });

    test('una solicitud inexistente no se puede aceptar', () async {
      await expectLater(
        repoDe('aliado-a').aceptar('sol-inexistente'),
        _falla(AsignacionErrorTipo.noEncontrada),
      );
    });

    test('una solicitud de otro tenant responde no encontrada', () async {
      servidor.publicar(id: 'sol-b', tenantId: 'tenant-b');
      await expectLater(
        repoDe('aliado-a').aceptar('sol-b'),
        _falla(AsignacionErrorTipo.noEncontrada),
      );
    });

    test('al aceptar se revela la dirección y se registra el evento', () async {
      final antes = (await repoDe(
        'aliado-a',
      ).listar()).firstWhere((s) => s.id == solicitudId);
      expect(antes.direccion, isNull, reason: 'privada antes de aceptar');
      expect(antes.reglasSitio, isNotEmpty, reason: 'QS-06: reglas visibles');

      final asignada = await repoDe('aliado-a').aceptar(solicitudId);

      expect(asignada.direccion, 'Calle Colima 120, Apto 401');
      expect(servidor.eventos.single['tipo_evento'], 'SOLICITUD_ASIGNADA');
      expect(servidor.notificaciones, hasLength(1));
    });
  });

  group('RNF-05 · exclusión concurrente', () {
    test(
      'cinco aceptaciones simultáneas producen exactamente una asignación',
      () async {
        final aliados = ['aliado-a', 'aliado-b', 'c', 'd', 'e'];

        final resultados = await Future.wait(
          aliados.map(
            (aliado) => repoDe(aliado)
                .aceptar(solicitudId)
                .then<Object>((s) => s)
                .catchError((Object e) => e),
          ),
        );

        final asignaciones = resultados.whereType<SolicitudEntity>().toList();
        final rechazos = resultados
            .whereType<AsignacionFailure>()
            .where((f) => f.tipo == AsignacionErrorTipo.yaNoDisponible)
            .toList();

        expect(asignaciones, hasLength(1));
        expect(rechazos, hasLength(aliados.length - 1));
        expect(servidor.eventos, hasLength(1));
        expect(servidor.fila(solicitudId)['aliado_id'], isNotNull);
      },
    );
  });

  group('Rechazar', () {
    test('oculta la solicitud solo para quien la rechaza', () async {
      await repoDe(
        'aliado-a',
      ).rechazar(solicitudId, motivo: MotivoRechazo.sinDisponibilidad);

      expect(await repoDe('aliado-a').listar(), isEmpty);
      expect((await repoDe('aliado-b').listar()).single.id, solicitudId);
      expect(servidor.fila(solicitudId)['estado'], 'PENDIENTE');
      expect(
        servidor.rechazos[(solicitudId, 'aliado-a')],
        'SIN_DISPONIBILIDAD',
      );
    });

    test('no se puede rechazar una solicitud que ya es tuya', () async {
      final repo = repoDe('aliado-a');
      await repo.aceptar(solicitudId);
      await expectLater(
        repo.rechazar(solicitudId, motivo: MotivoRechazo.sinDisponibilidad),
        _falla(AsignacionErrorTipo.yaEsTuya),
      );
    });

    test('rechazar dos veces es idempotente', () async {
      final repo = repoDe('aliado-a');
      await repo.rechazar(solicitudId, motivo: MotivoRechazo.fueraDeZona);
      await repo.rechazar(
        solicitudId,
        motivo: MotivoRechazo.otro,
        detalle: 'Tengo otro compromiso',
      );
      expect(servidor.rechazos[(solicitudId, 'aliado-a')], 'FUERA_DE_ZONA');
    });

    test('«Otro» llega con su detalle', () async {
      await repoDe('aliado-a').rechazar(
        solicitudId,
        motivo: MotivoRechazo.otro,
        detalle: 'Mi herramienta está en reparación',
      );
      expect(servidor.rechazos[(solicitudId, 'aliado-a')], 'OTRO');
      expect(
        servidor.detallesRechazo[(solicitudId, 'aliado-a')],
        'Mi herramienta está en reparación',
      );
    });

    test('un 422D de Dispatch se traduce a detalleInvalido', () async {
      await expectLater(
        repoDe('aliado-a').rechazar(solicitudId, motivo: MotivoRechazo.otro),
        _falla(AsignacionErrorTipo.detalleInvalido),
      );
      expect(servidor.rechazos, isEmpty);
    });
  });

  group('Elegibilidad y permisos', () {
    test('solo lista solicitudes de mis categorías y zonas', () async {
      servidor
        ..publicar(id: 'otra-cat', tenantId: tenant, categoria: 'Pintura')
        ..publicar(
          id: 'otra-zona',
          tenantId: tenant,
          zona: 'Polanco',
          zonaPadre: 'Miguel Hidalgo',
        );
      final ids = (await repoDe('aliado-a').listar()).map((s) => s.id);
      expect(ids, [solicitudId]);
    });

    test('no puede aceptar fuera de su categoría o zona', () async {
      servidor.publicar(id: 'otra-cat', tenantId: tenant, categoria: 'Pintura');
      await expectLater(
        repoDe('aliado-a').aceptar('otra-cat'),
        _falla(AsignacionErrorTipo.noElegible),
      );
    });

    test('un aliado no verificado no puede ver ni aceptar', () async {
      servidor.aliados['aliado-a']!.verificado = false;
      await expectLater(
        repoDe('aliado-a').listar(),
        _falla(AsignacionErrorTipo.aliadoNoVerificado),
      );
      await expectLater(
        repoDe('aliado-a').aceptar(solicitudId),
        _falla(AsignacionErrorTipo.aliadoNoVerificado),
      );
    });

    test('sin sesión y sin perfil de aliado', () async {
      await expectLater(
        repoDe(null).listar(),
        _falla(AsignacionErrorTipo.sinSesion),
      );
      await expectLater(
        repoDe('cliente-x').listar(),
        _falla(AsignacionErrorTipo.noEsAliado),
      );
    });
  });

  group('Trazabilidad', () {
    test('registra log INFO con duración al ganar y ERROR al perder', () async {
      await repoDe('aliado-a').aceptar(solicitudId);
      await expectLater(
        repoDe('aliado-b').aceptar(solicitudId),
        _falla(AsignacionErrorTipo.yaNoDisponible),
      );

      final gano = logs.first;
      final perdio = logs.last;
      for (final campo in [
        'timestamp',
        'level',
        'service_id',
        'trace_id',
        'tenant_id',
        'message',
      ]) {
        expect(gano.containsKey(campo), isTrue, reason: campo);
      }
      expect(gano['level'], 'INFO');
      expect(gano['event'], 'US-04.1.4.aceptar_solicitud');
      expect(gano['duracion_ms'], isA<int>());
      expect(perdio['level'], 'ERROR');
      expect(perdio['error'], 'yaNoDisponible');
    });

    test('errores de red se traducen a sinConexion', () async {
      final repo = AsignacionRepositoryImpl(
        _DsCaido(),
        logger: StructuredLogger(canal: 'test', sink: (_) {}),
      );
      await expectLater(repo.listar(), _falla(AsignacionErrorTipo.sinConexion));
    });
  });

  group('Errores de Dispatch y Core por el Gateway', () {
    test('aceptar lo que ya rechacé responde yaRechazada (409R)', () async {
      final repo = repoDe('aliado-a');
      await repo.rechazar(solicitudId, motivo: MotivoRechazo.fueraDeZona);
      await expectLater(
        repo.aceptar(solicitudId),
        _falla(AsignacionErrorTipo.yaRechazada),
      );
      expect(servidor.fila(solicitudId)['aliado_id'], isNull);
    });

    test('mapearGateway usa el code y, sin él, el status', () {
      const porCodigo = {
        'MANI-DSP-401': AsignacionErrorTipo.sinSesion,
        'MANI-SOL-403V': AsignacionErrorTipo.aliadoNoVerificado,
        'MANI-SOL-403E': AsignacionErrorTipo.noElegible,
        'MANI-SOL-403O': AsignacionErrorTipo.noElegible,
        'MANI-DSP-403': AsignacionErrorTipo.noEsAliado,
        'MANI-DSP-404': AsignacionErrorTipo.noEncontrada,
        'MANI-SOL-409': AsignacionErrorTipo.yaNoDisponible,
        'MANI-SOL-409E': AsignacionErrorTipo.yaNoDisponible,
        'MANI-DSP-409E': AsignacionErrorTipo.yaNoDisponible,
        'MANI-DSP-409A': AsignacionErrorTipo.yaEsTuya,
        'MANI-DSP-409R': AsignacionErrorTipo.yaRechazada,
        'MANI-SOL-422M': AsignacionErrorTipo.motivoInvalido,
        'MANI-SOL-422D': AsignacionErrorTipo.detalleInvalido,
        'CORE_SERVICE_UNAVAILABLE': AsignacionErrorTipo.servicioNoDisponible,
        'DATABASE_UNAVAILABLE': AsignacionErrorTipo.servicioNoDisponible,
      };
      porCodigo.forEach((code, tipo) {
        final status = switch (code) {
          'CORE_SERVICE_UNAVAILABLE' || 'DATABASE_UNAVAILABLE' => 503,
          _ => int.parse(code.replaceAll(RegExp(r'\D'), '')),
        };
        expect(
          AsignacionRepositoryImpl.mapearGateway(
            GatewayException.fromStatus(status, cuerpo: {'code': code}),
          ).tipo,
          tipo,
          reason: code,
        );
      });

      const porStatus = {
        401: AsignacionErrorTipo.sinSesion,
        403: AsignacionErrorTipo.noEsAliado,
        404: AsignacionErrorTipo.noEncontrada,
        409: AsignacionErrorTipo.yaNoDisponible,
        422: AsignacionErrorTipo.motivoInvalido,
        502: AsignacionErrorTipo.servicioNoDisponible,
        418: AsignacionErrorTipo.desconocido,
      };
      porStatus.forEach((status, tipo) {
        expect(
          AsignacionRepositoryImpl.mapearGateway(
            GatewayException.fromStatus(status),
          ).tipo,
          tipo,
          reason: '$status',
        );
      });
      expect(
        AsignacionRepositoryImpl.mapearGateway(
          const GatewayException(message: 'sin red'),
        ).tipo,
        AsignacionErrorTipo.sinConexion,
      );
    });

    test(
      'si la bandeja no responde tras ganar, igual informa la asignación',
      () async {
        final repo = AsignacionRepositoryImpl(
          _BandejaCaida(servidor.sesion('aliado-a')),
          logger: StructuredLogger(canal: 'test', sink: (_) {}),
        );

        final asignada = await repo.aceptar(solicitudId);

        expect(asignada.id, solicitudId);
        expect(asignada.esMia, isTrue);
        expect(asignada.estado, EstadoSolicitud.asignada);
        expect(servidor.fila(solicitudId)['aliado_id'], 'aliado-a');
      },
    );
  });
}

/// Datasource sin red: el `GatewayClient` responde sin status.
class _DsCaido implements AsignacionRemoteDataSource {
  Never _sinRed() => throw const GatewayException(message: 'sin red');

  @override
  Future<List<Map<String, dynamic>>> listar() async => _sinRed();

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async => _sinRed();

  @override
  Future<void> rechazar(
    String solicitudId,
    String motivo,
    String? detalle,
  ) async => _sinRed();

  @override
  String? get tenantIdSesion => null;
}

/// Acepta de verdad, pero la bandeja falla justo después.
class _BandejaCaida implements AsignacionRemoteDataSource {
  _BandejaCaida(this._ds);

  final AsignacionRemoteDataSource _ds;

  @override
  Future<List<Map<String, dynamic>>> listar() async =>
      errorGateway(503, 'CORE_SERVICE_UNAVAILABLE');

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) =>
      _ds.aceptar(solicitudId);

  @override
  Future<void> rechazar(String solicitudId, String motivo, String? detalle) =>
      _ds.rechazar(solicitudId, motivo, detalle);

  @override
  String? get tenantIdSesion => _ds.tenantIdSesion;
}
