import 'package:equatable/equatable.dart';

/// Estado de una cotización en Core (RF-15, RF-17). Un estado que la app no
/// conoce se muestra tal cual en vez de esconderse.
enum EstadoCotizacion {
  pendiente('Pendiente de respuesta'),
  aceptada('Aceptada'),
  rechazada('Rechazada'),
  ajusteSolicitado('Ajuste solicitado'),
  expirada('Expirada'),
  otro('');

  const EstadoCotizacion(this.etiqueta);

  final String etiqueta;

  static EstadoCotizacion desde(String valor) =>
      switch (valor.trim().toUpperCase()) {
        'PENDIENTE' => pendiente,
        'ACEPTADA' => aceptada,
        'RECHAZADA' => rechazada,
        'AJUSTE_SOLICITADO' => ajusteSolicitado,
        'EXPIRADA' => expirada,
        _ => otro,
      };
}

/// Una versión de la cotización de una solicitud (US-04.2.1 / SCRUM-865).
/// El total y la versión los calcula Core; la app no los recalcula.
class Cotizacion extends Equatable {
  const Cotizacion({
    required this.id,
    required this.solicitudId,
    required this.version,
    required this.estadoCrudo,
    required this.valorManoObra,
    required this.valorMateriales,
    required this.total,
    this.creadaEn,
  });

  factory Cotizacion.fromJson(Map<String, dynamic> json) => Cotizacion(
    id: json['id'] as String,
    solicitudId: (json['solicitudId'] as String?) ?? '',
    version: (json['version'] as num?)?.toInt() ?? 0,
    estadoCrudo: (json['estado'] as String?) ?? '',
    valorManoObra: _numero(json['valorManoObra']),
    valorMateriales: _numero(json['valorMateriales']),
    total: _numero(json['total']),
    creadaEn: DateTime.tryParse((json['creadaEn'] as String?) ?? '')?.toLocal(),
  );

  final String id;
  final String solicitudId;
  final int version;
  final String estadoCrudo;
  final double valorManoObra;
  final double valorMateriales;
  final double total;
  final DateTime? creadaEn;

  EstadoCotizacion get estado => EstadoCotizacion.desde(estadoCrudo);

  String get etiquetaEstado =>
      estado == EstadoCotizacion.otro ? estadoCrudo : estado.etiqueta;

  bool get pendiente => estado == EstadoCotizacion.pendiente;

  static double _numero(Object? v) => switch (v) {
    num n => n.toDouble(),
    String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  @override
  List<Object?> get props => [
    id,
    solicitudId,
    version,
    estadoCrudo,
    valorManoObra,
    valorMateriales,
    total,
    creadaEn,
  ];
}

/// Decisión del cliente sobre la cotización pendiente (US-04.2.3 / SCRUM-867).
enum DecisionCotizacion {
  aceptar('aceptar'),
  rechazar('rechazar'),
  ajustar('ajustar');

  const DecisionCotizacion(this.ruta);

  /// Último segmento de `POST /cotizaciones/{id}/<ruta>`.
  final String ruta;
}

enum CotizacionErrorTipo {
  sinConexion,
  sinSesion,
  sinPermiso,
  noEncontrada,
  datosInvalidos,
  conflicto,
  servicioNoDisponible,
  desconocido,
}

/// Fallo de una operación de cotización con el mensaje para el usuario.
/// [detalle] es el texto de Core cuando ayuda a corregir (400 y 409).
class CotizacionFailure extends Equatable implements Exception {
  const CotizacionFailure(this.tipo, [this.detalle]);

  final CotizacionErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    CotizacionErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu red e inténtalo de nuevo.',
    CotizacionErrorTipo.sinSesion =>
      'Tu sesión expiró. Inicia sesión de nuevo.',
    CotizacionErrorTipo.sinPermiso =>
      'Tu cuenta no puede hacer esta acción sobre la cotización.',
    CotizacionErrorTipo.noEncontrada =>
      'No encontramos esta solicitud o cotización.',
    CotizacionErrorTipo.datosInvalidos =>
      detalle ?? 'Revisa los datos ingresados.',
    CotizacionErrorTipo.conflicto =>
      detalle ??
          'La cotización cambió mientras la veías. Actualiza para ver su estado.',
    CotizacionErrorTipo.servicioNoDisponible =>
      'El servicio no está disponible. Inténtalo en unos minutos.',
    CotizacionErrorTipo.desconocido =>
      'No se pudo completar la acción. Inténtalo de nuevo.',
  };

  @override
  List<Object?> get props => [tipo, detalle];
}
