/// Errores de negocio de US-02.1.3. Los códigos `MANI-VER-*` los emiten las
/// RPC de la migración `002_verificacion_aliados.sql`.
enum VerificacionErrorTipo {
  sinSesion, // MANI-VER-401
  noAutorizado, // MANI-VER-403
  noEncontrado, // MANI-VER-404
  yaResuelta, // MANI-VER-409
  decisionInvalida, // MANI-VER-422D
  motivoInvalido, // MANI-VER-422M
  sinDocumentos, // MANI-VER-422K
  documentoNoDisponible,
  sinConexion,
  desconocido,
}

class VerificacionFailure implements Exception {
  const VerificacionFailure(this.tipo, [this.detalle]);

  final VerificacionErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    VerificacionErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para continuar.',
    VerificacionErrorTipo.noAutorizado =>
      'Solo el administrador del tenant puede verificar aliados.',
    VerificacionErrorTipo.noEncontrado =>
      'Este aliado ya no existe o no pertenece a tu empresa.',
    VerificacionErrorTipo.yaResuelta =>
      'Otro administrador ya resolvió esta solicitud. Actualizamos la bandeja.',
    VerificacionErrorTipo.decisionInvalida =>
      'La decisión enviada no es válida. Inténtalo de nuevo.',
    VerificacionErrorTipo.motivoInvalido =>
      'Explica el motivo del rechazo (entre 10 y 500 caracteres) para que el aliado sepa qué corregir.',
    VerificacionErrorTipo.sinDocumentos =>
      'No puedes aprobar un aliado sin documentos. Recházalo indicando qué debe adjuntar.',
    VerificacionErrorTipo.documentoNoDisponible =>
      'No pudimos abrir el documento. Es posible que el archivo aún no se haya cargado.',
    VerificacionErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
    VerificacionErrorTipo.desconocido => 'Algo salió mal. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'VerificacionFailure(${tipo.name}, $detalle)';
}
