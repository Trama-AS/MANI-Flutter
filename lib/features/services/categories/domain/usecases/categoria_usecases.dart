import '../entities/categoria_servicio.dart';
import '../entities/nueva_categoria.dart';
import '../failures/categoria_failure.dart';
import '../repositories/categorias_repository.dart';

/// Catálogo del tenant ordenado alfabéticamente (sin distinguir mayúsculas).
class ListarCategorias {
  const ListarCategorias(this._repo);
  final CategoriasRepository _repo;

  Future<List<CategoriaServicio>> call() async {
    final todas = await _repo.listar();
    return List.of(todas)
      ..sort((a, b) => a.claveNombre.compareTo(b.claveNombre));
  }
}

/// Crea una categoría. Si [existentes] ya contiene el mismo nombre falla sin
/// llamar a la red; el índice único de BD sigue siendo la última barrera.
class CrearCategoria {
  const CrearCategoria(this._repo);
  final CategoriasRepository _repo;

  Future<CategoriaServicio> call(
    NuevaCategoria categoria, {
    Iterable<CategoriaServicio> existentes = const [],
  }) {
    if (categoria.duplicadaEn(existentes) != null) {
      throw const CategoriaFailure(CategoriaErrorTipo.nombreDuplicado);
    }
    return _repo.crear(categoria);
  }
}

/// Oculta o vuelve a mostrar una categoría en el catálogo público del tenant
/// sin afectar los servicios que ya están en curso (US-03.1.2).
class CambiarEstadoCategoria {
  const CambiarEstadoCategoria(this._repo);
  final CategoriasRepository _repo;

  Future<CategoriaServicio> call({
    required String categoriaId,
    required bool activa,
  }) {
    final id = categoriaId.trim();
    if (id.isEmpty) {
      throw const CategoriaFailure(CategoriaErrorTipo.noEncontrada);
    }
    return _repo.cambiarEstado(categoriaId: id, activa: activa);
  }
}
