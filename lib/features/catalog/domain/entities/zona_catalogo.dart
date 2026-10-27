import 'package:flutter/foundation.dart';

/// Nodo del catálogo geográfico expuesto por Core
/// (`GET /api/v1/core/catalog/zones`, HU-M04-04 / REST-01).
///
/// No tiene `tenantId`: la tabla `zona` es un catálogo global compartido por
/// todos los tenants. El aislamiento lo aplica el Gateway, que exige el JWT y
/// deja que Core derive tenant y rol del claim.
@immutable
class ZonaCatalogo {
  const ZonaCatalogo({
    required this.id,
    required this.nombre,
    required this.nivel,
    required this.seleccionable,
    this.zonaPadreId,
    this.hijos = const [],
  });

  factory ZonaCatalogo.fromJson(Map<String, dynamic> json) => ZonaCatalogo(
    id: (json['id'] ?? '').toString(),
    nombre: (json['name'] ?? '').toString(),
    nivel: (json['level'] ?? '').toString(),
    // El contrato distingue "consultable" de "escogible": una zona
    // desactivada llega con `selectable: false` y no debe ofrecerse.
    seleccionable: json['selectable'] == true,
    zonaPadreId: json['parentId']?.toString(),
    hijos: (json['children'] is List)
        ? (json['children'] as List)
              .whereType<Map<String, dynamic>>()
              .map(ZonaCatalogo.fromJson)
              .toList(growable: false)
        : const [],
  );

  final String id;
  final String nombre;
  final String nivel;
  final bool seleccionable;
  final String? zonaPadreId;
  final List<ZonaCatalogo> hijos;

  /// Etiqueta jerárquica para un desplegable: "Bogotá D.C. · Chapinero".
  /// Se arma con el camino recibido del contrato, no concatenando nombres a
  /// mano en cada pantalla.
  String etiquetaCon(List<String> nombresAncestros) =>
      [...nombresAncestros, nombre].join(' · ');
}
