/// Errores de US-04.1.1. Los códigos `MANI-SOL-*` los emiten las RPC de la
/// migración `006_crear_solicitud.sql`; el resto se detecta en la app.
enum SolicitudErrorTipo {
  sinSesion, // MANI-SOL-401
  noEsCliente, // MANI-SOL-403C
  categoriaInvalida, // MANI-SOL-422C
  descripcionInvalida, // MANI-SOL-422D
  fotosInvalidas, // MANI-SOL-422F
  ubicacionInvalida, // MANI-SOL-422S
  zonaInvalida, // MANI-SOL-422Z
  demasiadasFotos,
  fotoFormatoInvalido,
  fotoMuyPesada,
  subidaFotosFallida,
  sinConexion,
  desconocido,
}

class SolicitudFailure implements Exception {
  const SolicitudFailure(this.tipo, [this.detalle]);

  final SolicitudErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    SolicitudErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para publicar tu solicitud.',
    SolicitudErrorTipo.noEsCliente =>
      'Solo los clientes pueden publicar solicitudes de servicio.',
    SolicitudErrorTipo.categoriaInvalida =>
      'Esa categoría ya no está disponible. Elige otra.',
    SolicitudErrorTipo.descripcionInvalida =>
      'Describe el problema con al menos 20 caracteres (máximo 1000).',
    SolicitudErrorTipo.fotosInvalidas ||
    SolicitudErrorTipo.subidaFotosFallida =>
      'No pudimos subir tus fotos. Inténtalo de nuevo.',
    SolicitudErrorTipo.ubicacionInvalida =>
      'Revisa la dirección: debe tener entre 5 y 200 caracteres.',
    SolicitudErrorTipo.zonaInvalida =>
      'Elige el barrio o la localidad de la dirección.',
    SolicitudErrorTipo.demasiadasFotos => 'Puedes adjuntar máximo 5 fotos.',
    SolicitudErrorTipo.fotoFormatoInvalido =>
      'Solo se aceptan fotos JPG, PNG o WEBP.',
    SolicitudErrorTipo.fotoMuyPesada => 'Cada foto puede pesar máximo 5 MB.',
    SolicitudErrorTipo.sinConexion =>
      'Sin conexión. Tu solicitud sigue aquí; inténtalo de nuevo.',
    SolicitudErrorTipo.desconocido =>
      'No pudimos publicar tu solicitud. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'SolicitudFailure(${tipo.name}, $detalle)';
}
