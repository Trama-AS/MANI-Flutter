import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../data/avisos_datasource.dart';
import '../domain/aviso.dart';

enum FaseAvisos { cargando, listo, error }

class AvisosState extends Equatable {
  const AvisosState({
    this.fase = FaseAvisos.cargando,
    this.bandeja,
    this.error,
  });

  final FaseAvisos fase;
  final BandejaAvisos? bandeja;
  final String? error;

  @override
  List<Object?> get props => [fase, bandeja, error];
}

/// Bandeja de avisos del usuario (SCRUM-882 y 884). Solo lee.
class AvisosCubit extends Cubit<AvisosState> {
  AvisosCubit(this._fuente) : super(const AvisosState());

  final FuenteAvisos _fuente;

  Future<void> cargar() async {
    emit(const AvisosState());
    try {
      emit(
        AvisosState(fase: FaseAvisos.listo, bandeja: await _fuente.listar()),
      );
    } on GatewayException catch (e) {
      emit(AvisosState(fase: FaseAvisos.error, error: e.message));
    } on FormatException {
      emit(
        const AvisosState(
          fase: FaseAvisos.error,
          error: 'No pudimos leer tus avisos. Inténtalo de nuevo.',
        ),
      );
    }
  }
}
