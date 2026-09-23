/// Errores de negocio de US-03.1.3. Los códigos `MANI-CAT-*` los emiten las
/// RPC de `database/migrations/004_aliado_categorias.sql`.
enum CategoriesErrorTipo {
  sinSesion, // MANI-CAT-401
  noEsAliado, // MANI-CAT-403
  seleccionVacia, // MANI-CAT-422V
  categoriaNoDisponible, // MANI-CAT-422C
  sinConexion,
  desconocido,
}

class CategoriesFailure implements Exception {
  const CategoriesFailure(this.tipo, [this.detalle]);

  final CategoriesErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    CategoriesErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para ver tus categorías.',
    CategoriesErrorTipo.noEsAliado =>
      'Solo los aliados pueden declarar las categorías que atienden.',
    CategoriesErrorTipo.seleccionVacia =>
      'Selecciona al menos una categoría para continuar.',
    CategoriesErrorTipo.categoriaNoDisponible =>
      'Una o más categorías ya no están disponibles. Actualiza la lista e '
          'inténtalo de nuevo.',
    CategoriesErrorTipo.sinConexion =>
      'Sin conexión. Tu selección sigue aquí; inténtalo de nuevo.',
    CategoriesErrorTipo.desconocido =>
      'No pudimos completar la operación. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'CategoriesFailure(${tipo.name}, $detalle)';
}
