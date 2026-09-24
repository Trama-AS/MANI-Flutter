import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';

import '../../domain/entities/motivo_rechazo.dart';
import '../../domain/entities/solicitud_entity.dart';
import '../../domain/failures/asignacion_failure.dart';
import '../../domain/repositories/i_asignacion_repository.dart';
import '../datasources/asignacion_remote_datasource.dart';
import '../models/solicitud_model.dart';

/// Implementación Supabase del despacho de solicitudes.
///
/// La exclusión la garantiza el servidor con un UPDATE condicional atómico
/// (DD-MANI §7.1); aquí solo se traducen sus códigos y se registra cada
/// intento con su duración (QS-09 exige respuesta < 500 ms).
class AsignacionRepositoryImpl implements IAsignacionRepository {
  AsignacionRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.asignacion');

  final AsignacionRemoteDataSource _ds;
  final StructuredLogger _log;

  static const _eventoAceptar = 'US-04.1.4.aceptar_solicitud';
  static const _eventoRechazar = 'US-04.1.4.rechazar_solicitud';

  @override
  Future<List<SolicitudEntity>> listar() => _guard(
    () async => (await _ds.listar())
        .map<SolicitudEntity>(SolicitudModel.fromJson)
        .toList(),
  );

  @override
  Future<SolicitudEntity> aceptar(String solicitudId) => _registrar(
    evento: _eventoAceptar,
    solicitudId: solicitudId,
    exito: 'solicitud_asignada',
    fallo: 'solicitud_no_asignada',
    op: () async => SolicitudModel.fromJson(await _ds.aceptar(solicitudId)),
  );

  @override
  Future<void> rechazar(String solicitudId, {MotivoRechazo? motivo}) =>
      _registrar(
        evento: _eventoRechazar,
        solicitudId: solicitudId,
        exito: 'solicitud_rechazada',
        fallo: 'solicitud_no_rechazada',
        extra: {'motivo': motivo?.codigo},
        op: () => _ds.rechazar(solicitudId, motivo?.codigo),
      );

  /// Ejecuta [op] y deja un log JSON con resultado y duración. Sin datos
  /// personales: solo ids, códigos y tiempos.
  Future<T> _registrar<T>({
    required String evento,
    required String solicitudId,
    required String exito,
    required String fallo,
    required Future<T> Function() op,
    Map<String, Object?> extra = const {},
  }) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    try {
      final r = await _guard(op);
      _log.info(
        exito,
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': evento,
          'solicitud_id': solicitudId,
          'duracion_ms': sw.elapsedMilliseconds,
          ...extra,
        },
      );
      return r;
    } on AsignacionFailure catch (f) {
      _log.error(
        fallo,
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': evento,
          'solicitud_id': solicitudId,
          'error': f.tipo.name,
          'duracion_ms': sw.elapsedMilliseconds,
          ...extra,
        },
      );
      rethrow;
    }
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw mapearMensaje(e.message);
    } on AuthException catch (e) {
      throw AsignacionFailure(AsignacionErrorTipo.sinSesion, e.message);
    } on AsignacionFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw AsignacionFailure(AsignacionErrorTipo.sinConexion, s);
      }
      throw AsignacionFailure(AsignacionErrorTipo.desconocido, s);
    }
  }

  /// Traduce el prefijo `MANI-SOL-*` de las RPC. El orden importa: los códigos
  /// con sufijo (403V, 403E, 409A) van antes que su versión corta.
  static AsignacionFailure mapearMensaje(String mensaje) {
    const tabla = <String, AsignacionErrorTipo>{
      'MANI-SOL-401': AsignacionErrorTipo.sinSesion,
      'MANI-SOL-403V': AsignacionErrorTipo.aliadoNoVerificado,
      'MANI-SOL-403E': AsignacionErrorTipo.noElegible,
      'MANI-SOL-403': AsignacionErrorTipo.noEsAliado,
      'MANI-SOL-404': AsignacionErrorTipo.noEncontrada,
      'MANI-SOL-409A': AsignacionErrorTipo.yaEsTuya,
      'MANI-SOL-409': AsignacionErrorTipo.yaNoDisponible,
      'MANI-SOL-422M': AsignacionErrorTipo.motivoInvalido,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key)) {
        return AsignacionFailure(e.value, mensaje);
      }
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return AsignacionFailure(AsignacionErrorTipo.sinSesion, mensaje);
    }
    return AsignacionFailure(AsignacionErrorTipo.desconocido, mensaje);
  }
}
