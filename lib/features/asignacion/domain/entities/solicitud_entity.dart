import 'package:equatable/equatable.dart';

import 'modalidad_servicio.dart';
import 'regla_sitio.dart';

/// Estados de una solicitud relevantes para su asignación (RF-14).
///
/// Equivalente al campo `estado` de la tabla `solicitud` (DD-MANI.md §7.1).
/// Cualquier estado posterior (en curso, cerrada…) se trata como [otro].
enum EstadoSolicitud {
  pendiente,
  asignada,
  otro;

  static EstadoSolicitud desde(String? valor) =>
      switch (valor?.trim().toUpperCase()) {
        'PENDIENTE' => pendiente,
        'ASIGNADA' => asignada,
        _ => otro,
      };
}

/// Solicitud de servicio vista desde la bandeja del aliado (US-04.1.4).
///
/// Inmutable y libre de dependencias de infraestructura.
/// Referencias: RF-14, DD-MANI.md §7.1, QS-06, QS-09, ADR-0016.
class SolicitudEntity extends Equatable {
  const SolicitudEntity({
    required this.id,
    required this.estado,
    required this.categoria,
    required this.zona,
    required this.fechaCreacion,
    this.esMia = false,
    this.modalidad = ModalidadServicio.desconocida,
    this.zonaPadre,
    this.reglasSitio = const [],
    this.descripcion,
    this.cantidadFotos = 0,
    this.direccion,
    this.fechaAsignacion,
  });

  final String id;
  final EstadoSolicitud estado;

  /// `true` si está asignada al aliado autenticado.
  final bool esMia;

  /// Nombre de la categoría de servicio (ej. "Plomería").
  final String categoria;
  final ModalidadServicio modalidad;

  /// Barrio o zona del servicio y su zona superior (ej. localidad).
  final String zona;
  final String? zonaPadre;

  /// Reglas del sitio: visibles ANTES de aceptar (QS-06).
  final List<ReglaSitio> reglasSitio;

  /// Problema descrito por el cliente al publicar (US-04.1.1).
  final String? descripcion;

  /// Fotos que adjuntó el cliente.
  final int cantidadFotos;

  /// Dirección exacta: el servidor solo la envía cuando la solicitud es mía.
  final String? direccion;
  final DateTime fechaCreacion;
  final DateTime? fechaAsignacion;

  /// Se puede aceptar o rechazar: sigue pendiente y no es de nadie.
  bool get estaDisponible => estado == EstadoSolicitud.pendiente && !esMia;

  /// "Roma Norte · Cuauhtémoc".
  String get ubicacion => [
    zona,
    if (zonaPadre != null && zonaPadre!.isNotEmpty) zonaPadre!,
  ].join(' · ');

  /// Minutos que el cliente lleva esperando a que alguien acepte.
  int minutosEsperando(DateTime ahora) =>
      ahora.difference(fechaCreacion).inMinutes;

  @override
  List<Object?> get props => [
    id,
    estado,
    esMia,
    categoria,
    modalidad,
    zona,
    zonaPadre,
    reglasSitio,
    descripcion,
    cantidadFotos,
    direccion,
    fechaCreacion,
    fechaAsignacion,
  ];
}
