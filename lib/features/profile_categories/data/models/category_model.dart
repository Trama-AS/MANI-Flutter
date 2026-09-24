import '../../domain/entities/category_entity.dart';

/// Modelo de datos de `listar_categorias_tenant` (`{id, nombre}`).
/// La tabla `categoria_servicio` no guarda ícono: el emoji se deriva del
/// nombre y, si no coincide ninguno, se usa uno genérico.
class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.label,
    required super.emoji,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    final nombre = json['nombre'] as String;
    return CategoryModel(
      id: json['id'] as String,
      label: nombre,
      emoji: emojiPara(nombre),
    );
  }

  static const _emojis = <String, String>{
    'plomer': '🔧',
    'electric': '💡',
    'carpinter': '🪚',
    'pintur': '🎨',
    'jardin': '🌿',
    'limpieza': '🧹',
    'cerrajer': '🔑',
    'aire': '❄️',
  };

  static String emojiPara(String nombre) {
    final n = nombre.toLowerCase();
    for (final e in _emojis.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return '🛠️';
  }
}
