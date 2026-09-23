/// Nivel de una zona dentro del catálogo jerárquico global (ADR-0011).
///
/// En BD `zona.nivel` es texto abierto (`ciudad | localidad/comuna | barrio`);
/// cualquier valor desconocido se trata como [otro] en vez de romper la UI.
enum NivelZona {
  ciudad,
  localidad,
  barrio,
  otro;

  static NivelZona desde(String valor) {
    switch (valor.trim().toLowerCase()) {
      case 'ciudad':
        return NivelZona.ciudad;
      case 'localidad':
      case 'comuna':
      case 'localidad/comuna':
        return NivelZona.localidad;
      case 'barrio':
        return NivelZona.barrio;
      default:
        return NivelZona.otro;
    }
  }

  String get etiqueta => switch (this) {
    NivelZona.ciudad => 'Ciudad',
    NivelZona.localidad => 'Localidad',
    NivelZona.barrio => 'Barrio',
    NivelZona.otro => 'Zona',
  };
}

/// Zona del catálogo (ciudad → localidad/comuna → barrio).
///
/// [ancestros] llega calculado por el servidor, del padre inmediato a la raíz.
/// Con eso el dominio sabe si una zona ya está cubierta por una zona superior
/// sin tener cargado el árbol completo.
class Zona {
  const Zona({
    required this.id,
    required this.nombre,
    required this.nivel,
    this.padreId,
    this.ancestros = const [],
    this.tieneHijas = false,
    this.activa = true,
  });

  final String id;
  final String nombre;
  final NivelZona nivel;
  final String? padreId;
  final List<String> ancestros;
  final bool tieneHijas;

  /// `false` cuando la zona fue desactivada en el catálogo después de que el
  /// aliado la declaró (ADR-0011 §5: nunca se borra, solo se desactiva).
  final bool activa;

  bool esDescendienteDe(String zonaId) => ancestros.contains(zonaId);

  @override
  bool operator ==(Object other) => other is Zona && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Zona($nombre, ${nivel.name})';
}
