import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/catalogo_solicitud.dart';
import '../../domain/entities/nueva_solicitud.dart';
import '../../domain/entities/solicitud_publicada.dart';
import '../../domain/failures/solicitud_failure.dart';
import '../../domain/repositories/solicitudes_cliente_repository.dart';
import '../datasources/solicitudes_cliente_remote_datasource.dart';
import '../models/solicitud_models.dart';

class SolicitudesClienteRepositoryImpl implements SolicitudesClienteRepository {
  SolicitudesClienteRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.solicitudes');

  final SolicitudesClienteRemoteDataSource _ds;
  final StructuredLogger _log;

  static const _evento = 'US-04.1.1.crear_solicitud';

  @override
  Future<List<CategoriaDisponible>> categoriasDisponibles() => _guard(
    () async => (await _ds.listarCategorias())
        .map<CategoriaDisponible>(CategoriaDisponibleModel.fromJson)
        .toList(),
  );

  @override
  Future<List<SitioCliente>> misSitios() => _guard(
    () async => (await _ds.listarSitios())
        .map<SitioCliente>(SitioClienteModel.fromJson)
        .toList(),
  );

  @override
  Future<List<ZonaOpcion>> buscarZonas(String texto) => _guard(
    () async => (await _ds.buscarZonas(
      texto,
    )).map<ZonaOpcion>(ZonaOpcionModel.fromJson).toList(),
  );

  /// Envía la solicitud con sus fotos a Core por el Gateway en una sola
  /// petición. Core sube las fotos, crea la solicitud y, si falla o es un
  /// reintento, borra lo que subió: la app ya no compensa en Storage.
  ///
  /// Si la respuesta se pierde (sin conexión), el reintento con la misma
  /// clave de idempotencia devuelve la solicitud que Core ya creó.
  @override
  Future<SolicitudPublicada> publicar(NuevaSolicitud solicitud) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    try {
      if (_ds.usuarioId == null) {
        throw const SolicitudFailure(SolicitudErrorTipo.sinSesion);
      }
      final ubicacion = solicitud.ubicacion;
      final publicada = await _guard(
        () async => SolicitudPublicadaModel.fromJson(
          await _ds.crear(
            categoriaId: solicitud.categoria.id,
            descripcion: solicitud.descripcion,
            fotos: solicitud.fotos,
            claveIdempotencia: solicitud.claveIdempotencia,
            sitioId: switch (ubicacion) {
              SitioExistente(:final sitio) => sitio.id,
              NuevaDireccion() => null,
            },
            direccion: switch (ubicacion) {
              NuevaDireccion(:final direccion) => direccion,
              SitioExistente() => null,
            },
            zonaId: switch (ubicacion) {
              NuevaDireccion(:final zona) => zona.id,
              SitioExistente() => null,
            },
          ),
        ),
      );
      _log.info(
        'solicitud_creada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'solicitud_id': publicada.id,
          'categoria_id': solicitud.categoria.id,
          'fotos': solicitud.fotos.length,
          'sitio_nuevo': ubicacion is NuevaDireccion,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return publicada;
    } on SolicitudFailure catch (f) {
      _log.error(
        'solicitud_no_creada',
        traceId: traceId,
        tenantId: tenantId,
        extra: {
          'event': _evento,
          'error': f.tipo.name,
          'fotos': solicitud.fotos.length,
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
      throw SolicitudFailure(SolicitudErrorTipo.sinSesion, e.message);
    } on SolicitudFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw SolicitudFailure(SolicitudErrorTipo.sinConexion, s);
      }
      throw SolicitudFailure(SolicitudErrorTipo.desconocido, s);
    }
  }

  /// Traduce la respuesta de Core: los 400/422 traen el código `MANI-SOL-*`
  /// al inicio del mensaje; el resto se decide por el status.
  static SolicitudFailure mapearGateway(GatewayException e) {
    final detalle = '${e.statusCode ?? 'sin respuesta'}: ${e.message}';
    return switch (e.statusCode) {
      null => SolicitudFailure(SolicitudErrorTipo.sinConexion, detalle),
      401 => SolicitudFailure(SolicitudErrorTipo.sinSesion, detalle),
      403 => SolicitudFailure(SolicitudErrorTipo.noEsCliente, detalle),
      413 => SolicitudFailure(SolicitudErrorTipo.fotoMuyPesada, detalle),
      400 || 422 => mapearMensaje(e.message),
      _ => SolicitudFailure(SolicitudErrorTipo.desconocido, detalle),
    };
  }

  /// Traduce el prefijo `MANI-SOL-*` (Core y RPC de la migración 006).
  static SolicitudFailure mapearMensaje(String mensaje) {
    const tabla = <String, SolicitudErrorTipo>{
      'MANI-SOL-401': SolicitudErrorTipo.sinSesion,
      'MANI-SOL-403C': SolicitudErrorTipo.noEsCliente,
      'MANI-SOL-422C': SolicitudErrorTipo.categoriaInvalida,
      'MANI-SOL-422D': SolicitudErrorTipo.descripcionInvalida,
      'MANI-SOL-422F': SolicitudErrorTipo.fotosInvalidas,
      'MANI-SOL-422S': SolicitudErrorTipo.ubicacionInvalida,
      'MANI-SOL-422Z': SolicitudErrorTipo.zonaInvalida,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key)) {
        return SolicitudFailure(e.value, mensaje);
      }
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return SolicitudFailure(SolicitudErrorTipo.sinSesion, mensaje);
    }
    return SolicitudFailure(SolicitudErrorTipo.desconocido, mensaje);
  }
}
