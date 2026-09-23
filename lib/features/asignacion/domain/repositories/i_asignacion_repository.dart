import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';

/// Contrato del despacho de solicitudes (RF-14, US-04.1.4).
///
/// Ningún método recibe `aliadoId` ni `tenantId`: el servidor los deriva de la
/// sesión, así un aliado no puede aceptar en nombre de otro.
/// Todas las operaciones lanzan `AsignacionFailure` ante errores.
abstract class IAsignacionRepository {
  /// Solicitudes disponibles para el aliado autenticado (de sus categorías y
  /// zonas, sin las que rechazó) más las que ya tiene asignadas.
  Future<List<SolicitudEntity>> listar();

  /// Acepta la solicitud para el aliado autenticado.
  ///
  /// Devuelve la solicitud asignada si este aliado ganó la carrera. Si otro la
  /// tomó primero lanza `yaNoDisponible` (409, DD-MANI §7.1). Es idempotente:
  /// si el mismo aliado reintenta tras un éxito, devuelve el mismo resultado.
  Future<SolicitudEntity> aceptar(String solicitudId);

  /// Oculta la solicitud para el aliado autenticado. No la quita a los demás.
  Future<void> rechazar(String solicitudId, {MotivoRechazo? motivo});
}
