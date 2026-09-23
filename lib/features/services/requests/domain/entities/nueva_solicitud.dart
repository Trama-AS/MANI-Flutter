import 'package:equatable/equatable.dart';

import '../failures/solicitud_failure.dart';
import 'catalogo_solicitud.dart';
import 'foto_adjunta.dart';

/// Dónde se hará el servicio: una dirección ya registrada o una nueva.
sealed class UbicacionSolicitud extends Equatable {
  const UbicacionSolicitud();
}

final class SitioExistente extends UbicacionSolicitud {
  const SitioExistente(this.sitio);

  final SitioCliente sitio;

  @override
  List<Object?> get props => [sitio];
}

final class NuevaDireccion extends UbicacionSolicitud {
  const NuevaDireccion._(this.direccion, this.zona);

  static const int minimo = 5;
  static const int maximo = 200;

  /// Lanza [SolicitudFailure] si la dirección o la zona no son válidas.
  factory NuevaDireccion.crear({
    required String direccion,
    required ZonaOpcion? zona,
  }) {
    final limpia = direccion.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpia.length < minimo || limpia.length > maximo) {
      throw const SolicitudFailure(SolicitudErrorTipo.ubicacionInvalida);
    }
    if (zona == null) {
      throw const SolicitudFailure(SolicitudErrorTipo.zonaInvalida);
    }
    return NuevaDireccion._(limpia, zona);
  }

  final String direccion;
  final ZonaOpcion zona;

  @override
  List<Object?> get props => [direccion, zona];
}

/// Solicitud lista para publicar. Solo se construye con [NuevaSolicitud.crear],
/// que aplica las mismas reglas que la RPC `crear_solicitud` para fallar
/// rápido y sin red.
class NuevaSolicitud extends Equatable {
  const NuevaSolicitud._({
    required this.categoria,
    required this.descripcion,
    required this.fotos,
    required this.ubicacion,
    required this.claveIdempotencia,
  });

  static const int descripcionMinima = 20;
  static const int descripcionMaxima = 1000;
  static const int maxFotos = 5;

  factory NuevaSolicitud.crear({
    required CategoriaDisponible? categoria,
    required String descripcion,
    required List<FotoAdjunta> fotos,
    required UbicacionSolicitud ubicacion,
    required String claveIdempotencia,
  }) {
    if (categoria == null) {
      throw const SolicitudFailure(SolicitudErrorTipo.categoriaInvalida);
    }
    if (!descripcionValida(descripcion)) {
      throw const SolicitudFailure(SolicitudErrorTipo.descripcionInvalida);
    }
    if (fotos.length > maxFotos) {
      throw const SolicitudFailure(SolicitudErrorTipo.demasiadasFotos);
    }
    return NuevaSolicitud._(
      categoria: categoria,
      descripcion: descripcion.trim(),
      fotos: List.unmodifiable(fotos),
      ubicacion: ubicacion,
      claveIdempotencia: claveIdempotencia,
    );
  }

  static bool descripcionValida(String texto) {
    final n = texto.trim().length;
    return n >= descripcionMinima && n <= descripcionMaxima;
  }

  final CategoriaDisponible categoria;
  final String descripcion;
  final List<FotoAdjunta> fotos;
  final UbicacionSolicitud ubicacion;

  /// Igual en todos los reintentos del mismo envío: evita duplicados.
  final String claveIdempotencia;

  @override
  List<Object?> get props => [
    categoria,
    descripcion,
    fotos,
    ubicacion,
    claveIdempotencia,
  ];
}
