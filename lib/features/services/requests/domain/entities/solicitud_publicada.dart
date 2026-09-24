import 'package:equatable/equatable.dart';

import 'catalogo_solicitud.dart';

/// Solicitud ya guardada, tal como la confirmó el servidor.
class SolicitudPublicada extends Equatable {
  const SolicitudPublicada({
    required this.id,
    required this.categoria,
    required this.descripcion,
    required this.direccion,
    required this.zona,
    required this.fechaCreacion,
    this.zonaPadre,
    this.modalidad = ModalidadCobro.desconocida,
    this.cantidadFotos = 0,
  });

  final String id;
  final String categoria;
  final ModalidadCobro modalidad;
  final String descripcion;
  final String direccion;
  final String zona;
  final String? zonaPadre;
  final int cantidadFotos;
  final DateTime fechaCreacion;

  String get ubicacion => [
    zona,
    if (zonaPadre != null && zonaPadre!.isNotEmpty) zonaPadre!,
  ].join(' · ');

  @override
  List<Object?> get props => [
    id,
    categoria,
    modalidad,
    descripcion,
    direccion,
    zona,
    zonaPadre,
    cantidadFotos,
    fechaCreacion,
  ];
}
