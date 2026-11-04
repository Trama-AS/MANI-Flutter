import 'package:equatable/equatable.dart';

/// Aviso de la bandeja del usuario (SCRUM-882 y 884): un mensaje nuevo del
/// servicio o un cambio de estado. Core decide a quién llega cada aviso; la app
/// solo muestra los de la sesión.
class Aviso extends Equatable {
  const Aviso({
    required this.id,
    required this.tipo,
    required this.canal,
    required this.payload,
    this.enviadoEn,
    this.leidoEn,
  });

  factory Aviso.fromJson(Map<String, dynamic> json) => Aviso(
    id: json['id'] as String,
    tipo: (json['tipo'] as String?) ?? '',
    canal: (json['canal'] as String?) ?? '',
    payload: json['payload'] is Map
        ? Map<String, dynamic>.from(json['payload'] as Map)
        : const {},
    enviadoEn: DateTime.tryParse(
      (json['enviadoAt'] as String?) ?? '',
    )?.toLocal(),
    leidoEn: DateTime.tryParse((json['leidoAt'] as String?) ?? '')?.toLocal(),
  );

  final String id;
  final String tipo;
  final String canal;
  final Map<String, dynamic> payload;
  final DateTime? enviadoEn;
  final DateTime? leidoEn;

  /// Solicitud a la que se refiere el aviso, si la trae.
  String? get solicitudId {
    final v = payload['requestId'] ?? payload['solicitudId'];
    return v is String && v.isNotEmpty ? v : null;
  }

  bool get esMensaje => tipo == 'MENSAJE_NUEVO';

  bool get leido => leidoEn != null;

  String get titulo => switch (tipo) {
    'MENSAJE_NUEVO' => 'Nuevo mensaje',
    'SOLICITUD_ASIGNADA' => 'Un aliado aceptó tu solicitud',
    'SOLICITUD_CANCELADA' => 'La solicitud fue cancelada',
    'EJECUCION_INICIADA' => 'El servicio comenzó',
    'EJECUCION_FINALIZADA' => 'El servicio finalizó',
    'COTIZACION_RECIBIDA' => 'Recibiste una cotización',
    'RESPUESTA_COTIZACION' => 'El cliente respondió tu cotización',
    'ADICION_SOLICITADA' => 'El aliado pidió una adición',
    'ADICION_ACEPTADA' => 'Adición aceptada',
    'ADICION_RECHAZADA' => 'Adición rechazada',
    'OFERTA_DESPACHO' => 'Nueva oferta de servicio',
    _ => 'Aviso',
  };

  String get detalle => switch (tipo) {
    'MENSAJE_NUEVO' => switch (payload['remitenteRol']) {
      'CLIENT' => 'Te escribió el cliente.',
      'ALLY' => 'Te escribió el aliado.',
      _ => 'Tienes un mensaje nuevo en el chat del servicio.',
    },
    'SOLICITUD_ASIGNADA' => 'Ya puedes seguir el servicio.',
    'EJECUCION_INICIADA' => 'El aliado marcó el inicio del trabajo.',
    'EJECUCION_FINALIZADA' => 'El aliado marcó el fin del trabajo.',
    _ => '',
  };

  @override
  List<Object?> get props => [id, tipo, canal, payload, enviadoEn, leidoEn];
}

/// Bandeja completa: [simulada] viene de Core e indica que el proveedor de
/// notificaciones es el simulador (no se envía un push real).
class BandejaAvisos extends Equatable {
  const BandejaAvisos({
    required this.items,
    required this.simulada,
    required this.proveedor,
  });

  factory BandejaAvisos.fromJson(Map<String, dynamic> json) {
    final lista = json['items'];
    if (lista is! List) {
      throw const FormatException('Respuesta de Core sin "items"');
    }
    return BandejaAvisos(
      items: [
        for (final e in lista)
          Aviso.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      simulada: (json['simulada'] as bool?) ?? false,
      proveedor: (json['proveedor'] as String?) ?? '',
    );
  }

  final List<Aviso> items;
  final bool simulada;
  final String proveedor;

  @override
  List<Object?> get props => [items, simulada, proveedor];
}
