import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mani/features/profile_categories/domain/entities/category_entity.dart';
import 'package:mani/features/profile_categories/domain/failures/categories_failure.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_available_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/save_selected_categories_usecase.dart';

part 'categories_state.dart';

/// Cubit de selección de categorías del aliado (US-03.1.3).
/// Coordina los casos de uso y emite estados de UI.
class CategoriesCubit extends Cubit<CategoriesState> {
  CategoriesCubit({
    required this.getAvailableCategoriesUseCase,
    required this.getSelectedCategoriesUseCase,
    required this.saveSelectedCategoriesUseCase,
  }) : super(const CategoriesState()) {
    loadCategories();
  }

  final GetAvailableCategoriesUseCase getAvailableCategoriesUseCase;
  final GetSelectedCategoriesUseCase getSelectedCategoriesUseCase;
  final SaveSelectedCategoriesUseCase saveSelectedCategoriesUseCase;

  /// Carga el catálogo del tenant y marca las categorías ya declaradas.
  Future<void> loadCategories() async {
    emit(state.copyWith(isLoading: true, loadFailure: null));
    try {
      final results = await Future.wait([
        getAvailableCategoriesUseCase(),
        getSelectedCategoriesUseCase(),
      ]);
      final categories = results[0] as List<CategoryEntity>;
      final available = categories.map((c) => c.id).toSet();
      final selected = (results[1] as Set<String>).intersection(available);
      emit(
        state.copyWith(
          categories: categories,
          selectedIds: selected,
          isLoading: false,
        ),
      );
    } on CategoriesFailure catch (f) {
      emit(state.copyWith(isLoading: false, loadFailure: f));
    }
  }

  void toggleCategory(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    emit(
      state.copyWith(
        selectedIds: updated,
        saveSuccess: false,
        saveFailure: null,
      ),
    );
  }

  Future<void> save() async {
    if (state.isSaving) return;
    emit(state.copyWith(attemptedSave: true, saveSuccess: false));
    if (state.selectedIds.isEmpty) return;
    emit(state.copyWith(isSaving: true, saveFailure: null));
    try {
      final saved = await saveSelectedCategoriesUseCase(state.selectedIds);
      emit(
        state.copyWith(selectedIds: saved, isSaving: false, saveSuccess: true),
      );
    } on CategoriesFailure catch (f) {
      emit(state.copyWith(isSaving: false, saveFailure: f));
    }
  }
}
