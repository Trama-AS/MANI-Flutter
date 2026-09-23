part of 'categories_cubit.dart';

class CategoriesState extends Equatable {
  final List<CategoryEntity> categories;
  final Set<String> selectedIds;
  final bool isLoading;
  final bool attemptedSave;
  final bool saveSuccess;

  const CategoriesState({
    this.categories = const [],
    this.selectedIds = const {},
    this.isLoading = false,
    this.attemptedSave = false,
    this.saveSuccess = false,
  });

  bool get showError => attemptedSave && selectedIds.isEmpty;

  CategoriesState copyWith({
    List<CategoryEntity>? categories,
    Set<String>? selectedIds,
    bool? isLoading,
    bool? attemptedSave,
    bool? saveSuccess,
  }) {
    return CategoriesState(
      categories: categories ?? this.categories,
      selectedIds: selectedIds ?? this.selectedIds,
      isLoading: isLoading ?? this.isLoading,
      attemptedSave: attemptedSave ?? this.attemptedSave,
      saveSuccess: saveSuccess ?? this.saveSuccess,
    );
  }

  @override
  List<Object?> get props => [
    categories,
    selectedIds,
    isLoading,
    attemptedSave,
    saveSuccess,
  ];
}
