import 'package:equatable/equatable.dart';

import '../failures/categoria_failure.dart';
import 'categoria_servicio.dart';
import 'flujo_operativo.dart';

/// Datos validados para crear una categoría. Solo se construye con
/// [NuevaCategoria.crear], que aplica las mismas reglas que la RPC
/// `crear_categoria_servicio` para fallar rápido y sin red.
class NuevaCategoria extends Equatable {
  const NuevaCategoria._(this.nombre, this.flujo, this.activa);

  static const int nombreMinimo = 3;
  static const int nombreMaximo = 60;
  static final RegExp _tieneLetra = RegExp(r'\p{L}', unicode: true);

  /// Lanza [CategoriaFailure] si el nombre o el flujo no son válidos.
  factory NuevaCategoria.crear({
    required String nombre,
    required FlujoOperativo? flujo,
    bool activa = true,
  }) {
    final limpio = normalizarNombre(nombre);
    if (validarNombre(limpio) != null) {
      throw const CategoriaFailure(CategoriaErrorTipo.nombreInvalido);
    }
    if (flujo == null) {
      throw const CategoriaFailure(CategoriaErrorTipo.flujoInvalido);
    }
    return NuevaCategoria._(limpio, flujo, activa);
  }

  final String nombre;
  final FlujoOperativo flujo;

  /// `true` publica la categoría de inmediato en el catálogo de clientes.
  final bool activa;

  /// Motivo por el que [nombre] no es válido, o `null` si lo es.
  /// Se expone para validar en vivo mientras el administrador escribe.
  static CategoriaErrorTipo? validarNombre(String nombre) {
    final limpio = normalizarNombre(nombre);
    if (limpio.length < nombreMinimo ||
        limpio.length > nombreMaximo ||
        !_tieneLetra.hasMatch(limpio)) {
      return CategoriaErrorTipo.nombreInvalido;
    }
    return null;
  }

  /// La categoría de [existentes] que ya usa [nombre] (sin distinguir
  /// mayúsculas ni espacios), o `null`. Mismo criterio que el índice único.
  static CategoriaServicio? buscarDuplicada(
    String nombre,
    Iterable<CategoriaServicio> existentes,
  ) {
    final clave = normalizarClaveNombre(nombre);
    for (final c in existentes) {
      if (c.claveNombre == clave) {
        return c;
      }
    }
    return null;
  }

  /// La categoría existente con el mismo nombre, si la hay.
  CategoriaServicio? duplicadaEn(Iterable<CategoriaServicio> existentes) =>
      buscarDuplicada(nombre, existentes);

  @override
  List<Object?> get props => [nombre, flujo, activa];
}
