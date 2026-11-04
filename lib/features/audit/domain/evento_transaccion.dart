import 'package:equatable/equatable.dart';

double _numero(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

/// Evento inmutable de una transacción (SCRUM-889, HU-M11-03): quién la hizo,
/// cuándo y con qué desenlace. Core lo escribe en la misma transacción del pago y
/// nadie lo modifica ni lo borra.
class EventoTransaccion extends Equatable {
  const EventoTransaccion({
    required this.id,
    required this.pagoId,
    required this.tipo,
    required this.estado,
    required this.monto,
    required this.moneda,
    required this.actorRol,
    required this.actorId,
    this.correlationId,
    this.creadoEn,
  });

  factory EventoTransaccion.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] is Map
        ? Map<String, dynamic>.from(json['actor'] as Map)
        : const <String, dynamic>{};
    return EventoTransaccion(
      id: json['id'] as String,
      pagoId: (json['pagoId'] as String?) ?? '',
      tipo: (json['tipo'] as String?) ?? '',
      estado: (json['estado'] as String?) ?? '',
      monto: _numero(json['monto']),
      moneda: (json['moneda'] as String?) ?? 'COP',
      actorRol: (actor['rol'] as String?) ?? '',
      actorId: (actor['id'] as String?) ?? '',
      correlationId: json['correlationId'] as String?,
      creadoEn: DateTime.tryParse(
        (json['creadoEn'] as String?) ?? '',
      )?.toLocal(),
    );
  }

  final String id;
  final String pagoId;
  final String tipo;
  final String estado;
  final double monto;
  final String moneda;
  final String actorRol;
  final String actorId;
  final String? correlationId;
  final DateTime? creadoEn;

  String get etiquetaActor => switch (actorRol) {
    'CLIENT' => 'Cliente',
    'ALLY' => 'Aliado',
    'ADMIN' => 'Administrador',
    _ => actorRol,
  };

  String get etiquetaTipo => switch (tipo) {
    'PAGO_REGISTRADO' => 'Pago registrado',
    _ => tipo,
  };

  @override
  List<Object?> get props => [
    id,
    pagoId,
    tipo,
    estado,
    monto,
    moneda,
    actorRol,
    actorId,
    correlationId,
    creadoEn,
  ];
}
