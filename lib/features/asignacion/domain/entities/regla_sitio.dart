import 'package:equatable/equatable.dart';

/// Regla del sitio del cliente (ej. `mascotas: false`, `horario: "8-17"`),
/// tal como la guarda `sitio.reglas` (JSONB). QS-06: el aliado debe verlas
/// todas antes de aceptar.
class ReglaSitio extends Equatable {
  const ReglaSitio(this.clave, this.valor);

  final String clave;

  /// `bool`, `num` o `String`, según la regla.
  final Object? valor;

  /// Convierte el JSON de `sitio.reglas` en reglas ordenadas por clave.
  static List<ReglaSitio> desdeMapa(Map<String, dynamic>? mapa) {
    if (mapa == null) {
      return const [];
    }
    final claves = mapa.keys.toList()..sort();
    return [for (final k in claves) ReglaSitio(k, mapa[k])];
  }

  @override
  List<Object?> get props => [clave, valor];
}
