import '../../domain/entities/ausencia.dart';

/// Traducción entre el JSON de Core (`AllyAbsence` en core.yaml) y el dominio.
abstract final class AusenciaModel {
  static Ausencia fromJson(Map<String, dynamic> json) => Ausencia(
    id: json['id'] as String,
    inicio: DateTime.parse(json['startsAt'] as String).toLocal(),
    fin: DateTime.parse(json['endsAt'] as String).toLocal(),
    motivo: MotivoAusencia.desdeCodigo(json['reason'] as String?),
    nota: json['note'] as String?,
    activa: json['active'] as bool? ?? false,
  );

  /// Las fechas viajan en UTC con `Z`: Core exige zona horaria explícita.
  static Map<String, dynamic> toJson(BorradorAusencia borrador) {
    final nota = borrador.nota?.trim();
    return {
      'startsAt': borrador.inicio.toUtc().toIso8601String(),
      'endsAt': borrador.fin.toUtc().toIso8601String(),
      'reason': borrador.motivo.codigo,
      'note': (nota == null || nota.isEmpty) ? null : nota,
    };
  }
}
