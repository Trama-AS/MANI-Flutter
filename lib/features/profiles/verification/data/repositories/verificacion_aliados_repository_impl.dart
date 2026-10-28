import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/decision_verificacion.dart';
import '../../domain/entities/documento_kyc.dart';
import '../../domain/entities/solicitud_aliado.dart';
import '../../domain/failures/verificacion_failure.dart';
import '../../domain/repositories/verificacion_aliados_repository.dart';
import '../datasources/verificacion_remote_datasource.dart';
import '../models/solicitud_aliado_model.dart';

class VerificacionAliadosRepositoryImpl
    implements VerificacionAliadosRepository {
  VerificacionAliadosRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.verificacion');

  final VerificacionRemoteDataSource _ds;
  final StructuredLogger _log;

  static const _evento = 'US-02.1.3.resolver_verificacion';

  @override
  Future<List<SolicitudAliado>> listarSolicitudes() => _guard(
    () async => (await _ds.listarAliados())
        .map<SolicitudAliado>(SolicitudAliadoModel.fromJson)
        .toList(),
  );

  @override
  Future<SolicitudAliado> obtenerDetalle(String aliadoId) => _guard(
    () async =>
        SolicitudAliadoModel.fromJson(await _ds.obtenerAliado(aliadoId)),
  );

  @override
  Future<SolicitudAliado> resolver(
    String aliadoId,
    DecisionVerificacion decision,
  ) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final (codigo, motivo) = switch (decision) {
      Aprobacion() => ('VERIFICADO', null),
      Rechazo(:final motivo) => ('RECHAZADO', motivo),
    };
    final sw = Stopwatch()..start();
    try {
      final aliado = await _guard(
        () async => SolicitudAliadoModel.fromJson(
          await _ds.resolver(aliadoId, codigo, motivo),
        ),
      );
      _log.info(
        'verificacion_resuelta',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'aliado_id': aliadoId,
          'decision': codigo,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return aliado;
    } on VerificacionFailure catch (f) {
      _log.error(
        'verificacion_no_resuelta',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'aliado_id': aliadoId,
          'decision': codigo,
          'error': f.tipo.name,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      rethrow;
    }
  }

  @override
  Future<Uri> urlDocumento(DocumentoKyc documento) async {
    try {
      final url = await _guard(
        () => _ds.urlFirmada(
          documento.rutaStorage,
          aliadoId: documento.aliadoId,
          documentoId: documento.id,
        ),
      );
      return Uri.parse(url);
    } on VerificacionFailure catch (f) {
      if (f.tipo == VerificacionErrorTipo.sinConexion) rethrow;
      throw VerificacionFailure(
        VerificacionErrorTipo.documentoNoDisponible,
        f.detalle,
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    } on PostgrestException catch (e) {
      throw mapearMensaje(e.message);
    } on AuthException catch (e) {
      throw VerificacionFailure(VerificacionErrorTipo.sinSesion, e.message);
    } on StorageException catch (e) {
      throw VerificacionFailure(
        VerificacionErrorTipo.documentoNoDisponible,
        e.message,
      );
    } on VerificacionFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw VerificacionFailure(VerificacionErrorTipo.sinConexion, s);
      }
      throw VerificacionFailure(VerificacionErrorTipo.desconocido, s);
    }
  }

  /// Traduce una [GatewayException]. Core manda el código de negocio en
  /// `code` (`MANI-VER-*`); si no viene, se decide por el status HTTP.
  static VerificacionFailure mapearGateway(GatewayException e) {
    if (e.isConnectionError) {
      return VerificacionFailure(VerificacionErrorTipo.sinConexion, e.message);
    }
    final codigo = e.cuerpo?['code'];
    if (codigo is String && codigo.startsWith('MANI-VER-')) {
      return mapearMensaje(codigo);
    }
    final tipo = switch (e.statusCode) {
      401 => VerificacionErrorTipo.sinSesion,
      403 => VerificacionErrorTipo.noAutorizado,
      404 => VerificacionErrorTipo.noEncontrado,
      409 => VerificacionErrorTipo.yaResuelta,
      _ => VerificacionErrorTipo.desconocido,
    };
    return VerificacionFailure(tipo, e.message);
  }

  /// Traduce el prefijo `MANI-VER-*` de Core y de las RPC.
  static VerificacionFailure mapearMensaje(String mensaje) {
    const tabla = <String, VerificacionErrorTipo>{
      'MANI-VER-401': VerificacionErrorTipo.sinSesion,
      'MANI-VER-403': VerificacionErrorTipo.noAutorizado,
      'MANI-VER-404': VerificacionErrorTipo.noEncontrado,
      'MANI-VER-409': VerificacionErrorTipo.yaResuelta,
      'MANI-VER-422D': VerificacionErrorTipo.decisionInvalida,
      'MANI-VER-422M': VerificacionErrorTipo.motivoInvalido,
      'MANI-VER-422K': VerificacionErrorTipo.sinDocumentos,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key)) {
        return VerificacionFailure(e.value, mensaje);
      }
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return VerificacionFailure(VerificacionErrorTipo.sinSesion, mensaje);
    }
    return VerificacionFailure(VerificacionErrorTipo.desconocido, mensaje);
  }
}
