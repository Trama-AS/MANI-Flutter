import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import 'package:mani/features/services/categories/domain/entities/categoria_servicio.dart';
import 'package:mani/features/services/categories/domain/repositories/categorias_repository.dart';

import '../data/tarifas_datasource.dart';
import '../domain/tarifa.dart';

class TarifarioState extends Equatable {
  const TarifarioState({
    this.cargando = false,
    this.guardando = false,
    this.categorias = const [],
    this.tarifas = const [],
    this.error,
    this.aviso,
    this.avisoEsError = false,
  });

  final bool cargando;
  final bool guardando;
  final List<CategoriaServicio> categorias;

  /// Versiones ACTIVA del tenant.
  final List<Tarifa> tarifas;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  List<Tarifa> tarifasDe(String categoriaId) =>
      tarifas.where((t) => t.categoriaId == categoriaId).toList();

  TarifarioState copiar({
    bool? cargando,
    bool? guardando,
    List<CategoriaServicio>? categorias,
    List<Tarifa>? tarifas,
    String? error,
    String? aviso,
    bool avisoEsError = false,
  }) => TarifarioState(
    cargando: cargando ?? this.cargando,
    guardando: guardando ?? this.guardando,
    categorias: categorias ?? this.categorias,
    tarifas: tarifas ?? this.tarifas,
    error: error,
    aviso: aviso,
    avisoEsError: avisoEsError,
  );

  @override
  List<Object?> get props => [
    cargando,
    guardando,
    categorias,
    tarifas,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Tarifario del tenant (HU-M10-01 / SCRUM-885): el administrador ve cada
/// categoría con su tarifa activa, la carga o la edita (versión nueva) y
/// consulta el historial. Tras guardar se recarga de Core, que es la fuente.
class TarifarioCubit extends Cubit<TarifarioState> {
  TarifarioCubit(this._fuente, this._categorias)
    : super(const TarifarioState());

  final FuenteTarifas _fuente;
  final CategoriasRepository _categorias;

  Future<void> cargar() async {
    emit(state.copiar(cargando: true));
    try {
      final resultados = await Future.wait([
        _categorias.listar(),
        _fuente.activas(),
      ]);
      emit(
        state.copiar(
          cargando: false,
          categorias: resultados[0] as List<CategoriaServicio>,
          tarifas: resultados[1] as List<Tarifa>,
        ),
      );
    } catch (e) {
      emit(state.copiar(cargando: false, error: mensajeErrorGateway(e)));
    }
  }

  /// Carga la primera tarifa de [categoriaId] o, con [tarifaId], la edita.
  /// Devuelve `true` si Core la guardó.
  Future<bool> guardar({
    required String categoriaId,
    String? tarifaId,
    required DatosTarifa datos,
  }) async {
    final invalida = datos.error;
    if (invalida != null) {
      emit(state.copiar(aviso: invalida, avisoEsError: true));
      return false;
    }
    emit(state.copiar(guardando: true));
    try {
      final guardada = tarifaId == null
          ? await _fuente.crear(categoriaId, datos)
          : await _fuente.editar(tarifaId, datos);
      emit(
        state.copiar(
          guardando: false,
          aviso: 'Tarifa guardada: versión ${guardada.version}.',
        ),
      );
      await cargar();
      return true;
    } catch (e) {
      emit(
        state.copiar(
          guardando: false,
          aviso: mensajeErrorGateway(e),
          avisoEsError: true,
        ),
      );
      return false;
    }
  }

  Future<List<Tarifa>> historial(String categoriaId) =>
      _fuente.historial(categoriaId);
}
