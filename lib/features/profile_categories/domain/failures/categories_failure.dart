/// Errores de negocio de US-03.1.3. Los códigos `MANI-CAT-*` los emite Core
/// Node en `/profiles/me/categories` (SCRUM-1380).
enum CategoriesErrorTipo {
  sinSesion, // MANI-CAT-401
  // MANI-CAT-403. Core lo emite en dos casos: quien pide no es un aliado de
  // este tenant, o es un aliado cuya verificación todavía no está aprobada
  // (C2 de SCRUM-1392). Comparten código y status, así que el mensaje cubre
  // los dos sin afirmar de más.
  noEsAliado,
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
      'Solo los aliados con la verificación aprobada pueden declarar las '
          'categorías que atienden.',
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
