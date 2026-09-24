import '../entities/zona.dart';

/// Puerto del dominio. La implementación vive en `data/` (Supabase).
/// Todas las operaciones lanzan `CoberturaFailure` ante errores.
abstract interface class CoberturaRepository {
  /// Hijas activas de [padreId]; `null` devuelve las ciudades.
  Future<List<Zona>> listarZonas({String? padreId});

  /// Búsqueda por nombre dentro de una ciudad (mínimo 2 caracteres).
  Future<List<Zona>> buscarZonas({
    required String ciudadId,
    required String texto,
  });

  /// Zonas que el aliado autenticado tiene declaradas hoy.
  Future<List<Zona>> obtenerMiCobertura();

  /// Reemplaza el set completo de zonas del aliado autenticado.
  /// Devuelve los ids que quedaron guardados (ya normalizados por el servidor).
  Future<Set<String>> declararCobertura(Set<String> zonaIds);
}
