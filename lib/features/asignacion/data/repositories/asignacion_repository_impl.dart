import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/repositories/i_asignacion_repository.dart';

/// Implementación en memoria del repositorio de asignación.
///
/// Reproduce el UPDATE condicional atómico del backend (DD-MANI.md §7.1).
/// El `await` de [_latencia] es el punto de entrelazado: dos aceptaciones
/// concurrentes se suspenden ahí y luego compiten por el mismo estado, igual
/// que dos transacciones contra la misma fila de PostgreSQL.
///
/// Debe reemplazarse por una implementación real de Supabase cuando el
/// endpoint `POST /solicitudes/:id/aceptar` esté disponible.
class AsignacionRepositoryImpl implements IAsignacionRepository {
  AsignacionRepositoryImpl({
    Iterable<SolicitudEntity> solicitudes = const [],
    this.latencia = Duration.zero,
  }) {
    for (final s in solicitudes) {
      _solicitudes[s.id] = s;
    }
  }

  final Duration latencia;
  final Map<String, SolicitudEntity> _solicitudes = {};

  @override
  Future<SolicitudEntity> obtener(String solicitudId) async {
    final actual = _solicitudes[solicitudId];
    if (actual == null) throw SolicitudNoEncontrada(solicitudId);
    return actual;
  }

  @override
  Future<SolicitudEntity> aceptar(String solicitudId, String aliadoId) async {
    await Future<void>.delayed(latencia);

    final actual = _solicitudes[solicitudId];
    if (actual == null) throw SolicitudNoEncontrada(solicitudId);

    // Equivale a:
    //   UPDATE solicitud SET aliado_id = ?, estado = 'asignada'
    //   WHERE id = ? AND estado = 'pendiente';
    if (actual.estado == EstadoSolicitud.asignada) {
      if (actual.aliadoId == aliadoId) return actual; // reintento idempotente
      throw SolicitudNoDisponible(solicitudId);
    }

    final asignada = actual.asignadaA(aliadoId);
    _solicitudes[solicitudId] = asignada;
    return asignada;
  }
}
