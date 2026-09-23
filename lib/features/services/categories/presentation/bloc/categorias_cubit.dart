import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/categoria_servicio.dart';
import '../../domain/entities/flujo_operativo.dart';
import '../../domain/entities/nueva_categoria.dart';
import '../../domain/failures/categoria_failure.dart';
import '../../domain/usecases/categoria_usecases.dart';

part 'categorias_state.dart';

/// Estado y acciones del catálogo de categorías del tenant (US-03.1.1).
class CategoriasCubit extends Cubit<CategoriasState> {
  CategoriasCubit({
    required ListarCategorias listar,
    required CrearCategoria crear,
  }) : _listar = listar,
       _crear = crear,
       super(const CategoriasState());

  final ListarCategorias _listar;
  final CrearCategoria _crear;
  int _secuenciaAvisos = 0;

  /// Carga el catálogo. Con [silencioso] conserva la lista en pantalla
  /// mientras llega la nueva (botón actualizar).
  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso || state.carga != CargaCategorias.listo) {
      emit(state.copyWith(carga: CargaCategorias.cargando, error: null));
    }
    try {
      final categorias = await _listar();
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          carga: CargaCategorias.listo,
          categorias: categorias,
          error: null,
        ),
      );
    } on CategoriaFailure catch (f) {
      if (isClosed) {
        return;
      }
      if (state.carga == CargaCategorias.listo) {
        _avisar(f.mensajeUsuario, esError: true);
      } else {
        emit(state.copyWith(carga: CargaCategorias.error, error: f));
      }
    }
  }

  void buscar(String texto) => emit(state.copyWith(busqueda: texto));

  /// Crea la categoría. Devuelve `null` si se creó, o la falla para que el
  /// formulario la muestre junto al campo correspondiente.
  Future<CategoriaFailure?> crear({
    required String nombre,
    required FlujoOperativo? flujo,
    required bool activa,
  }) async {
    if (state.guardando) {
      return null;
    }
    final NuevaCategoria nueva;
    try {
      nueva = NuevaCategoria.crear(
        nombre: nombre,
        flujo: flujo,
        activa: activa,
      );
    } on CategoriaFailure catch (f) {
      return f;
    }

    emit(state.copyWith(guardando: true));
    try {
      final creada = await _crear(nueva, existentes: state.categorias);
      if (isClosed) {
        return null;
      }
      final lista = [...state.categorias, creada]
        ..sort((a, b) => a.claveNombre.compareTo(b.claveNombre));
      emit(
        state.copyWith(
          categorias: lista,
          guardando: false,
          recienCreadaId: creada.id,
          busqueda: '',
        ),
      );
      _avisar(
        creada.activa
            ? 'Categoría "${creada.nombre}" creada. Ya aparece en el catálogo de tus clientes.'
            : 'Categoría "${creada.nombre}" guardada como oculta. Tus clientes no la verán hasta que la actives.',
      );
      return null;
    } on CategoriaFailure catch (f) {
      if (isClosed) {
        return f;
      }
      emit(state.copyWith(guardando: false));
      // Otro administrador la creó mientras tanto: se trae el catálogo real.
      if (f.tipo == CategoriaErrorTipo.nombreDuplicado) {
        await cargar(silencioso: true);
      }
      return f;
    }
  }

  void _avisar(String mensaje, {bool esError = false}) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        aviso: AvisoCategorias(++_secuenciaAvisos, mensaje, esError: esError),
      ),
    );
  }
}
