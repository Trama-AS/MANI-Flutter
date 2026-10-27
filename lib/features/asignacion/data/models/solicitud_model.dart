import '../../domain/entities/modalidad_servicio.dart';
import '../../domain/entities/regla_sitio.dart';
import '../../domain/entities/solicitud_entity.dart';

/// Mapea un elemento de la bandeja del aliado, `GET /api/v1/dispatch/offers/me`
/// (camelCase de Core, `core-internal.yaml` → `AllyOffer`).
class SolicitudModel extends SolicitudEntity {
  const SolicitudModel({
    required super.id,
    required super.estado,
    required super.categoria,
    required super.zona,
    required super.fechaCreacion,
    super.esMia,
    super.modalidad,
    super.zonaPadre,
    super.reglasSitio,
    super.descripcion,
    super.cantidadFotos,
    super.direccion,
    super.fechaAsignacion,
  });

  factory SolicitudModel.fromGateway(Map<String, dynamic> json) =>
      SolicitudModel(
        id: json['id'] as String,
        estado: EstadoSolicitud.desde(json['estado'] as String?),
        esMia: json['esMia'] as bool? ?? false,
        categoria: json['categoria'] as String? ?? 'Servicio',
        modalidad: ModalidadServicio.desde(json['flujoOperativo'] as String?),
        zona: json['zona'] as String? ?? '',
        zonaPadre: json['zonaPadre'] as String?,
        reglasSitio: ReglaSitio.desdeMapa(
          json['reglasSitio'] is Map
              ? Map<String, dynamic>.from(json['reglasSitio'] as Map)
              : null,
        ),
        descripcion: json['descripcion'] as String?,
        cantidadFotos: (json['fotos'] as num?)?.toInt() ?? 0,
        direccion: json['direccion'] as String?,
        fechaCreacion:
            _fecha(json['creadaEn']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        fechaAsignacion: _fecha(json['asignadaEn']),
      );
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;
