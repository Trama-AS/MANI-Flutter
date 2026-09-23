import '../repositories/i_categories_repository.dart';

class GetSelectedCategoriesUseCase {
  final ICategoriesRepository repository;

  GetSelectedCategoriesUseCase(this.repository);

  Future<Set<String>> call() {
    return repository.getSelectedCategoryIds();
  }
}
