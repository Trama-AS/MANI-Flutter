import 'package:equatable/equatable.dart';

/// Estado de una solicitud del cliente, con el texto que se le muestra.
///
/// Los valores salen de `solicitud.estado` en Core. Un estado que la app no
/// conoce se muestra tal cual en vez de esconderse.
enum EstadoSeguimiento {
  pendiente('Buscando aliado'),
  asignada('Aliado asignado'),
  enEjecucion('En ejecución'),
  finalizada('Finalizada'),
  cancelada('Cancelada'),
  otro('');

  const EstadoSeguimiento(this.etiqueta);

  final String etiqueta;

  static EstadoSeguimiento desde(String valor) =>
      switch (valor.trim().toUpperCase()) {
        'PENDIENTE' => pendiente,
        'ASIGNADA' => asignada,
        'EN_EJECUCION' || 'EN_CURSO' => enEjecucion,
        'FINALIZADA' || 'CERRADA' || 'COMPLETADA' => finalizada,
        'CANCELADA' => cancelada,
        _ => otro,
      };
}

/// Seguimiento simplificado de una solicitud (HU-M07-04 / SCRUM-871).
///
/// [zona] es la zona que el cliente declaró al publicar la solicitud, no la
/// ubicación del aliado: no hay rastreo en vivo (SRS §1.2). [actualizadaEn]
/// dice de cuándo es el estado; se refresca al volver a consultar.
class SolicitudSeguimiento extends Equatable {
  const SolicitudSeguimiento({
    required this.id,
    required this.estadoCrudo,
    required this.categoria,
    required this.zona,
    required this.actualizadaEn,
    this.zonaPadre,
    this.creadaEn,
  });

  factory SolicitudSeguimiento.fromJson(Map<String, dynamic> json) {
    final zona = json['zonaDeclarada'] is Map
        ? Map<String, dynamic>.from(json['zonaDeclarada'] as Map)
        : const <String, dynamic>{};
    return SolicitudSeguimiento(
      id: json['id'] as String,
      estadoCrudo: (json['estado'] as String?) ?? '',
      categoria: (json['categoria'] as String?) ?? 'Servicio',
      zona: (zona['nombre'] as String?) ?? '',
      zonaPadre: zona['zonaPadre'] as String?,
      creadaEn: _fecha(json['creadaEn']),
      actualizadaEn:
          _fecha(json['actualizadaEn']) ??
          _fecha(json['creadaEn']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String estadoCrudo;
  final String categoria;
  final String zona;
  final String? zonaPadre;
  final DateTime? creadaEn;
  final DateTime actualizadaEn;

  EstadoSeguimiento get estado => EstadoSeguimiento.desde(estadoCrudo);

  /// Texto del estado; si la app no lo conoce, el valor que envió Core.
  String get etiquetaEstado =>
      estado == EstadoSeguimiento.otro ? estadoCrudo : estado.etiqueta;

  /// "Chapinero · Bogotá".
  String get zonaCompleta => [
    zona,
    if (zonaPadre != null && zonaPadre!.isNotEmpty) zonaPadre!,
  ].where((p) => p.isNotEmpty).join(' · ');

  @override
  List<Object?> get props => [
    id,
    estadoCrudo,
    categoria,
    zona,
    zonaPadre,
    creadaEn,
    actualizadaEn,
  ];
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;

/// Errores al consultar el seguimiento. Los códigos `MANI-SOL-*` los emite
/// Core en `/solicitudes/me` (contrato core.yaml del Gateway).
enum SeguimientoErrorTipo {
  sinSesion, // 401 / MANI-SOL-401
  noEsCliente, // MANI-SOL-403C
  sinConexion,
  servicioNoDisponible, // 5xx (T2)
  desconocido,
}

class SeguimientoFailure implements Exception {
  const SeguimientoFailure(this.tipo, [this.detalle]);

  final SeguimientoErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    SeguimientoErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para ver tus solicitudes.',
    SeguimientoErrorTipo.noEsCliente =>
      'Solo los clientes pueden consultar sus solicitudes.',
    SeguimientoErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
    SeguimientoErrorTipo.servicioNoDisponible =>
      'No pudimos consultar tus solicitudes porque el servicio no está disponible. Inténtalo en unos minutos.',
    SeguimientoErrorTipo.desconocido =>
      'No pudimos consultar tus solicitudes. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'SeguimientoFailure(${tipo.name}, $detalle)';
}
