import '../../domain/entities/categoria_servicio.dart';
import '../../domain/entities/flujo_operativo.dart';

/// Mapea el JSON que devuelve `_cat_json` (migración 003).
class CategoriaServicioModel extends CategoriaServicio {
  const CategoriaServicioModel({
    required super.id,
    required super.nombre,
    required super.activa,
    super.flujo,
    super.fechaCreacion,
    super.aliadosAsociados,
  });

  factory CategoriaServicioModel.fromJson(Map<String, dynamic> json) =>
      CategoriaServicioModel(
        id: json['id'] as String,
        nombre: json['nombre'] as String? ?? '',
        activa: (json['estado'] as String? ?? '').toUpperCase() == 'ACTIVO',
        flujo: FlujoOperativo.desde(json['flujo_operativo'] as String?),
        fechaCreacion: json['created_at'] is String
            ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
            : null,
        aliadosAsociados: (json['aliados'] as num?)?.toInt() ?? 0,
      );
}
