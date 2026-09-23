import 'package:equatable/equatable.dart';

import 'solicitud_entity.dart';

/// Bandeja del aliado separada en lo que puede tomar y lo que ya es suyo.
class BandejaSolicitudes extends Equatable {
  const BandejaSolicitudes({
    this.disponibles = const [],
    this.misTrabajos = const [],
  });

  /// Reparte y ordena: disponibles de la más antigua a la más reciente (el
  /// cliente que más espera va primero) y mis trabajos del más reciente al
  /// más antiguo.
  factory BandejaSolicitudes.desde(Iterable<SolicitudEntity> solicitudes) {
    final disponibles = solicitudes.where((s) => s.estaDisponible).toList()
      ..sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));
    DateTime fecha(SolicitudEntity s) => s.fechaAsignacion ?? s.fechaCreacion;
    final mias = solicitudes.where((s) => s.esMia).toList()
      ..sort((a, b) => fecha(b).compareTo(fecha(a)));
    return BandejaSolicitudes(disponibles: disponibles, misTrabajos: mias);
  }

  final List<SolicitudEntity> disponibles;
  final List<SolicitudEntity> misTrabajos;

  SolicitudEntity? porId(String id) {
    for (final s in [...disponibles, ...misTrabajos]) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  /// Quita la solicitud de disponibles (rechazada o tomada por otro).
  BandejaSolicitudes sin(String id) => BandejaSolicitudes(
    disponibles: disponibles.where((s) => s.id != id).toList(),
    misTrabajos: misTrabajos,
  );

  /// Mueve [asignada] a mis trabajos (al principio: es la más reciente).
  BandejaSolicitudes conAsignada(SolicitudEntity asignada) =>
      BandejaSolicitudes(
        disponibles: disponibles.where((s) => s.id != asignada.id).toList(),
        misTrabajos: [
          asignada,
          ...misTrabajos.where((s) => s.id != asignada.id),
        ],
      );

  @override
  List<Object?> get props => [disponibles, misTrabajos];
}
