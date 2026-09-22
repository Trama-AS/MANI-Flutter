class Category {
  final String id;
  final String label;
  final String emoji;

  const Category({
    required this.id,
    required this.label,
    required this.emoji,
  });
}

const List<Category> mockCategories = [
  Category(id: 'plomeria', label: 'Plomería', emoji: '🔧'),
  Category(id: 'electricidad', label: 'Electricidad', emoji: '💡'),
  Category(id: 'carpinteria', label: 'Carpintería', emoji: '🪚'),
  Category(id: 'pintura', label: 'Pintura', emoji: '🎨'),
  Category(id: 'jardineria', label: 'Jardinería', emoji: '🌿'),
  Category(id: 'limpieza', label: 'Limpieza del hogar', emoji: '🧹'),
  Category(id: 'cerrajeria', label: 'Cerrajería', emoji: '🔑'),
  Category(id: 'aire', label: 'Aire acondicionado', emoji: '❄️'),
];