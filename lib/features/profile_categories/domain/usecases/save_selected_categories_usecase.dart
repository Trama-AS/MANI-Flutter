import '../repositories/i_categories_repository.dart';

class SaveSelectedCategoriesUseCase {
  final ICategoriesRepository repository;

  SaveSelectedCategoriesUseCase(this.repository);

  Future<Set<String>> call(Set<String> categoryIds) {
    return repository.saveSelectedCategories(categoryIds);
  }
}
