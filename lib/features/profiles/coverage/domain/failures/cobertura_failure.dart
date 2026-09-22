/// Errores de negocio de US-02.1.4. Los códigos `MANI-COB-*` los emite la RPC
/// `declarar_cobertura` (ver migración 20260922120000).
enum CoberturaErrorTipo {
  sinSesion, // MANI-COB-401
  noEsAliado, // MANI-COB-403
  aliadoRechazado, // MANI-COB-403R
  seleccionVacia, // MANI-COB-422V
  limiteExcedido, // MANI-COB-422L
  zonaInvalida, // MANI-COB-422Z
  sinConexion,
  desconocido,
}

class CoberturaFailure implements Exception {
  const CoberturaFailure(this.tipo, [this.detalle]);

  final CoberturaErrorTipo tipo;
  final String? detalle;

  /// Máximo de zonas por declaración — debe coincidir con la RPC.
  static const int maxZonas = 200;

  String get mensajeUsuario => switch (tipo) {
    CoberturaErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para guardar tu cobertura.',
    CoberturaErrorTipo.noEsAliado =>
      'Solo los aliados pueden declarar zonas de cobertura.',
    CoberturaErrorTipo.aliadoRechazado =>
      'Tu registro como aliado fue rechazado. Contacta al administrador.',
    CoberturaErrorTipo.seleccionVacia =>
      'Selecciona al menos una zona. Si no quieres recibir solicitudes por '
          'un tiempo, usa "No disponible" en tu perfil.',
    CoberturaErrorTipo.limiteExcedido =>
      'Puedes declarar máximo $maxZonas zonas. Selecciona la localidad '
          'completa en lugar de barrio por barrio.',
    CoberturaErrorTipo.zonaInvalida =>
      'Una o más zonas ya no están disponibles. Actualiza la lista e '
          'inténtalo de nuevo.',
    CoberturaErrorTipo.sinConexion =>
      'Sin conexión. Tus cambios siguen aquí; inténtalo de nuevo.',
    CoberturaErrorTipo.desconocido =>
      'No pudimos guardar tu cobertura. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'CoberturaFailure(${tipo.name}, $detalle)';
}
