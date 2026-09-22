import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';

import '../../domain/entities/zona.dart';
import '../../domain/failures/cobertura_failure.dart';
import '../../domain/repositories/cobertura_repository.dart';
import '../datasources/cobertura_remote_datasource.dart';
import '../models/zona_model.dart';

class CoberturaRepositoryImpl implements CoberturaRepository {
  CoberturaRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.cobertura');

  final CoberturaRemoteDataSource _ds;
  final StructuredLogger _log;

  @override
  Future<List<Zona>> listarZonas({String? padreId}) => _guard(
    () async =>
        (await _ds.listarZonas(padreId)).map<Zona>(ZonaModel.fromJson).toList(),
  );

  @override
  Future<List<Zona>> buscarZonas({
    required String ciudadId,
    required String texto,
  }) => _guard(
    () async => (await _ds.buscarZonas(
      ciudadId,
      texto,
    )).map<Zona>(ZonaModel.fromJson).toList(),
  );

  @override
  Future<List<Zona>> obtenerMiCobertura() => _guard(
    () async =>
        (await _ds.obtenerMiCobertura()).map<Zona>(ZonaModel.fromJson).toList(),
  );

  @override
  Future<Set<String>> declararCobertura(Set<String> zonaIds) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    try {
      final filas = await _guard(() => _ds.declararCobertura(zonaIds.toList()));
      final guardadas = filas.map((f) => f['zona_id'] as String).toSet();
      _log.info(
        'cobertura_declarada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': 'US-02.1.4.declarar_cobertura',
          'zonas_enviadas': zonaIds.length,
          'zonas_guardadas': guardadas.length,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return guardadas;
    } on CoberturaFailure catch (f) {
      _log.error(
        'cobertura_no_declarada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': 'US-02.1.4.declarar_cobertura',
          'error': f.tipo.name,
          'zonas_enviadas': zonaIds.length,
          'duracion_ms': sw.elapsedMilliseconds,
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
      throw CoberturaFailure(CoberturaErrorTipo.sinSesion, e.message);
    } on CoberturaFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw CoberturaFailure(CoberturaErrorTipo.sinConexion, s);
      }
      throw CoberturaFailure(CoberturaErrorTipo.desconocido, s);
    }
  }

  /// Traduce el prefijo `MANI-COB-*` de la RPC. El orden importa: 403R antes que 403.
  static CoberturaFailure mapearMensaje(String mensaje) {
    const tabla = <String, CoberturaErrorTipo>{
      'MANI-COB-401': CoberturaErrorTipo.sinSesion,
      'MANI-COB-403R': CoberturaErrorTipo.aliadoRechazado,
      'MANI-COB-403': CoberturaErrorTipo.noEsAliado,
      'MANI-COB-422V': CoberturaErrorTipo.seleccionVacia,
      'MANI-COB-422L': CoberturaErrorTipo.limiteExcedido,
      'MANI-COB-422Z': CoberturaErrorTipo.zonaInvalida,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key)) return CoberturaFailure(e.value, mensaje);
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return CoberturaFailure(CoberturaErrorTipo.sinSesion, mensaje);
    }
    return CoberturaFailure(CoberturaErrorTipo.desconocido, mensaje);
  }
}
