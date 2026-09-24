import '../entities/category_entity.dart';

/// Contrato del repositorio de categorías.
/// La capa de dominio no conoce Supabase ni ninguna fuente de datos concreta.
/// Todas las operaciones lanzan `CategoriesFailure` ante errores.
abstract class ICategoriesRepository {
  /// Categorías activas del tenant del aliado autenticado.
  Future<List<CategoryEntity>> getAvailableCategories();

  /// Ids de las categorías que el aliado autenticado ya declaró.
  Future<Set<String>> getSelectedCategoryIds();

  /// Reemplaza la selección completa del aliado autenticado.
  /// Devuelve los ids que quedaron guardados según el servidor.
  Future<Set<String>> saveSelectedCategories(Set<String> categoryIds);
}
