import '../../domain/entities/documento_kyc.dart';
import '../../domain/entities/solicitud_aliado.dart';

/// Mapea la vista de verificación que devuelve Core
/// (`hydrateAllyVerificationView`), con la misma forma que `_ver_aliado_json`.
class DocumentoKycModel extends DocumentoKyc {
  const DocumentoKycModel({
    required super.id,
    required super.tipo,
    required super.rutaStorage,
    required super.estado,
    super.fechaCarga,
    super.aliadoId,
  });

  factory DocumentoKycModel.fromJson(
    Map<String, dynamic> json, {
    String? aliadoId,
  }) => DocumentoKycModel(
    id: json['id'] as String,
    tipo: TipoDocumentoKyc.desde(json['tipo_documento'] as String? ?? ''),
    rutaStorage: json['ruta_storage'] as String? ?? '',
    estado: EstadoDocumentoKyc.desde(json['estado'] as String? ?? ''),
    fechaCarga: _fecha(json['fecha_carga']),
    aliadoId: aliadoId,
  );
}

class SolicitudAliadoModel extends SolicitudAliado {
  const SolicitudAliadoModel({
    required super.id,
    required super.nombre,
    required super.email,
    required super.tipo,
    required super.estado,
    required super.fechaRegistro,
    super.categorias,
    super.documentos,
    super.motivoRechazo,
    super.fechaVerificacion,
  });

  factory SolicitudAliadoModel.fromJson(Map<String, dynamic> json) =>
      SolicitudAliadoModel(
        id: json['id'] as String,
        nombre: json['nombre'] as String? ?? '',
        email: json['email'] as String? ?? '',
        tipo: TipoAliado.desde(json['tipo'] as String? ?? ''),
        estado: EstadoVerificacion.desde(
          json['estado_verificacion'] as String? ?? '',
        ),
        fechaRegistro:
            _fecha(json['fecha_registro']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        categorias: (json['categorias'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        documentos: (json['documentos'] as List<dynamic>? ?? const [])
            .map(
              (e) => DocumentoKycModel.fromJson(
                Map<String, dynamic>.from(e as Map),
                aliadoId: json['id'] as String,
              ),
            )
            .toList(growable: false),
        motivoRechazo: json['motivo_rechazo'] as String?,
        fechaVerificacion: _fecha(json['fecha_verificacion']),
      );
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;
