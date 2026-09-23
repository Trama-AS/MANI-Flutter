import 'package:mani/features/profile_categories/data/datasources/categories_remote_datasource.dart';
import 'package:mani/features/profile_categories/domain/entities/category_entity.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';
import 'package:mani/features/profile_categories/domain/repositories/i_categories_repository.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_available_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/save_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/presentation/bloc/categories_cubit.dart';

const plomeria = CategoryEntity(id: 'c-plo', label: 'Plomería', emoji: '🔧');
const electricidad = CategoryEntity(
  id: 'c-ele',
  label: 'Electricidad',
  emoji: '💡',
);
const cerrajeria = CategoryEntity(
  id: 'c-cer',
  label: 'Cerrajería',
  emoji: '🔑',
);

/// Repositorio en memoria que imita las reglas de las RPC de la migración 004.
class FakeCategoriesRepository implements ICategoriesRepository {
  FakeCategoriesRepository({
    this.catalogo = const [plomeria, electricidad, cerrajeria],
    Set<String> guardadas = const {},
    this.fallaCarga,
    this.fallaGuardado,
  }) : guardadas = {...guardadas};

  final List<CategoryEntity> catalogo;
  Set<String> guardadas;
  CategoriesFailure? fallaCarga;
  CategoriesFailure? fallaGuardado;

  Set<String>? ultimoEnvio;
  int llamadasGuardar = 0;

  @override
  Future<List<CategoryEntity>> getAvailableCategories() async {
    if (fallaCarga != null) throw fallaCarga!;
    return catalogo;
  }

  @override
  Future<Set<String>> getSelectedCategoryIds() async {
    if (fallaCarga != null) throw fallaCarga!;
    return guardadas;
  }

  @override
  Future<Set<String>> saveSelectedCategories(Set<String> categoryIds) async {
    llamadasGuardar++;
    ultimoEnvio = {...categoryIds};
    if (fallaGuardado != null) throw fallaGuardado!;
    guardadas = {...categoryIds};
    return guardadas;
  }
}

CategoriesCubit cubitCon(ICategoriesRepository repo) => CategoriesCubit(
  getAvailableCategoriesUseCase: GetAvailableCategoriesUseCase(repo),
  getSelectedCategoriesUseCase: GetSelectedCategoriesUseCase(repo),
  saveSelectedCategoriesUseCase: SaveSelectedCategoriesUseCase(repo),
);

/// Datasource que devuelve respuestas crudas o lanza la excepción indicada.
class FakeCategoriesDataSource implements CategoriesRemoteDataSource {
  List<Map<String, dynamic>> catalogo = const [];
  List<String> mias = const [];
  Object? error;
  List<String>? ultimoEnvio;

  @override
  Future<List<Map<String, dynamic>>> listarCategoriasTenant() async {
    if (error != null) throw error!;
    return catalogo;
  }

  @override
  Future<List<String>> obtenerMisCategorias() async {
    if (error != null) throw error!;
    return mias;
  }

  @override
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds) async {
    ultimoEnvio = categoriaIds;
    if (error != null) throw error!;
    return categoriaIds;
  }
}
