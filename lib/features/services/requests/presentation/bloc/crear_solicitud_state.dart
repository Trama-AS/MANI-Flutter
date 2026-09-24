part of 'crear_solicitud_cubit.dart';

enum CargaFormulario { inicial, cargando, listo, error }

/// Pasos del asistente, en orden.
enum PasoSolicitud {
  categoria('Servicio'),
  detalle('Problema'),
  ubicacion('Ubicación'),
  revision('Revisar');

  const PasoSolicitud(this.etiqueta);

  final String etiqueta;
}

enum ModoUbicacion { sitioGuardado, nuevaDireccion }

/// Mensaje de un solo uso para SnackBar.
class AvisoSolicitud extends Equatable {
  const AvisoSolicitud(this.id, this.mensaje, {this.esError = false});

  final int id;
  final String mensaje;
  final bool esError;

  @override
  List<Object?> get props => [id, mensaje, esError];
}

const Object _sinCambio = Object();

class CrearSolicitudState extends Equatable {
  const CrearSolicitudState({
    required this.clave,
    this.carga = CargaFormulario.inicial,
    this.catalogo = const CatalogoSolicitud(),
    this.paso = PasoSolicitud.categoria,
    this.categoriaId,
    this.descripcion = '',
    this.fotos = const [],
    this.modo = ModoUbicacion.nuevaDireccion,
    this.sitioId,
    this.direccion = '',
    this.zona,
    this.zonasEncontradas = const [],
    this.buscandoZonas = false,
    this.publicando = false,
    this.publicada,
    this.error,
    this.errorEnvio,
    this.aviso,
  });

  /// Clave de idempotencia del envío actual (la misma en cada reintento).
  final String clave;
  final CargaFormulario carga;
  final CatalogoSolicitud catalogo;
  final PasoSolicitud paso;
  final String? categoriaId;
  final String descripcion;
  final List<FotoAdjunta> fotos;
  final ModoUbicacion modo;
  final String? sitioId;
  final String direccion;
  final ZonaOpcion? zona;
  final List<ZonaOpcion> zonasEncontradas;
  final bool buscandoZonas;
  final bool publicando;
  final SolicitudPublicada? publicada;

  /// Error al cargar el formulario.
  final SolicitudFailure? error;

  /// Error del último intento de publicación.
  final SolicitudFailure? errorEnvio;
  final AvisoSolicitud? aviso;

  CategoriaDisponible? get categoria {
    for (final c in catalogo.categorias) {
      if (c.id == categoriaId) {
        return c;
      }
    }
    return null;
  }

  SitioCliente? get sitio {
    for (final s in catalogo.sitios) {
      if (s.id == sitioId) {
        return s;
      }
    }
    return null;
  }

  bool get descripcionValida => NuevaSolicitud.descripcionValida(descripcion);

  bool get fotosCompletas => fotos.length >= NuevaSolicitud.maxFotos;

  bool get ubicacionValida => switch (modo) {
    ModoUbicacion.sitioGuardado => sitio != null,
    ModoUbicacion.nuevaDireccion =>
      zona != null &&
          direccion.trim().length >= NuevaDireccion.minimo &&
          direccion.trim().length <= NuevaDireccion.maximo,
  };

  bool completo(PasoSolicitud p) => switch (p) {
    PasoSolicitud.categoria => categoria != null,
    PasoSolicitud.detalle => descripcionValida,
    PasoSolicitud.ubicacion => ubicacionValida,
    PasoSolicitud.revision =>
      categoria != null && descripcionValida && ubicacionValida,
  };

  bool get puedeAvanzar => completo(paso) && !publicando;

  CrearSolicitudState copyWith({
    String? clave,
    CargaFormulario? carga,
    CatalogoSolicitud? catalogo,
    PasoSolicitud? paso,
    Object? categoriaId = _sinCambio,
    String? descripcion,
    List<FotoAdjunta>? fotos,
    ModoUbicacion? modo,
    Object? sitioId = _sinCambio,
    String? direccion,
    Object? zona = _sinCambio,
    List<ZonaOpcion>? zonasEncontradas,
    bool? buscandoZonas,
    bool? publicando,
    Object? publicada = _sinCambio,
    Object? error = _sinCambio,
    Object? errorEnvio = _sinCambio,
    Object? aviso = _sinCambio,
  }) => CrearSolicitudState(
    clave: clave ?? this.clave,
    carga: carga ?? this.carga,
    catalogo: catalogo ?? this.catalogo,
    paso: paso ?? this.paso,
    categoriaId: identical(categoriaId, _sinCambio)
        ? this.categoriaId
        : categoriaId as String?,
    descripcion: descripcion ?? this.descripcion,
    fotos: fotos ?? this.fotos,
    modo: modo ?? this.modo,
    sitioId: identical(sitioId, _sinCambio) ? this.sitioId : sitioId as String?,
    direccion: direccion ?? this.direccion,
    zona: identical(zona, _sinCambio) ? this.zona : zona as ZonaOpcion?,
    zonasEncontradas: zonasEncontradas ?? this.zonasEncontradas,
    buscandoZonas: buscandoZonas ?? this.buscandoZonas,
    publicando: publicando ?? this.publicando,
    publicada: identical(publicada, _sinCambio)
        ? this.publicada
        : publicada as SolicitudPublicada?,
    error: identical(error, _sinCambio)
        ? this.error
        : error as SolicitudFailure?,
    errorEnvio: identical(errorEnvio, _sinCambio)
        ? this.errorEnvio
        : errorEnvio as SolicitudFailure?,
    aviso: identical(aviso, _sinCambio) ? this.aviso : aviso as AvisoSolicitud?,
  );

  @override
  List<Object?> get props => [
    clave,
    carga,
    catalogo,
    paso,
    categoriaId,
    descripcion,
    fotos,
    modo,
    sitioId,
    direccion,
    zona,
    zonasEncontradas,
    buscandoZonas,
    publicando,
    publicada,
    error?.tipo,
    errorEnvio?.tipo,
    aviso,
  ];
}
