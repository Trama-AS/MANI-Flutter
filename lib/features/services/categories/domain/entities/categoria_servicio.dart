import 'package:equatable/equatable.dart';

import 'flujo_operativo.dart';

/// Categoría del catálogo de servicios de un tenant (ej. "Plomería").
class CategoriaServicio extends Equatable {
  const CategoriaServicio({
    required this.id,
    required this.nombre,
    required this.activa,
    this.flujo,
    this.fechaCreacion,
    this.aliadosAsociados = 0,
  });

  final String id;
  final String nombre;

  /// Solo las categorías activas aparecen en el catálogo de los clientes.
  final bool activa;

  /// `null` cuando la BD tiene un flujo que la app no reconoce (dato histórico).
  final FlujoOperativo? flujo;
  final DateTime? fechaCreacion;

  /// Aliados que declararon esta especialidad.
  final int aliadosAsociados;

  /// Clave de comparación para detectar nombres repetidos: igual que el índice
  /// único de BD (`lower(btrim(nombre))`), más espacios internos colapsados.
  String get claveNombre => normalizarClaveNombre(nombre);

  bool coincideCon(String consulta) {
    final q = consulta.trim().toLowerCase();
    return q.isEmpty || nombre.toLowerCase().contains(q);
  }

  @override
  List<Object?> get props => [
    id,
    nombre,
    activa,
    flujo,
    fechaCreacion,
    aliadosAsociados,
  ];
}

/// Colapsa espacios y recorta: "  Aire   acondicionado " → "Aire acondicionado".
String normalizarNombre(String nombre) =>
    nombre.trim().replaceAll(RegExp(r'\s+'), ' ');

String normalizarClaveNombre(String nombre) =>
    normalizarNombre(nombre).toLowerCase();
