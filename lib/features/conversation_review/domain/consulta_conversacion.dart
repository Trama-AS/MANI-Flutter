import 'package:equatable/equatable.dart';
import 'package:mani/features/messaging/domain/mensaje.dart';

/// Registro de una consulta de conversación (SCRUM-883): Core guarda quién la
/// abrió, por qué y cuántos mensajes vio, en la misma transacción de la lectura.
class ConsultaConversacion extends Equatable {
  const ConsultaConversacion({
    required this.id,
    required this.solicitudId,
    required this.motivo,
    required this.mensajesVistos,
    this.quejaRef,
    this.creadoEn,
  });

  factory ConsultaConversacion.fromJson(Map<String, dynamic> json) =>
      ConsultaConversacion(
        id: json['id'] as String,
        solicitudId: (json['solicitudId'] as String?) ?? '',
        motivo: (json['motivo'] as String?) ?? '',
        quejaRef: json['quejaRef'] as String?,
        mensajesVistos: (json['mensajesVistos'] as num?)?.toInt() ?? 0,
        creadoEn: DateTime.tryParse(
          (json['creadoEn'] as String?) ?? '',
        )?.toLocal(),
      );

  final String id;
  final String solicitudId;
  final String motivo;
  final String? quejaRef;
  final int mensajesVistos;
  final DateTime? creadoEn;

  @override
  List<Object?> get props => [
    id,
    solicitudId,
    motivo,
    quejaRef,
    mensajesVistos,
    creadoEn,
  ];
}

/// Resultado de abrir la conversación: el registro de la consulta y los mensajes.
class ConversacionConsultada extends Equatable {
  const ConversacionConsultada({
    required this.consulta,
    required this.mensajes,
  });

  factory ConversacionConsultada.fromJson(Map<String, dynamic> json) {
    final c = json['consulta'];
    final m = json['mensajes'];
    if (c is! Map || m is! List) {
      throw const FormatException(
        'Respuesta de Core sin "consulta" o "mensajes"',
      );
    }
    return ConversacionConsultada(
      consulta: ConsultaConversacion.fromJson(Map<String, dynamic>.from(c)),
      mensajes: [
        for (final e in m)
          Mensaje.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  final ConsultaConversacion consulta;
  final List<Mensaje> mensajes;

  @override
  List<Object?> get props => [consulta, mensajes];
}
