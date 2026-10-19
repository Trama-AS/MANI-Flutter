/// Errores de negocio de US-02.1.6. Los códigos `MANI-AUS-*` los emite Core
/// Node en `/profiles/me/unavailability` (contrato core.yaml del Gateway).
enum DisponibilidadErrorTipo {
  sinSesion, // 401 / MANI-AUS-401
  noEsAliado, // MANI-AUS-403
  noEncontrada, // MANI-AUS-404
  solapamiento, // MANI-AUS-409
  horarioInvalido, // MANI-AUS-422H
  datosInvalidos, // MANI-AUS-422V
  sinConexion,
  desconocido,
}

class DisponibilidadFailure implements Exception {
  const DisponibilidadFailure(this.tipo, [this.detalle]);

  final DisponibilidadErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    DisponibilidadErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para gestionar tu disponibilidad.',
    DisponibilidadErrorTipo.noEsAliado =>
      'Solo los aliados pueden gestionar su disponibilidad.',
    DisponibilidadErrorTipo.noEncontrada =>
      'Esa ausencia ya no existe. Actualizamos la lista.',
    DisponibilidadErrorTipo.solapamiento =>
      'Ese intervalo se cruza con otra ausencia que ya registraste.',
    DisponibilidadErrorTipo.horarioInvalido =>
      'Revisa las fechas: el fin debe ser posterior al inicio y estar en el futuro.',
    DisponibilidadErrorTipo.datosInvalidos =>
      'Revisa los datos del formulario e inténtalo de nuevo.',
    DisponibilidadErrorTipo.sinConexion =>
      'Sin conexión. Inténtalo de nuevo en un momento.',
    DisponibilidadErrorTipo.desconocido =>
      'No pudimos completar la operación. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'DisponibilidadFailure(${tipo.name}, $detalle)';
}
