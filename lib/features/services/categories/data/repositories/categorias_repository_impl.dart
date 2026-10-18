import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/categoria_servicio.dart';
import '../../domain/entities/nueva_categoria.dart';
import '../../domain/failures/categoria_failure.dart';
import '../../domain/repositories/categorias_repository.dart';
import '../datasources/categorias_remote_datasource.dart';
import '../models/categoria_servicio_model.dart';

class CategoriasRepositoryImpl implements CategoriasRepository {
  CategoriasRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.categorias');

  final CategoriasRemoteDataSource _ds;
  final StructuredLogger _log;

  static const _evento = 'US-03.1.1.crear_categoria';
  static const _eventoEstado = 'US-03.1.2.cambiar_estado_categoria';

  @override
  Future<List<CategoriaServicio>> listar() => _guard(
    () async => (await _ds.listar())
        .map<CategoriaServicio>(CategoriaServicioModel.fromJson)
        .toList(),
  );

  @override
  Future<CategoriaServicio> crear(NuevaCategoria categoria) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    try {
      final creada = await _guard(
        () async => CategoriaServicioModel.fromJson(
          await _ds.crear(
            nombre: categoria.nombre,
            flujoOperativo: categoria.flujo.codigo,
            activa: categoria.activa,
          ),
        ),
      );
      _log.info(
        'categoria_creada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'categoria_id': creada.id,
          'flujo_operativo': categoria.flujo.codigo,
          'activa': categoria.activa,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return creada;
    } on CategoriaFailure catch (f) {
      _log.error(
        'categoria_no_creada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'flujo_operativo': categoria.flujo.codigo,
          'error': f.tipo.name,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      rethrow;
    }
  }

  @override
  Future<CategoriaServicio> cambiarEstado({
    required String categoriaId,
    required bool activa,
  }) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    try {
      final actualizada = await _guard(
        () async => CategoriaServicioModel.fromJson(
          await _ds.cambiarEstado(categoriaId: categoriaId, activa: activa),
        ),
      );
      _log.info(
        activa ? 'categoria_activada' : 'categoria_desactivada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _eventoEstado,
          'categoria_id': actualizada.id,
          'activa': actualizada.activa,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return actualizada;
    } on CategoriaFailure catch (f) {
      _log.error(
        'categoria_estado_no_actualizado',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _eventoEstado,
          'categoria_id': categoriaId,
          'activa': activa,
          'error': f.tipo.name,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      rethrow;
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
      throw CategoriaFailure(CategoriaErrorTipo.sinSesion, e.message);
    } on CategoriaFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw CategoriaFailure(CategoriaErrorTipo.sinConexion, s);
      }
      throw CategoriaFailure(CategoriaErrorTipo.desconocido, s);
    }
  }

  /// Traduce una [GatewayException] (HTTP status + mensaje de Core Node).
  static CategoriaFailure mapearGateway(GatewayException e) {
    if (e.isConnectionError) {
      return CategoriaFailure(CategoriaErrorTipo.sinConexion, e.message);
    }
    return switch (e.statusCode) {
      401 => CategoriaFailure(CategoriaErrorTipo.sinSesion, e.message),
      403 => CategoriaFailure(CategoriaErrorTipo.noAutorizado, e.message),
      404 => CategoriaFailure(CategoriaErrorTipo.noEncontrada, e.message),
      409 => CategoriaFailure(CategoriaErrorTipo.nombreDuplicado, e.message),
      _ => mapearMensaje(e.message),
    };
  }

  /// Traduce el prefijo `MANI-CAT-*` de las RPC y códigos de Core Node.
  static CategoriaFailure mapearMensaje(String mensaje) {
    const tabla = <String, CategoriaErrorTipo>{
      'MANI-CAT-401': CategoriaErrorTipo.sinSesion,
      'MANI-CAT-403': CategoriaErrorTipo.noAutorizado,
      'MANI-CAT-404': CategoriaErrorTipo.noEncontrada,
      'MANI-CAT-409': CategoriaErrorTipo.nombreDuplicado,
      'MANI-CAT-422N': CategoriaErrorTipo.nombreInvalido,
      'MANI-CAT-422F': CategoriaErrorTipo.flujoInvalido,
      'CATEGORY_NOT_FOUND': CategoriaErrorTipo.noEncontrada,
      'CATEGORY_NAME_ALREADY_EXISTS': CategoriaErrorTipo.nombreDuplicado,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key) || mensaje.contains(e.key)) {
        return CategoriaFailure(e.value, mensaje);
      }
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return CategoriaFailure(CategoriaErrorTipo.sinSesion, mensaje);
    }
    return CategoriaFailure(CategoriaErrorTipo.desconocido, mensaje);
  }
}
