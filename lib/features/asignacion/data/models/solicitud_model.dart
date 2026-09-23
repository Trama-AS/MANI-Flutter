import '../../domain/entities/modalidad_servicio.dart';
import '../../domain/entities/regla_sitio.dart';
import '../../domain/entities/solicitud_entity.dart';

/// Mapea el JSON que devuelve `_sol_json` (migración 005).
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
    super.direccion,
    super.fechaAsignacion,
  });

  factory SolicitudModel.fromJson(Map<String, dynamic> json) => SolicitudModel(
    id: json['id'] as String,
    estado: EstadoSolicitud.desde(json['estado'] as String?),
    esMia: json['es_mia'] as bool? ?? false,
    categoria: json['categoria'] as String? ?? 'Servicio',
    modalidad: ModalidadServicio.desde(json['flujo_operativo'] as String?),
    zona: json['zona'] as String? ?? '',
    zonaPadre: json['zona_padre'] as String?,
    reglasSitio: ReglaSitio.desdeMapa(
      json['reglas_sitio'] is Map
          ? Map<String, dynamic>.from(json['reglas_sitio'] as Map)
          : null,
    ),
    direccion: json['direccion'] as String?,
    fechaCreacion:
        _fecha(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    fechaAsignacion: _fecha(json['asignada_at']),
  );
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;
