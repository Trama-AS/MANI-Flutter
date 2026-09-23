part of 'categories_cubit.dart';

class CategoriesState extends Equatable {
  final List<CategoryEntity> categories;
  final Set<String> selectedIds;
  final bool isLoading;
  final bool isSaving;
  final bool attemptedSave;
  final bool saveSuccess;

  /// Error al cargar: la pantalla muestra el mensaje y un botón Reintentar.
  final CategoriesFailure? loadFailure;

  /// Error al guardar: la selección se conserva para reintentar.
  final CategoriesFailure? saveFailure;

  const CategoriesState({
    this.categories = const [],
    this.selectedIds = const {},
    this.isLoading = false,
    this.isSaving = false,
    this.attemptedSave = false,
    this.saveSuccess = false,
    this.loadFailure,
    this.saveFailure,
  });

  bool get showError => attemptedSave && selectedIds.isEmpty;

  static const _unset = Object();

  CategoriesState copyWith({
    List<CategoryEntity>? categories,
    Set<String>? selectedIds,
    bool? isLoading,
    bool? isSaving,
    bool? attemptedSave,
    bool? saveSuccess,
    Object? loadFailure = _unset,
    Object? saveFailure = _unset,
  }) {
    return CategoriesState(
      categories: categories ?? this.categories,
      selectedIds: selectedIds ?? this.selectedIds,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      attemptedSave: attemptedSave ?? this.attemptedSave,
      saveSuccess: saveSuccess ?? this.saveSuccess,
      loadFailure: identical(loadFailure, _unset)
          ? this.loadFailure
          : loadFailure as CategoriesFailure?,
      saveFailure: identical(saveFailure, _unset)
          ? this.saveFailure
          : saveFailure as CategoriesFailure?,
    );
  }

  @override
  List<Object?> get props => [
    categories,
    selectedIds,
    isLoading,
    isSaving,
    attemptedSave,
    saveSuccess,
    loadFailure,
    saveFailure,
  ];
}
