/// Errores de negocio de US-03.1.1 y US-03.1.2. Los códigos `MANI-CAT-*` los
/// emite el Rules Service (`violations[].code`) y Core Node los devuelve a
/// través del API Gateway.
enum CategoriaErrorTipo {
  sinSesion, // MANI-CAT-401
  noAutorizado, // MANI-CAT-403
  noEncontrada, // MANI-CAT-404 / HTTP 404
  nombreDuplicado, // MANI-CAT-409
  nombreInvalido, // MANI-CAT-422N
  flujoInvalido, // MANI-CAT-422F
  sinConexion,
  desconocido,
}

class CategoriaFailure implements Exception {
  const CategoriaFailure(this.tipo, [this.detalle]);

  final CategoriaErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    CategoriaErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para continuar.',
    CategoriaErrorTipo.noAutorizado =>
      'Solo el administrador del tenant puede gestionar categorías.',
    CategoriaErrorTipo.noEncontrada =>
      'No encontramos esta categoría en tu catálogo.',
    CategoriaErrorTipo.nombreDuplicado =>
      'Ya tienes una categoría con ese nombre. Usa un nombre distinto.',
    CategoriaErrorTipo.nombreInvalido =>
      'El nombre debe tener entre 3 y 60 caracteres e incluir al menos una letra.',
    CategoriaErrorTipo.flujoInvalido =>
      'Elige cómo opera la categoría: cotización previa o tarifa estándar.',
    CategoriaErrorTipo.sinConexion =>
      'Sin conexión. Tus datos siguen aquí; inténtalo de nuevo.',
    CategoriaErrorTipo.desconocido =>
      'No pudimos guardar la categoría. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'CategoriaFailure(${tipo.name}, $detalle)';
}
