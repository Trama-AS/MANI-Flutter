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
    this.aliadosAvisados = true,
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

  /// `false` si la solicitud quedó guardada pero Dispatch no alcanzó a
  /// ofrecerla a los aliados (SCRUM-1402); el cliente puede reintentar.
  final bool aliadosAvisados;

  SolicitudPublicada conAviso(bool avisados) => SolicitudPublicada(
    id: id,
    categoria: categoria,
    descripcion: descripcion,
    direccion: direccion,
    zona: zona,
    fechaCreacion: fechaCreacion,
    zonaPadre: zonaPadre,
    modalidad: modalidad,
    cantidadFotos: cantidadFotos,
    aliadosAvisados: avisados,
  );

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
    aliadosAvisados,
  ];
}
