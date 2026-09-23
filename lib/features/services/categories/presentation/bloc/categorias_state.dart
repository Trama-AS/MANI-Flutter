part of 'categorias_cubit.dart';

enum CargaCategorias { inicial, cargando, listo, error }

/// Mensaje de un solo uso para SnackBar. El [id] cambia en cada aviso para que
/// dos mensajes iguales seguidos también se muestren.
class AvisoCategorias extends Equatable {
  const AvisoCategorias(this.id, this.mensaje, {this.esError = false});

  final int id;
  final String mensaje;
  final bool esError;

  @override
  List<Object?> get props => [id, mensaje, esError];
}

const Object _sinCambio = Object();

class CategoriasState extends Equatable {
  const CategoriasState({
    this.carga = CargaCategorias.inicial,
    this.categorias = const [],
    this.busqueda = '',
    this.guardando = false,
    this.recienCreadaId,
    this.error,
    this.aviso,
  });

  final CargaCategorias carga;
  final List<CategoriaServicio> categorias;
  final String busqueda;
  final bool guardando;

  /// Categoría recién creada, para resaltarla en el catálogo.
  final String? recienCreadaId;
  final CategoriaFailure? error;
  final AvisoCategorias? aviso;

  List<CategoriaServicio> get visibles =>
      categorias.where((c) => c.coincideCon(busqueda)).toList(growable: false);

  int get activas => categorias.where((c) => c.activa).length;
  int get ocultas => categorias.length - activas;

  CategoriasState copyWith({
    CargaCategorias? carga,
    List<CategoriaServicio>? categorias,
    String? busqueda,
    bool? guardando,
    Object? recienCreadaId = _sinCambio,
    Object? error = _sinCambio,
    Object? aviso = _sinCambio,
  }) => CategoriasState(
    carga: carga ?? this.carga,
    categorias: categorias ?? this.categorias,
    busqueda: busqueda ?? this.busqueda,
    guardando: guardando ?? this.guardando,
    recienCreadaId: identical(recienCreadaId, _sinCambio)
        ? this.recienCreadaId
        : recienCreadaId as String?,
    error: identical(error, _sinCambio)
        ? this.error
        : error as CategoriaFailure?,
    aviso: identical(aviso, _sinCambio)
        ? this.aviso
        : aviso as AvisoCategorias?,
  );

  @override
  List<Object?> get props => [
    carga,
    categorias,
    busqueda,
    guardando,
    recienCreadaId,
    error?.tipo,
    aviso,
  ];
}
