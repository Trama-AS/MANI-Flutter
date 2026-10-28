import '../../domain/entities/zona.dart';

/// Mapea las filas de zona que arma `GatewayCoberturaDataSource` a partir de
/// `GET /catalog/zones` y `GET /profiles/me/coverage`.
class ZonaModel extends Zona {
  const ZonaModel({
    required super.id,
    required super.nombre,
    required super.nivel,
    super.padreId,
    super.ancestros,
    super.tieneHijas,
    super.activa,
  });

  factory ZonaModel.fromJson(Map<String, dynamic> json) => ZonaModel(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    nivel: NivelZona.desde(json['nivel'] as String? ?? ''),
    padreId: json['zona_padre_id'] as String?,
    ancestros: (json['ancestros'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(growable: false),
    tieneHijas: json['tiene_hijas'] as bool? ?? false,
    activa: (json['estado'] as String? ?? 'activa') == 'activa',
  );
}
