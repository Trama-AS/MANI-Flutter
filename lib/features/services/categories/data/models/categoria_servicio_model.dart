import '../../domain/entities/categoria_servicio.dart';
import '../../domain/entities/flujo_operativo.dart';

/// Mapea el JSON que devuelve `_cat_json` (migración 003) o Core Node a través
/// del API Gateway (`/api/v1/core/catalog/categories`).
class CategoriaServicioModel extends CategoriaServicio {
  const CategoriaServicioModel({
    required super.id,
    required super.nombre,
    required super.activa,
    super.flujo,
    super.fechaCreacion,
    super.aliadosAsociados,
  });

  factory CategoriaServicioModel.fromJson(Map<String, dynamic> json) {
    final map = json['category'] is Map
        ? Map<String, dynamic>.from(json['category'] as Map)
        : json;
    final bool activa;
    if (map['active'] is bool) {
      activa = map['active'] as bool;
    } else if (map['activa'] is bool) {
      activa = map['activa'] as bool;
    } else {
      activa = (map['estado'] as String? ?? '').toUpperCase() == 'ACTIVO';
    }
    final fechaRaw = map['created_at'] ?? map['createdAt'];
    return CategoriaServicioModel(
      id: map['id'] as String,
      nombre: (map['nombre'] ?? map['name']) as String? ?? '',
      activa: activa,
      flujo: FlujoOperativo.desde(
        (map['flujo_operativo'] ?? map['flujoOperativo']) as String?,
      ),
      fechaCreacion: fechaRaw is String
          ? DateTime.tryParse(fechaRaw)?.toLocal()
          : null,
      aliadosAsociados:
          ((map['aliados'] ?? map['aliadosAsociados'] ?? map['alliesCount'])
                  as num?)
              ?.toInt() ??
          0,
    );
  }
}
