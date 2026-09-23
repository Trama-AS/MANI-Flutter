/// Por qué un aliado rechaza una solicitud. Es opcional; ayuda al tenant a
/// detectar zonas o categorías sin cobertura suficiente.
/// Los códigos coinciden con `ck_solicitud_rechazo_motivo` (migración 005).
enum MotivoRechazo {
  sinDisponibilidad('SIN_DISPONIBILIDAD', 'No tengo disponibilidad'),
  fueraDeZona('FUERA_DE_ZONA', 'Me queda lejos'),
  noEsMiEspecialidad('NO_ES_MI_ESPECIALIDAD', 'No es mi especialidad'),
  otro('OTRO', 'Otro motivo');

  const MotivoRechazo(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;
}
