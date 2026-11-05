part of 'categories_cubit.dart';

class CategoriesState extends Equatable {
  final List<CategoryEntity> categories;
  final Set<String> selectedIds;

  /// Lo último que el servidor confirmó. La pantalla trabaja sobre
  /// [selectedIds], que puede ir por delante mientras el aliado marca y
  /// desmarca; esto es el punto al que se vuelve si el servidor rechaza el
  /// guardado, para no afirmar en pantalla un estado que la base no tiene
  /// (SCRUM-1632).
  final Set<String> selectedIdsConfirmadas;
  final bool isLoading;
  final bool isSaving;
  final bool attemptedSave;
  final bool saveSuccess;

  /// Error al cargar: la pantalla muestra el mensaje y un botón Reintentar.
  final CategoriesFailure? loadFailure;

  /// Error al guardar. Si el servidor respondió y rechazó, la selección vuelve
  /// a [selectedIdsConfirmadas]; si falló la red, se conserva para reintentar.
  final CategoriesFailure? saveFailure;

  const CategoriesState({
    this.categories = const [],
    this.selectedIds = const {},
    this.selectedIdsConfirmadas = const {},
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
    Set<String>? selectedIdsConfirmadas,
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
      selectedIdsConfirmadas:
          selectedIdsConfirmadas ?? this.selectedIdsConfirmadas,
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
    selectedIdsConfirmadas,
    isLoading,
    isSaving,
    attemptedSave,
    saveSuccess,
    loadFailure,
    saveFailure,
  ];
}
