import 'package:equatable/equatable.dart';

/// Estados posibles de una solicitud de servicio (RF-14).
///
/// Equivalente al campo `estado` de la tabla `solicitud` en el backend
/// (DD-MANI.md §7.1).
enum EstadoSolicitud { pendiente, asignada }

/// Entidad de dominio que representa una solicitud de servicio técnico.
///
/// Inmutable y libre de dependencias de infraestructura.
/// Referencias: SRS_MANI.md RF-14, DD-MANI.md §7.1, ADR-0016.
class SolicitudEntity extends Equatable {
  const SolicitudEntity({
    required this.id,
    required this.estado,
    this.aliadoId,
  });

  const SolicitudEntity.pendiente(this.id)
    : estado = EstadoSolicitud.pendiente,
      aliadoId = null;

  final String id;
  final EstadoSolicitud estado;
  final String? aliadoId;

  /// Devuelve una copia de la solicitud asignada al [aliadoId] dado.
  SolicitudEntity asignadaA(String aliadoId) => SolicitudEntity(
    id: id,
    estado: EstadoSolicitud.asignada,
    aliadoId: aliadoId,
  );

  @override
  List<Object?> get props => [id, estado, aliadoId];
}
