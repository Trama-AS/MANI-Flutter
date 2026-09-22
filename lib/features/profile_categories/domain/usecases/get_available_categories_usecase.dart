import '../entities/category_entity.dart';
import '../repositories/i_categories_repository.dart';

class GetAvailableCategoriesUseCase {
  final ICategoriesRepository repository;

  GetAvailableCategoriesUseCase(this.repository);

  Future<List<CategoryEntity>> call() {
    return repository.getAvailableCategories();
  }
}