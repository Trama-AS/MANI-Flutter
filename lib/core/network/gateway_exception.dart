/// Error de una petición al API Gateway, ya traducido a un mensaje que se
/// puede mostrar al usuario.
///
/// [statusCode] es `null` cuando la petición no llegó a tener respuesta
/// (sin red, timeout, DNS).
class GatewayException implements Exception {
  const GatewayException({
    required this.message,
    this.statusCode,
    this.correlationId,
  });

  /// Construye el error a partir del status HTTP. [detalle] es el mensaje que
  /// devuelve el servicio (campo `message` o `error` del cuerpo); solo se usa
  /// en los 400 y 409, donde explica qué campo o dato hay que corregir.
  factory GatewayException.fromStatus(
    int statusCode, {
    String? detalle,
    String? correlationId,
  }) {
    final String message;
    if (statusCode == 400 || statusCode == 422) {
      message =
          detalle ?? 'Revisa los datos del formulario e inténtalo de nuevo.';
    } else if (statusCode == 401) {
      message = 'Tu sesión no es válida o expiró. Inicia sesión de nuevo.';
    } else if (statusCode == 403) {
      message = 'No tienes permiso para realizar esta acción.';
    } else if (statusCode == 404) {
      message = 'El servicio solicitado no está disponible.';
    } else if (statusCode == 409) {
      message = detalle ?? 'Ya existe un registro con estos datos.';
    } else if (statusCode == 413) {
      message = 'Los archivos adjuntos superan el tamaño permitido.';
    } else if (statusCode >= 500) {
      message =
          'El servicio no está disponible en este momento. Inténtalo más tarde.';
    } else {
      message = detalle ?? 'No se pudo completar la solicitud ($statusCode).';
    }
    return GatewayException(
      message: message,
      statusCode: statusCode,
      correlationId: correlationId,
    );
  }

  final String message;
  final int? statusCode;

  /// `X-Correlation-ID` de la petición, para rastrearla en los logs del
  /// Gateway y de los servicios.
  final String? correlationId;

  /// Indica si el error se debe a un conflicto de concurrencia o duplicado (HTTP 409).
  bool get isConflict => statusCode == 409;

  /// Indica si el error se debe a falta de autenticación o expiración de token (HTTP 401).
  bool get isUnauthorized => statusCode == 401;

  /// Indica si el error se debe a permisos insuficientes (HTTP 403).
  bool get isForbidden => statusCode == 403;

  /// Indica si ocurrió un fallo de red o timeout sin respuesta del servidor.
  bool get isConnectionError => statusCode == null;

  @override
  String toString() =>
      'GatewayException($statusCode, $message, correlation: $correlationId)';
}
