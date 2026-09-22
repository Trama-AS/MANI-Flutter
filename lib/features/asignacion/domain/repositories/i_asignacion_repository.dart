import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';

/// Contrato del despacho de solicitudes (RF-14).
///
/// La implementación definitiva llamará a `POST /solicitudes/:id/aceptar`
/// (DD-MANI.md §5.4). Esta interfaz existe para que los casos de prueba y
/// la capa de presentación no cambien cuando se conecte el backend real.
abstract class IAsignacionRepository {
  /// Recupera una solicitud por su ID.
  ///
  /// Lanza [SolicitudNoEncontrada] si no existe en el tenant de la sesión.
  Future<SolicitudEntity> obtener(String solicitudId);

  /// Acepta una solicitud en nombre de un aliado.
  ///
  /// Devuelve la solicitud asignada si este aliado ganó la carrera.
  /// Lanza [SolicitudNoDisponible] si otro aliado la tomó primero y
  /// [SolicitudNoEncontrada] si no existe para el tenant de la sesión.
  /// Es idempotente: si el mismo aliado reintenta tras un éxito previo,
  /// devuelve el mismo resultado en vez de fallar (DD-MANI.md §7.1).
  Future<SolicitudEntity> aceptar(String solicitudId, String aliadoId);
}

/// Equivalente a `409 { "error": "ya_no_disponible" }` (DD-MANI.md §7.1).
class SolicitudNoDisponible implements Exception {
  const SolicitudNoDisponible(this.solicitudId);
  final String solicitudId;

  @override
  String toString() => 'ya_no_disponible: $solicitudId';
}

/// Equivalente a `404 Not Found` (DD-MANI.md §7.1).
class SolicitudNoEncontrada implements Exception {
  const SolicitudNoEncontrada(this.solicitudId);
  final String solicitudId;

  @override
  String toString() => 'no_encontrada: $solicitudId';
}
