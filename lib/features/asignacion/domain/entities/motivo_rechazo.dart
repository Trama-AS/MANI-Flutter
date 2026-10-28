/// Por qué un aliado rechaza una solicitud. Es obligatorio (decisión del PO,
/// SCRUM-1617): así los informes de rechazo muestran el motivo real y el
/// servidor nunca inventa uno. Las etiquetas son las que aprobó el PO.
/// Los códigos coinciden con `ck_solicitud_rechazo_motivo` (migración 005).
enum MotivoRechazo {
  sinDisponibilidad('SIN_DISPONIBILIDAD', 'No estoy disponible'),
  fueraDeZona('FUERA_DE_ZONA', 'Fuera de mi zona'),
  noEsMiEspecialidad('NO_ES_MI_ESPECIALIDAD', 'No hago este tipo de trabajo'),
  otro('OTRO', 'Otro');

  const MotivoRechazo(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

  /// «Otro» lleva texto libre; los demás no (migración 0025 de Core).
  bool get requiereDetalle => this == MotivoRechazo.otro;

  static const detalleMinimo = 3;
  static const detalleMaximo = 280;

  /// Si [detalle] cumple el largo que exige Dispatch, sin espacios extremos.
  /// Se cuentan caracteres (runes), igual que `char_length` en la base.
  static bool detalleValido(String detalle) {
    final largo = detalle.trim().runes.length;
    return largo >= detalleMinimo && largo <= detalleMaximo;
  }
}
