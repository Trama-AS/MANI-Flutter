import 'package:equatable/equatable.dart';

/// Motivo de una queja (HU-M12-01 / SCRUM-895). Mismo catálogo que Core.
enum MotivoQueja {
  calidadDelServicio('CALIDAD_DEL_SERVICIO', 'Calidad del servicio'),
  incumplimientoDeHorario(
    'INCUMPLIMIENTO_DE_HORARIO',
    'Incumplimiento de horario',
  ),
  cobroIndebido('COBRO_INDEBIDO', 'Cobro indebido'),
  tratoInadecuado('TRATO_INADECUADO', 'Trato inadecuado'),
  danoALaPropiedad('DANO_A_LA_PROPIEDAD', 'Daño a la propiedad'),
  otro('OTRO', 'Otro');

  const MotivoQueja(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static MotivoQueja? desde(String? valor) {
    for (final m in values) {
      if (m.valor == valor) return m;
    }
    return null;
  }
}

/// Estado de una queja y sus transiciones válidas (HU-M12-02 / SCRUM-896).
/// RESUELTA y RECHAZADA son finales; la regla definitiva la aplica Core.
enum EstadoQueja {
  abierta('ABIERTA', 'Abierta'),
  enRevision('EN_REVISION', 'En revisión'),
  resuelta('RESUELTA', 'Resuelta'),
  rechazada('RECHAZADA', 'Rechazada');

  const EstadoQueja(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  bool get esFinal => this == resuelta || this == rechazada;

  List<EstadoQueja> get siguientes => switch (this) {
    abierta => const [enRevision, resuelta, rechazada],
    enRevision => const [resuelta, rechazada],
    resuelta || rechazada => const [],
  };

  static EstadoQueja desde(String? valor) =>
      values.firstWhere((e) => e.valor == valor, orElse: () => abierta);
}

/// Descripción entre 10 y 1000 caracteres (C2 de SCRUM-895), como en Core.
bool descripcionQuejaValida(String texto) {
  final n = texto.trim().runes.length;
  return n >= 10 && n <= 1000;
}

class TransicionQueja extends Equatable {
  const TransicionQueja({
    required this.estadoNuevo,
    required this.actorRol,
    this.estadoAnterior,
    this.nota,
    this.fecha,
  });

  factory TransicionQueja.fromJson(Map<String, dynamic> json) =>
      TransicionQueja(
        estadoAnterior: json['estadoAnterior'] == null
            ? null
            : EstadoQueja.desde(json['estadoAnterior'] as String),
        estadoNuevo: EstadoQueja.desde(json['estadoNuevo'] as String?),
        actorRol: ((json['actor'] as Map?)?['rol'] as String?) ?? '',
        nota: json['nota'] as String?,
        fecha: DateTime.tryParse('${json['fecha']}'),
      );

  final EstadoQueja? estadoAnterior;
  final EstadoQueja estadoNuevo;
  final String actorRol;
  final String? nota;
  final DateTime? fecha;

  @override
  List<Object?> get props => [
    estadoAnterior,
    estadoNuevo,
    actorRol,
    nota,
    fecha,
  ];
}

class Queja extends Equatable {
  const Queja({
    required this.id,
    required this.solicitudId,
    required this.categoria,
    required this.motivo,
    required this.descripcion,
    required this.estado,
    this.motivoCrudo = '',
    this.respuesta,
    this.clienteEmail,
    this.creadaEn,
    this.historial = const [],
  });

  factory Queja.fromJson(Map<String, dynamic> json) => Queja(
    id: json['id'] as String,
    solicitudId: json['solicitudId'] as String,
    categoria: (json['categoria'] as String?) ?? '',
    motivo: MotivoQueja.desde(json['motivo'] as String?),
    motivoCrudo: (json['motivo'] as String?) ?? '',
    descripcion: (json['descripcion'] as String?) ?? '',
    estado: EstadoQueja.desde(json['estado'] as String?),
    respuesta: json['respuesta'] as String?,
    clienteEmail: (json['cliente'] as Map?)?['email'] as String?,
    creadaEn: DateTime.tryParse('${json['creadaEn']}'),
    historial: [
      for (final h in (json['historial'] as List? ?? const []))
        TransicionQueja.fromJson(Map<String, dynamic>.from(h as Map)),
    ],
  );

  final String id;
  final String solicitudId;
  final String categoria;
  final MotivoQueja? motivo;
  final String motivoCrudo;
  final String descripcion;
  final EstadoQueja estado;
  final String? respuesta;
  final String? clienteEmail;
  final DateTime? creadaEn;
  final List<TransicionQueja> historial;

  String get etiquetaMotivo => motivo?.etiqueta ?? motivoCrudo;

  @override
  List<Object?> get props => [id, estado, respuesta, historial];
}
