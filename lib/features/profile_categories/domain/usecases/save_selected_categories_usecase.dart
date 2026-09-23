import '../repositories/i_categories_repository.dart';

class SaveSelectedCategoriesUseCase {
  final ICategoriesRepository repository;

  SaveSelectedCategoriesUseCase(this.repository);

  Future<void> call(List<String> categoryIds) {
    return repository.saveSelectedCategories(categoryIds);
  }
}