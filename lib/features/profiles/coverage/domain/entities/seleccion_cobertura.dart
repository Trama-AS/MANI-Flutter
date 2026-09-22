import 'zona.dart';

/// Conjunto de zonas que el aliado está declarando. Inmutable.
///
/// Regla de negocio (ADR-0011, jerarquía): declarar una zona cubre todas sus
/// descendientes. Por eso la selección se mantiene siempre **normalizada**:
/// nunca contiene a la vez una zona y un ancestro suyo. El servidor aplica la
/// misma normalización (`declarar_cobertura`), esto solo la hace visible en UI.
class SeleccionCobertura {
  const SeleccionCobertura._(this._zonas);

  factory SeleccionCobertura.vacia() =>
      const SeleccionCobertura._(<String, Zona>{});

  factory SeleccionCobertura.desde(Iterable<Zona> zonas) {
    var s = SeleccionCobertura.vacia();
    for (final z in zonas) {
      s = s.agregar(z);
    }
    return s;
  }

  final Map<String, Zona> _zonas;

  Iterable<Zona> get zonas => _zonas.values;
  Set<String> get ids => _zonas.keys.toSet();
  int get cantidad => _zonas.length;
  bool get estaVacia => _zonas.isEmpty;

  /// Zonas declaradas que el catálogo desactivó después: ya no hacen match.
  List<Zona> get desactivadas =>
      _zonas.values.where((z) => !z.activa).toList(growable: false);

  bool estaSeleccionadaDirectamente(Zona z) => _zonas.containsKey(z.id);

  /// La zona superior seleccionada que ya cubre a [z], si existe.
  Zona? ancestroSeleccionado(Zona z) {
    for (final id in z.ancestros) {
      final a = _zonas[id];
      if (a != null) return a;
    }
    return null;
  }

  bool estaCubiertaPorAncestro(Zona z) => ancestroSeleccionado(z) != null;

  bool cubre(Zona z) =>
      estaSeleccionadaDirectamente(z) || estaCubiertaPorAncestro(z);

  /// Seleccionadas que quedarían absorbidas si se agrega [z].
  int cantidadAbsorbidaPor(Zona z) =>
      _zonas.values.where((s) => s.esDescendienteDe(z.id)).length;

  /// Tiene al menos una descendiente seleccionada (para el checkbox parcial).
  bool tieneDescendienteSeleccionada(Zona z) =>
      _zonas.values.any((s) => s.esDescendienteDe(z.id));

  SeleccionCobertura agregar(Zona z) {
    if (cubre(z)) return this;
    final m = Map<String, Zona>.of(_zonas)
      ..removeWhere((_, s) => s.esDescendienteDe(z.id))
      ..[z.id] = z;
    return SeleccionCobertura._(Map.unmodifiable(m));
  }

  /// Solo quita zonas seleccionadas directamente; una zona cubierta por su
  /// ancestro se libera quitando el ancestro.
  SeleccionCobertura quitar(Zona z) {
    if (!estaSeleccionadaDirectamente(z)) return this;
    final m = Map<String, Zona>.of(_zonas)..remove(z.id);
    return SeleccionCobertura._(Map.unmodifiable(m));
  }

  SeleccionCobertura alternar(Zona z) =>
      estaSeleccionadaDirectamente(z) ? quitar(z) : agregar(z);

  /// Quita las zonas desactivadas (acción "Limpiar zonas no disponibles").
  SeleccionCobertura sinDesactivadas() {
    final m = Map<String, Zona>.of(_zonas)..removeWhere((_, z) => !z.activa);
    return SeleccionCobertura._(Map.unmodifiable(m));
  }

  /// Conserva solo las zonas cuyo id confirmó el servidor.
  SeleccionCobertura soloIds(Set<String> confirmados) {
    final m = Map<String, Zona>.of(_zonas)
      ..removeWhere((id, _) => !confirmados.contains(id));
    return SeleccionCobertura._(Map.unmodifiable(m));
  }

  bool mismoContenidoQue(SeleccionCobertura otra) {
    final a = ids;
    final b = otra.ids;
    return a.length == b.length && a.containsAll(b);
  }
}
