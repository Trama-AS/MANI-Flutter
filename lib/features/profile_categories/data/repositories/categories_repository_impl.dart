import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/i_categories_repository.dart';
import '../datasources/categories_local_datasource.dart';

class CategoriesRepositoryImpl implements ICategoriesRepository {
  final CategoriesLocalDataSource localDataSource;

  CategoriesRepositoryImpl({required this.localDataSource});

  @override
  Future<List<CategoryEntity>> getAvailableCategories() {
    return localDataSource.getAvailableCategories();
  }

  @override
  Future<void> saveSelectedCategories(List<String> categoryIds) {
    return localDataSource.saveSelectedCategories(categoryIds);
  }
}