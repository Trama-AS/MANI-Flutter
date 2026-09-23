import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/logging/structured_logger.dart';

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

  /// Sube las fotos y crea la solicitud. Las rutas dependen de la clave de
  /// idempotencia, así un reintento reemplaza los mismos archivos en vez de
  /// duplicarlos.
  ///
  /// Compensación: si la publicación falla se borran las fotos subidas,
  /// EXCEPTO cuando la RPC ya se envió y el resultado es desconocido (sin
  /// conexión): el servidor pudo haber creado la solicitud, y el reintento
  /// con la misma clave la recupera junto con sus fotos.
  @override
  Future<SolicitudPublicada> publicar(NuevaSolicitud solicitud) async {
    final traceId = StructuredLogger.nuevoTraceId();
    final tenantId = _ds.tenantIdSesion;
    final sw = Stopwatch()..start();
    final subidas = <String>[];
    var rpcEnviada = false;
    try {
      final usuario = _ds.usuarioId;
      if (usuario == null) {
        throw const SolicitudFailure(SolicitudErrorTipo.sinSesion);
      }
      for (var i = 0; i < solicitud.fotos.length; i++) {
        final foto = solicitud.fotos[i];
        final ruta =
            '$usuario/${solicitud.claveIdempotencia}/${i + 1}.${foto.extension}';
        await _guard(
          () => _ds.subirFoto(ruta, foto.bytes, foto.mime),
          alFallar: SolicitudErrorTipo.subidaFotosFallida,
        );
        subidas.add(ruta);
      }

      final ubicacion = solicitud.ubicacion;
      rpcEnviada = true;
      final publicada = await _guard(
        () async => SolicitudPublicadaModel.fromJson(
          await _ds.crear(
            categoriaId: solicitud.categoria.id,
            descripcion: solicitud.descripcion,
            fotos: subidas,
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
          'fotos': subidas.length,
          'sitio_nuevo': ubicacion is NuevaDireccion,
          'duracion_ms': sw.elapsedMilliseconds,
        },
      );
      return publicada;
    } on SolicitudFailure catch (f) {
      final resultadoDesconocido =
          rpcEnviada && f.tipo == SolicitudErrorTipo.sinConexion;
      if (!resultadoDesconocido) {
        await _limpiar(subidas);
      }
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

  /// Compensación: sin solicitud no deben quedar fotos huérfanas.
  Future<void> _limpiar(List<String> rutas) async {
    if (rutas.isEmpty) {
      return;
    }
    try {
      await _ds.eliminarFotos(rutas);
    } catch (_) {
      // Mejor esfuerzo: un fallo aquí no debe ocultar el error original.
    }
  }

  Future<T> _guard<T>(
    Future<T> Function() op, {
    SolicitudErrorTipo alFallar = SolicitudErrorTipo.desconocido,
  }) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw mapearMensaje(e.message);
    } on AuthException catch (e) {
      throw SolicitudFailure(SolicitudErrorTipo.sinSesion, e.message);
    } on StorageException catch (e) {
      throw SolicitudFailure(SolicitudErrorTipo.subidaFotosFallida, e.message);
    } on SolicitudFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw SolicitudFailure(SolicitudErrorTipo.sinConexion, s);
      }
      throw SolicitudFailure(alFallar, s);
    }
  }

  /// Traduce el prefijo `MANI-SOL-*` de las RPC de la migración 006.
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
