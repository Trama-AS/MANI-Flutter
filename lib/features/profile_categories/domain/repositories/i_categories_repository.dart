import '../entities/category_entity.dart';

/// Contrato del repositorio de categorías.
/// La capa de dominio no conoce Supabase ni ninguna fuente de datos concreta.
abstract class ICategoriesRepository {
  Future<List<CategoryEntity>> getAvailableCategories();
  Future<void> saveSelectedCategories(List<String> categoryIds);
}
