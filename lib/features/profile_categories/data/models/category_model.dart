import '../../domain/entities/category_entity.dart';

/// Modelo de datos: envuelve la entidad, listo para fromJson/toJson
/// cuando se conecte a Supabase.
class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.label,
    required super.emoji,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      label: json['label'] as String,
      emoji: json['emoji'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'emoji': emoji};
}
