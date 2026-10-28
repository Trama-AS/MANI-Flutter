import '../entities/bandeja_solicitudes.dart';
import '../entities/motivo_rechazo.dart';
import '../entities/solicitud_entity.dart';
import '../failures/asignacion_failure.dart';
import '../repositories/i_asignacion_repository.dart';

/// Carga la bandeja del aliado ya repartida en disponibles y mis trabajos.
class ListarSolicitudesAliado {
  const ListarSolicitudesAliado(this._repo);
  final IAsignacionRepository _repo;

  Future<BandejaSolicitudes> call() async =>
      BandejaSolicitudes.desde(await _repo.listar());
}

/// Acepta una solicitud. Falla sin red si ya se sabe que no está disponible;
/// la decisión final (quién gana la carrera) la toma siempre el servidor.
class AceptarSolicitud {
  const AceptarSolicitud(this._repo);
  final IAsignacionRepository _repo;

  Future<SolicitudEntity> call(SolicitudEntity solicitud) {
    if (solicitud.esMia) {
      throw const AsignacionFailure(AsignacionErrorTipo.yaEsTuya);
    }
    if (solicitud.estado != EstadoSolicitud.pendiente) {
      throw const AsignacionFailure(AsignacionErrorTipo.yaNoDisponible);
    }
    return _repo.aceptar(solicitud.id);
  }
}

/// Rechaza una solicitud solo para este aliado; sigue disponible para otros.
class RechazarSolicitud {
  const RechazarSolicitud(this._repo);
  final IAsignacionRepository _repo;

  Future<void> call(
    SolicitudEntity solicitud, {
    required MotivoRechazo motivo,
    String? detalle,
  }) {
    if (solicitud.esMia) {
      throw const AsignacionFailure(AsignacionErrorTipo.yaEsTuya);
    }
    // Las mismas reglas que Dispatch (SCRUM-1617): se cortan aquí para no
    // hacer una petición que el servidor rechazaría con 422.
    final texto = detalle?.trim();
    if (motivo.requiereDetalle) {
      if (texto == null || !MotivoRechazo.detalleValido(texto)) {
        throw const AsignacionFailure(AsignacionErrorTipo.detalleInvalido);
      }
      return _repo.rechazar(solicitud.id, motivo: motivo, detalle: texto);
    }
    return _repo.rechazar(solicitud.id, motivo: motivo);
  }
}
