import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mani/features/profile_categories/domain/entities/category_entity.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_available_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/save_selected_categories_usecase.dart';

part 'categories_state.dart';

/// Cubit de selección de categorías del aliado (US-03.1.3).
/// Coordina los casos de uso y emite estados de UI.
class CategoriesCubit extends Cubit<CategoriesState> {
  CategoriesCubit({
    required this.getAvailableCategoriesUseCase,
    required this.saveSelectedCategoriesUseCase,
  }) : super(const CategoriesState()) {
    loadCategories();
  }

  final GetAvailableCategoriesUseCase getAvailableCategoriesUseCase;
  final SaveSelectedCategoriesUseCase saveSelectedCategoriesUseCase;

  Future<void> loadCategories() async {
    emit(state.copyWith(isLoading: true));
    final categories = await getAvailableCategoriesUseCase();
    emit(state.copyWith(categories: categories, isLoading: false));
  }

  void toggleCategory(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    emit(state.copyWith(selectedIds: updated, saveSuccess: false));
  }

  Future<void> save() async {
    emit(state.copyWith(attemptedSave: true));
    if (state.selectedIds.isEmpty) return;
    await saveSelectedCategoriesUseCase(state.selectedIds);
    emit(state.copyWith(saveSuccess: true));
  }
}
