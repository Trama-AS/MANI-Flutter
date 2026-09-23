import '../../domain/entities/catalogo_solicitud.dart';
import '../../domain/entities/solicitud_publicada.dart';

/// Mapeos del JSON de las RPC de la migración 006.
class CategoriaDisponibleModel extends CategoriaDisponible {
  const CategoriaDisponibleModel({
    required super.id,
    required super.nombre,
    super.modalidad,
  });

  factory CategoriaDisponibleModel.fromJson(Map<String, dynamic> json) =>
      CategoriaDisponibleModel(
        id: json['id'] as String,
        nombre: json['nombre'] as String? ?? '',
        modalidad: ModalidadCobro.desde(json['flujo_operativo'] as String?),
      );
}

class SitioClienteModel extends SitioCliente {
  const SitioClienteModel({
    required super.id,
    required super.direccion,
    required super.zona,
    super.zonaPadre,
  });

  factory SitioClienteModel.fromJson(Map<String, dynamic> json) =>
      SitioClienteModel(
        id: json['id'] as String,
        direccion: json['direccion'] as String? ?? '',
        zona: json['zona'] as String? ?? '',
        zonaPadre: json['zona_padre'] as String?,
      );
}

class ZonaOpcionModel extends ZonaOpcion {
  const ZonaOpcionModel({
    required super.id,
    required super.nombre,
    super.zonaPadre,
  });

  factory ZonaOpcionModel.fromJson(Map<String, dynamic> json) =>
      ZonaOpcionModel(
        id: json['id'] as String,
        nombre: json['nombre'] as String? ?? '',
        zonaPadre: json['zona_padre'] as String?,
      );
}

class SolicitudPublicadaModel extends SolicitudPublicada {
  const SolicitudPublicadaModel({
    required super.id,
    required super.categoria,
    required super.descripcion,
    required super.direccion,
    required super.zona,
    required super.fechaCreacion,
    super.zonaPadre,
    super.modalidad,
    super.cantidadFotos,
  });

  factory SolicitudPublicadaModel.fromJson(Map<String, dynamic> json) =>
      SolicitudPublicadaModel(
        id: json['id'] as String,
        categoria: json['categoria'] as String? ?? '',
        modalidad: ModalidadCobro.desde(json['flujo_operativo'] as String?),
        descripcion: json['descripcion'] as String? ?? '',
        direccion: json['direccion'] as String? ?? '',
        zona: json['zona'] as String? ?? '',
        zonaPadre: json['zona_padre'] as String?,
        cantidadFotos: (json['fotos'] as num?)?.toInt() ?? 0,
        fechaCreacion:
            (json['created_at'] is String
                ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
                : null) ??
            DateTime.now(),
      );
}
