import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/motivo_rechazo.dart';
import '../../domain/entities/solicitud_entity.dart';
import '../../domain/failures/asignacion_failure.dart';
import '../../domain/repositories/i_asignacion_repository.dart';
import '../datasources/asignacion_remote_datasource.dart';
import '../models/solicitud_model.dart';

/// Despacho de solicitudes por el Gateway (decisión 6A).
///
/// Dispatch decide quién acepta y Core registra la asignación con un UPDATE
/// condicional bajo bloqueo de fila (DD-MANI §7.1); aquí solo se traducen sus
/// códigos y se registra cada intento con su duración (QS-09 exige respuesta
/// < 500 ms).
class AsignacionRepositoryImpl implements IAsignacionRepository {
  AsignacionRepositoryImpl(this._ds, {StructuredLogger? logger})
    : _log = logger ?? StructuredLogger(canal: 'mani.asignacion');

  final AsignacionRemoteDataSource _ds;
  final StructuredLogger _log;

  static const _eventoAceptar = 'US-04.1.4.aceptar_solicitud';
  static const _eventoRechazar = 'US-04.1.4.rechazar_solicitud';

  @override
  Future<List<SolicitudEntity>> listar() => _guard(_listar);

  Future<List<SolicitudEntity>> _listar() async => (await _ds.listar())
      .map<SolicitudEntity>(SolicitudModel.fromGateway)
      .toList();

  @override
  Future<SolicitudEntity> aceptar(String solicitudId) => _registrar(
    evento: _eventoAceptar,
    solicitudId: solicitudId,
    exito: 'solicitud_asignada',
    fallo: 'solicitud_no_asignada',
    op: () async {
      await _ds.aceptar(solicitudId);
      return _asignadaDesdeBandeja(solicitudId);
    },
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

  /// La aceptación no devuelve la solicitud, así que se lee de la bandeja, que
  /// ya trae la dirección. La asignación ya quedó en Core: si la bandeja no
  /// responde o aún no la muestra, no se informa un error, se devuelve lo
  /// mínimo y el siguiente refresco completa los datos.
  Future<SolicitudEntity> _asignadaDesdeBandeja(String solicitudId) async {
    try {
      for (final s in await _listar()) {
        if (s.id == solicitudId && s.esMia) {
          return s;
        }
      }
    } on Object {
      // Se cae al mínimo de abajo.
    }
    return SolicitudEntity(
      id: solicitudId,
      estado: EstadoSolicitud.asignada,
      esMia: true,
      categoria: 'Servicio',
      zona: '',
      fechaCreacion: DateTime.now(),
      fechaAsignacion: DateTime.now(),
    );
  }

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
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    } on AsignacionFailure {
      rethrow;
    } catch (e) {
      throw AsignacionFailure(AsignacionErrorTipo.desconocido, e.toString());
    }
  }

  /// Traduce el `code` que devuelven Dispatch y Core (`dispatch.yaml`). Si no
  /// hay código, decide el status HTTP. Un 5xx no se disfraza de otra cosa:
  /// el aliado ve que el servicio no responde y puede reintentar.
  static AsignacionFailure mapearGateway(GatewayException e) {
    final status = e.statusCode;
    if (status == null) {
      return AsignacionFailure(AsignacionErrorTipo.sinConexion, e.message);
    }
    final codigo = e.cuerpo?['code'];
    const porCodigo = <String, AsignacionErrorTipo>{
      'MANI-SOL-401': AsignacionErrorTipo.sinSesion,
      'MANI-DSP-401': AsignacionErrorTipo.sinSesion,
      'MANI-SOL-403V': AsignacionErrorTipo.aliadoNoVerificado,
      'MANI-SOL-403E': AsignacionErrorTipo.noElegible,
      'MANI-SOL-403O': AsignacionErrorTipo.noElegible,
      'MANI-SOL-403': AsignacionErrorTipo.noEsAliado,
      'MANI-DSP-403': AsignacionErrorTipo.noEsAliado,
      'MANI-SOL-404': AsignacionErrorTipo.noEncontrada,
      'MANI-DSP-404': AsignacionErrorTipo.noEncontrada,
      'MANI-SOL-409': AsignacionErrorTipo.yaNoDisponible,
      'MANI-SOL-409E': AsignacionErrorTipo.yaNoDisponible,
      'MANI-DSP-409E': AsignacionErrorTipo.yaNoDisponible,
      'MANI-DSP-409A': AsignacionErrorTipo.yaEsTuya,
      'MANI-DSP-409R': AsignacionErrorTipo.yaRechazada,
      'MANI-SOL-422M': AsignacionErrorTipo.motivoInvalido,
    };
    final tipo =
        porCodigo[codigo] ??
        switch (status) {
          401 => AsignacionErrorTipo.sinSesion,
          403 => AsignacionErrorTipo.noEsAliado,
          404 => AsignacionErrorTipo.noEncontrada,
          409 => AsignacionErrorTipo.yaNoDisponible,
          422 => AsignacionErrorTipo.motivoInvalido,
          >= 500 => AsignacionErrorTipo.servicioNoDisponible,
          _ => AsignacionErrorTipo.desconocido,
        };
    return AsignacionFailure(tipo, codigo is String ? codigo : e.message);
  }
}
