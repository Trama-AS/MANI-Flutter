import '../models/category_model.dart';

/// Fuente de datos temporal (mock) mientras el backend expone
/// los endpoints reales en Supabase. Se reemplaza por una
/// CategoriesRemoteDataSource sin tocar el resto de las capas.
abstract class CategoriesLocalDataSource {
  Future<List<CategoryModel>> getAvailableCategories();
  Future<void> saveSelectedCategories(List<String> categoryIds);
}

class CategoriesLocalDataSourceImpl implements CategoriesLocalDataSource {
  static const List<CategoryModel> _mockCategories = [
    CategoryModel(id: 'plomeria', label: 'Plomería', emoji: '🔧'),
    CategoryModel(id: 'electricidad', label: 'Electricidad', emoji: '💡'),
    CategoryModel(id: 'carpinteria', label: 'Carpintería', emoji: '🪚'),
    CategoryModel(id: 'pintura', label: 'Pintura', emoji: '🎨'),
    CategoryModel(id: 'jardineria', label: 'Jardinería', emoji: '🌿'),
    CategoryModel(id: 'limpieza', label: 'Limpieza del hogar', emoji: '🧹'),
    CategoryModel(id: 'cerrajeria', label: 'Cerrajería', emoji: '🔑'),
    CategoryModel(id: 'aire', label: 'Aire acondicionado', emoji: '❄️'),
  ];

  @override
  Future<List<CategoryModel>> getAvailableCategories() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockCategories;
  }

  @override
  Future<void> saveSelectedCategories(List<String> categoryIds) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // TODO: reemplazar por escritura real en Supabase cuando el
    // backend exponga el endpoint/tabla correspondiente.
  }
}