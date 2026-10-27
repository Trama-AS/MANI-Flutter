import 'package:equatable/equatable.dart';

/// Tipo de aliado (HU-M05-05 / SCRUM-1400), con el valor que espera Dispatch
/// en `?tipo=` y el texto del chip.
enum TipoAliado {
  personaNatural('PERSONA_NATURAL', 'Persona natural'),
  personaJuridica('PERSONA_JURIDICA', 'Empresa'),
  empleadoDirecto('EMPLEADO_DIRECTO', 'Empleado directo');

  const TipoAliado(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static TipoAliado? desde(Object? valor) {
    if (valor is! String) return null;
    final v = valor.trim().toUpperCase();
    for (final t in values) {
      if (t.valor == v) return t;
    }
    return null;
  }
}

/// Aliado elegible para una solicitud. [posicion], [puntaje] y [razones]
/// solo llegan cuando Rules ordenó la lista (borrador de `dispatch.yaml`
/// 0.2.0, SCRUM-1401 / SCRUM-1462).
class AliadoElegible extends Equatable {
  const AliadoElegible({
    required this.id,
    required this.nombre,
    required this.tipoCrudo,
    this.posicion,
    this.puntaje,
    this.razones = const [],
  });

  factory AliadoElegible.fromJson(Map<String, dynamic> json) {
    final razones = json['razones'];
    return AliadoElegible(
      id: json['allyId'] as String,
      nombre: (json['nombreRazonSocial'] as String?) ?? '',
      tipoCrudo: (json['tipo'] as String?) ?? '',
      posicion: (json['posicion'] as num?)?.toInt(),
      puntaje: (json['puntaje'] as num?)?.toDouble(),
      razones: razones is List
          ? razones.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  final String id;
  final String nombre;
  final String tipoCrudo;
  final int? posicion;
  final double? puntaje;
  final List<String> razones;

  TipoAliado? get tipo => TipoAliado.desde(tipoCrudo);

  /// Texto del tipo; si la app no lo conoce, el valor que envió Dispatch.
  String get etiquetaTipo => tipo?.etiqueta ?? tipoCrudo;

  @override
  List<Object?> get props => [
    id,
    nombre,
    tipoCrudo,
    posicion,
    puntaje,
    razones,
  ];
}

/// Lista de elegibles tal como la entrega Dispatch. [aliados] conserva el
/// orden del backend: la app no reordena ni recalcula (SCRUM-1401).
class ListaElegibles extends Equatable {
  const ListaElegibles({
    required this.aliados,
    required this.total,
    this.ordenAplicado = false,
    this.criterio,
    this.motivoSinOrden,
  });

  factory ListaElegibles.fromJson(Map<String, dynamic> json) {
    final lista = json['matchedAllies'];
    // Un 200 sin la lista es una respuesta mal formada, no «sin aliados».
    if (lista is! List) {
      throw const ElegiblesFailure(
        ElegiblesErrorTipo.desconocido,
        'Respuesta de Dispatch sin "matchedAllies"',
      );
    }
    final aliados = lista
        .whereType<Map>()
        .map((e) => AliadoElegible.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final ranking = json['ranking'];
    final estado = ranking is Map ? ranking['estado'] : null;
    return ListaElegibles(
      aliados: aliados,
      total: (json['totalCount'] as num?)?.toInt() ?? aliados.length,
      // Sin `ranking` (Dispatch aún no lo envía) se trata como NO_DISPONIBLE.
      ordenAplicado: estado == 'APLICADO',
      criterio: ranking is Map ? ranking['criterio'] as String? : null,
      motivoSinOrden: ranking is Map ? ranking['motivo'] as String? : null,
    );
  }

  final List<AliadoElegible> aliados;
  final int total;
  final bool ordenAplicado;
  final String? criterio;
  final String? motivoSinOrden;

  @override
  List<Object?> get props => [
    aliados,
    total,
    ordenAplicado,
    criterio,
    motivoSinOrden,
  ];
}

/// Errores al consultar los elegibles. Los códigos `MANI-DSP-*` y
/// `MANI-SOL-*` los emite Dispatch (`dispatch.yaml` del Gateway).
enum ElegiblesErrorTipo {
  tipoInvalido, // 400 / MANI-DSP-400
  sinSesion, // 401
  noPermitido, // 403 / MANI-DSP-403
  noEncontrada, // 404 / MANI-DSP-404
  sinConexion,
  servicioNoDisponible, // 5xx, CORE_SERVICE_UNAVAILABLE
  desconocido,
}

class ElegiblesFailure implements Exception {
  const ElegiblesFailure(this.tipo, [this.detalle]);

  final ElegiblesErrorTipo tipo;
  final String? detalle;

  String get mensajeUsuario => switch (tipo) {
    ElegiblesErrorTipo.tipoInvalido =>
      'Ese tipo de aliado no es válido. Elige otro filtro.',
    ElegiblesErrorTipo.sinSesion =>
      'Tu sesión expiró. Vuelve a iniciar sesión para ver los aliados.',
    ElegiblesErrorTipo.noPermitido =>
      'Solo el cliente dueño de la solicitud puede ver sus aliados.',
    ElegiblesErrorTipo.noEncontrada =>
      'No encontramos esa solicitud entre las tuyas.',
    ElegiblesErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
    ElegiblesErrorTipo.servicioNoDisponible =>
      'No pudimos consultar los aliados porque el servicio no está disponible. Inténtalo en unos minutos.',
    ElegiblesErrorTipo.desconocido =>
      'No pudimos consultar los aliados. Inténtalo de nuevo.',
  };

  @override
  String toString() => 'ElegiblesFailure(${tipo.name}, $detalle)';
}
