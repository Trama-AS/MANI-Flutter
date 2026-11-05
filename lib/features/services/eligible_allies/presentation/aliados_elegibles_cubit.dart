import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/elegibles_datasource.dart';
import '../domain/aliado_elegible.dart';

class AliadosElegiblesState extends Equatable {
  const AliadosElegiblesState({
    this.cargando = false,
    this.lista,
    this.tipo,
    this.error,
  });

  final bool cargando;

  /// Última lista consultada con éxito para el filtro vigente.
  final ListaElegibles? lista;

  /// Filtro de tipo de aliado (SCRUM-1400); `null` es «Todos».
  final TipoAliado? tipo;

  /// Mensaje para el usuario si la última consulta falló.
  final String? error;

  @override
  List<Object?> get props => [cargando, lista, tipo, error];
}

/// Aliados elegibles de una solicitud del cliente (SCRUM-1398, 1400 y 1401).
/// Muestra la lista en el orden que entrega Dispatch, sin reordenar.
class AliadosElegiblesCubit extends Cubit<AliadosElegiblesState> {
  AliadosElegiblesCubit(this._fuente, this.solicitudId)
    : super(const AliadosElegiblesState());

  final FuenteElegibles _fuente;
  final String solicitudId;

  /// Consulta con el filtro vigente.
  Future<void> cargar() => _consultar(state.tipo);

  /// Cambia el filtro de tipo. Una respuesta de un filtro anterior que llegue
  /// tarde se descarta.
  Future<void> filtrar(TipoAliado? tipo) async {
    if (tipo == state.tipo && state.lista != null) return;
    await _consultar(tipo);
  }

  Future<void> _consultar(TipoAliado? tipo) async {
    // Al cambiar de filtro no se muestran los aliados del filtro anterior.
    final conserva = tipo == state.tipo ? state.lista : null;
    emit(AliadosElegiblesState(cargando: true, lista: conserva, tipo: tipo));
    try {
      final lista = await _fuente.listar(solicitudId, tipo: tipo);
      if (isClosed || state.tipo != tipo) return;
      emit(AliadosElegiblesState(lista: lista, tipo: tipo));
    } on ElegiblesFailure catch (f) {
      _fallo(tipo, f.mensajeUsuario);
    } catch (_) {
      _fallo(
        tipo,
        const ElegiblesFailure(ElegiblesErrorTipo.desconocido).mensajeUsuario,
      );
    }
  }

  void _fallo(TipoAliado? tipo, String mensaje) {
    if (isClosed || state.tipo != tipo) return;
    emit(AliadosElegiblesState(lista: state.lista, tipo: tipo, error: mensaje));
  }
}
