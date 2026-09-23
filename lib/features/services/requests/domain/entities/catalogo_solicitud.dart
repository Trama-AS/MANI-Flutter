import 'package:equatable/equatable.dart';

/// Cómo se cobra el servicio según el flujo operativo de su categoría
/// (US-03.1.1). Le anticipa al cliente si recibirá cotizaciones.
/// Modelo propio de este contexto: solo comparte los códigos de BD.
enum ModalidadCobro {
  cotizacionPrevia('COTIZACION_PREVIA'),
  tarifaEstandar('TARIFA_ESTANDAR'),
  desconocida('');

  const ModalidadCobro(this.codigo);

  final String codigo;

  static ModalidadCobro desde(String? valor) {
    final v = valor?.trim().toUpperCase();
    for (final m in values) {
      if (m != desconocida && m.codigo == v) {
        return m;
      }
    }
    return desconocida;
  }
}

/// Categoría activa del tenant que el cliente puede solicitar.
class CategoriaDisponible extends Equatable {
  const CategoriaDisponible({
    required this.id,
    required this.nombre,
    this.modalidad = ModalidadCobro.desconocida,
  });

  final String id;
  final String nombre;
  final ModalidadCobro modalidad;

  @override
  List<Object?> get props => [id, nombre, modalidad];
}

/// Dirección ya registrada por el cliente.
class SitioCliente extends Equatable {
  const SitioCliente({
    required this.id,
    required this.direccion,
    required this.zona,
    this.zonaPadre,
  });

  final String id;
  final String direccion;
  final String zona;
  final String? zonaPadre;

  /// "Roma Norte · Cuauhtémoc".
  String get ubicacion => [
    zona,
    if (zonaPadre != null && zonaPadre!.isNotEmpty) zonaPadre!,
  ].join(' · ');

  @override
  List<Object?> get props => [id, direccion, zona, zonaPadre];
}

/// Barrio o localidad del catálogo global de zonas (ADR-0011).
class ZonaOpcion extends Equatable {
  const ZonaOpcion({required this.id, required this.nombre, this.zonaPadre});

  final String id;
  final String nombre;
  final String? zonaPadre;

  String get etiqueta => [
    nombre,
    if (zonaPadre != null && zonaPadre!.isNotEmpty) zonaPadre!,
  ].join(' · ');

  @override
  List<Object?> get props => [id, nombre, zonaPadre];
}

/// Lo que el cliente necesita para llenar el formulario.
class CatalogoSolicitud extends Equatable {
  const CatalogoSolicitud({this.categorias = const [], this.sitios = const []});

  final List<CategoriaDisponible> categorias;
  final List<SitioCliente> sitios;

  @override
  List<Object?> get props => [categorias, sitios];
}
