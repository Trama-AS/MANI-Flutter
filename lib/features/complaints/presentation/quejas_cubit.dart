import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';

import '../data/quejas_datasource.dart';
import '../domain/queja.dart';

class QuejasState extends Equatable {
  const QuejasState({
    this.cargando = false,
    this.quejas = const [],
    this.filtro,
    this.actualizandoId,
    this.error,
    this.aviso,
    this.avisoEsError = false,
  });

  final bool cargando;
  final List<Queja> quejas;

  /// Solo el administrador filtra por estado.
  final EstadoQueja? filtro;
  final String? actualizandoId;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  QuejasState copiar({
    bool? cargando,
    List<Queja>? quejas,
    EstadoQueja? filtro,
    bool quitarFiltro = false,
    String? actualizandoId,
    String? error,
    String? aviso,
    bool avisoEsError = false,
  }) => QuejasState(
    cargando: cargando ?? this.cargando,
    quejas: quejas ?? this.quejas,
    filtro: quitarFiltro ? null : (filtro ?? this.filtro),
    actualizandoId: actualizandoId,
    error: error,
    aviso: aviso,
    avisoEsError: avisoEsError,
  );

  @override
  List<Object?> get props => [
    cargando,
    quejas,
    filtro,
    actualizandoId,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Quejas del cliente (SCRUM-895, [esAdmin] = false) o del tenant
/// (SCRUM-896, [esAdmin] = true). Tras cada cambio de estado se recarga de
/// Core: la transición y su auditoría las decide el servidor.
class QuejasCubit extends Cubit<QuejasState> {
  QuejasCubit(this._fuente, {required this.esAdmin})
    : super(const QuejasState());

  final FuenteQuejas _fuente;
  final bool esAdmin;

  Future<void> cargar() async {
    emit(state.copiar(cargando: true));
    try {
      final quejas = esAdmin
          ? await _fuente.delTenant(estado: state.filtro)
          : await _fuente.mias();
      emit(state.copiar(cargando: false, quejas: quejas));
    } catch (e) {
      emit(state.copiar(cargando: false, error: mensajeErrorGateway(e)));
    }
  }

  Future<void> filtrar(EstadoQueja? estado) async {
    emit(state.copiar(filtro: estado, quitarFiltro: estado == null));
    await cargar();
  }

  Future<List<TransicionQueja>> historial(String quejaId) async =>
      (await _fuente.detalle(quejaId)).historial;

  /// Devuelve `true` si Core aplicó la transición.
  Future<bool> cambiarEstado(
    Queja queja,
    EstadoQueja estado, {
    String? nota,
  }) async {
    emit(state.copiar(actualizandoId: queja.id));
    try {
      await _fuente.cambiarEstado(queja.id, estado, nota: nota);
      emit(
        state.copiar(aviso: 'La queja quedó ${estado.etiqueta.toLowerCase()}.'),
      );
      await cargar();
      return true;
    } catch (e) {
      emit(state.copiar(aviso: mensajeErrorGateway(e), avisoEsError: true));
      return false;
    }
  }
}
