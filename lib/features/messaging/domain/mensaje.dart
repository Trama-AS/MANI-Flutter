import 'package:equatable/equatable.dart';

/// Máximo de caracteres de un mensaje; Core rechaza más (MANI-MSG-400).
const maxCaracteresMensaje = 1000;

/// Mensaje del hilo de un servicio entre el cliente y el aliado (SCRUM-881).
/// [esMio] y [rolRemitente] los decide Core con la sesión: la app no sabe quién
/// es el otro participante más que por su rol.
class Mensaje extends Equatable {
  const Mensaje({
    required this.id,
    required this.contenido,
    required this.esMio,
    required this.rolRemitente,
    this.creadoEn,
  });

  factory Mensaje.fromJson(Map<String, dynamic> json) {
    final remitente = json['remitente'];
    return Mensaje(
      id: json['id'] as String,
      contenido: (json['contenido'] as String?) ?? '',
      esMio: (json['mio'] as bool?) ?? false,
      rolRemitente: remitente is Map ? (remitente['rol'] as String?) ?? '' : '',
      creadoEn: DateTime.tryParse(
        (json['creadoEn'] as String?) ?? '',
      )?.toLocal(),
    );
  }

  final String id;
  final String contenido;
  final bool esMio;

  /// `CLIENT` o `ALLY`, tal como lo manda Core.
  final String rolRemitente;
  final DateTime? creadoEn;

  String get etiquetaRemitente => switch (rolRemitente) {
    'CLIENT' => 'Cliente',
    'ALLY' => 'Aliado',
    _ => '',
  };

  @override
  List<Object?> get props => [id, contenido, esMio, rolRemitente, creadoEn];
}

enum MensajeErrorTipo {
  sinConexion,
  sinSesion,
  sinPermiso,
  noEncontrado,
  datosInvalidos,
  servicioCerrado,
  servicioNoDisponible,
  desconocido,
}

/// Fallo de una operación de mensajería con el mensaje para el usuario.
class MensajeFailure extends Equatable implements Exception {
  const MensajeFailure(this.tipo, {this.detalle, this.correlationId});

  final MensajeErrorTipo tipo;
  final String? detalle;
  final String? correlationId;

  /// El hilo ya no se puede usar: reintentar no lo arregla.
  bool get definitivo => switch (tipo) {
    MensajeErrorTipo.sinSesion ||
    MensajeErrorTipo.sinPermiso ||
    MensajeErrorTipo.noEncontrado => true,
    _ => false,
  };

  String get mensajeUsuario => switch (tipo) {
    MensajeErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu red; tus mensajes no se pierden.',
    MensajeErrorTipo.sinSesion => 'Tu sesión expiró. Inicia sesión de nuevo.',
    MensajeErrorTipo.sinPermiso =>
      'Tu cuenta no puede usar la mensajería de este servicio.',
    MensajeErrorTipo.noEncontrado => 'No encontramos este servicio.',
    MensajeErrorTipo.datosInvalidos =>
      detalle ?? 'Revisa el mensaje e inténtalo de nuevo.',
    MensajeErrorTipo.servicioCerrado =>
      'Este servicio ya no admite mensajes nuevos. Puedes leer la '
          'conversación.',
    MensajeErrorTipo.servicioNoDisponible =>
      'El servicio no está disponible. Inténtalo en unos minutos.',
    MensajeErrorTipo.desconocido =>
      'No se pudo completar la operación. Inténtalo de nuevo.',
  };

  @override
  List<Object?> get props => [tipo, detalle, correlationId];
}
