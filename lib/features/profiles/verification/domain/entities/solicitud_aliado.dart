import 'package:equatable/equatable.dart';

import 'documento_kyc.dart';

enum EstadoVerificacion {
  pendiente('Pendiente'),
  aprobado('Aprobado'),
  rechazado('Rechazado');

  const EstadoVerificacion(this.etiqueta);

  final String etiqueta;

  /// En BD el aprobado se guarda como `VERIFICADO` (ver seeds y migración 002).
  static EstadoVerificacion desde(String valor) =>
      switch (valor.trim().toUpperCase()) {
        'VERIFICADO' || 'APROBADO' => aprobado,
        'RECHAZADO' => rechazado,
        _ => pendiente,
      };
}

enum TipoAliado {
  personaNatural('Persona natural'),
  empresa('Empresa');

  const TipoAliado(this.etiqueta);

  final String etiqueta;

  static TipoAliado desde(String valor) =>
      valor.trim().toUpperCase() == 'PERSONA_JURIDICA'
      ? empresa
      : personaNatural;
}

/// Registro de un aliado candidato visto desde la bandeja del administrador.
class SolicitudAliado extends Equatable {
  const SolicitudAliado({
    required this.id,
    required this.nombre,
    required this.email,
    required this.tipo,
    required this.estado,
    required this.fechaRegistro,
    this.categorias = const [],
    this.documentos = const [],
    this.motivoRechazo,
    this.fechaVerificacion,
  });

  final String id;
  final String nombre;
  final String email;
  final TipoAliado tipo;
  final EstadoVerificacion estado;
  final DateTime fechaRegistro;
  final List<String> categorias;
  final List<DocumentoKyc> documentos;
  final String? motivoRechazo;
  final DateTime? fechaVerificacion;

  bool get estaPendiente => estado == EstadoVerificacion.pendiente;
  bool get tieneDocumentos => documentos.isNotEmpty;

  /// "CM" para "Carlos Mendoza" — avatar de la tarjeta.
  String get iniciales {
    final palabras = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    return palabras.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// Días que lleva esperando respuesta (para priorizar la bandeja).
  int diasEnEspera(DateTime ahora) => ahora.difference(fechaRegistro).inDays;

  bool coincideCon(String consulta) {
    final q = consulta.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombre.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q) ||
        categorias.any((c) => c.toLowerCase().contains(q));
  }

  @override
  List<Object?> get props => [
    id,
    nombre,
    email,
    tipo,
    estado,
    fechaRegistro,
    categorias,
    documentos,
    motivoRechazo,
    fechaVerificacion,
  ];
}
