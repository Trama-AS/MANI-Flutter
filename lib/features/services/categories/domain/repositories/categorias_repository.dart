import '../entities/categoria_servicio.dart';
import '../entities/nueva_categoria.dart';

/// Puerto del dominio. La implementación vive en `data/` (Supabase).
/// Todas las operaciones lanzan `CategoriaFailure` ante errores.
///
/// Ningún método recibe `tenantId`: el servidor lo deriva de la sesión del
/// administrador (anti tenant-spoofing).
abstract interface class CategoriasRepository {
  /// Todas las categorías del tenant, activas e inactivas.
  Future<List<CategoriaServicio>> listar();

  /// Crea la categoría y la devuelve tal como quedó guardada.
  Future<CategoriaServicio> crear(NuevaCategoria categoria);
}
