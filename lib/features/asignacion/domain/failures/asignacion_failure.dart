/// Errores de negocio de US-04.1.4. Los códigos `MANI-SOL-*` los emite Core al
/// registrar la asignación y los `MANI-DSP-*` Dispatch (decisión 6A); llegan
/// por el Gateway en el campo `code`.
enum AsignacionErrorTipo {
  sinSesion, // MANI-SOL-401
  noEsAliado, // MANI-SOL-403
  aliadoNoVerificado, // MANI-SOL-403V
  noElegible, // MANI-SOL-403E / 403O
  noEncontrada, // MANI-SOL-404
  yaNoDisponible, // MANI-SOL-409 / 409E (ya_no_disponible, DD-MANI §7.1)
  yaEsTuya, // MANI-DSP-409A
  yaRechazada, // MANI-DSP-409R
  motivoInvalido, // MANI-SOL-422M
  detalleInvalido, // MANI-SOL-422D
  servicioNoDisponible, // 5xx: Dispatch, Core o la base no responden
  sinConexion,
  desconocido,
}

class AsignacionFailure implements Exception {
  const AsignacionFailure(this.tipo, [this.detalle]);

  final AsignacionErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    AsignacionErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para continuar.',
    AsignacionErrorTipo.noEsAliado =>
      'Solo los aliados pueden aceptar solicitudes de servicio.',
    AsignacionErrorTipo.aliadoNoVerificado =>
      'Tu registro aún está en revisión. Podrás aceptar solicitudes cuando el administrador lo apruebe.',
    AsignacionErrorTipo.noElegible =>
      'Esta solicitud no corresponde a tus especialidades o zonas de cobertura.',
    AsignacionErrorTipo.noEncontrada => 'Esta solicitud ya no existe.',
    AsignacionErrorTipo.yaNoDisponible =>
      'Otro aliado tomó esta solicitud primero. Te mostramos las que siguen disponibles.',
    AsignacionErrorTipo.yaEsTuya =>
      'Esta solicitud ya es tuya. Búscala en "Mis trabajos".',
    AsignacionErrorTipo.yaRechazada =>
      'Ya habías descartado esta solicitud, así que no puedes aceptarla.',
    AsignacionErrorTipo.motivoInvalido =>
      'Elige un motivo para rechazar la solicitud.',
    AsignacionErrorTipo.detalleInvalido =>
      'Cuéntanos el motivo en 3 a 280 caracteres.',
    AsignacionErrorTipo.servicioNoDisponible =>
      'El servicio de asignación no responde en este momento. Inténtalo en unos minutos.',
    AsignacionErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
    AsignacionErrorTipo.desconocido => 'Algo salió mal. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'AsignacionFailure(${tipo.name}, $detalle)';
}
