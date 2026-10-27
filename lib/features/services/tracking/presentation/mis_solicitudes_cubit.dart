import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/seguimiento_datasource.dart';
import '../domain/solicitud_seguimiento.dart';

class MisSolicitudesState extends Equatable {
  const MisSolicitudesState({
    this.cargando = false,
    this.solicitudes = const [],
    this.error,
    this.consultadoEn,
  });

  final bool cargando;
  final List<SolicitudSeguimiento> solicitudes;

  /// Mensaje para el usuario si la última consulta falló.
  final String? error;

  /// Cuándo se consultó por última vez con éxito.
  final DateTime? consultadoEn;

  @override
  List<Object?> get props => [cargando, solicitudes, error, consultadoEn];
}

/// Estado de las solicitudes del cliente (HU-M07-04 / SCRUM-871). No hay
/// actualización automática: el estado se refresca al consultar de nuevo.
class MisSolicitudesCubit extends Cubit<MisSolicitudesState> {
  MisSolicitudesCubit(this._fuente, {DateTime Function()? reloj})
    : _reloj = reloj ?? DateTime.now,
      super(const MisSolicitudesState());

  final FuenteSeguimiento _fuente;
  final DateTime Function() _reloj;

  Future<void> cargar() async {
    emit(
      MisSolicitudesState(
        cargando: true,
        solicitudes: state.solicitudes,
        consultadoEn: state.consultadoEn,
      ),
    );
    try {
      final lista = await _fuente.listar();
      if (isClosed) return;
      emit(MisSolicitudesState(solicitudes: lista, consultadoEn: _reloj()));
    } on SeguimientoFailure catch (f) {
      _fallo(f.mensajeUsuario);
    } catch (_) {
      _fallo(
        const SeguimientoFailure(
          SeguimientoErrorTipo.desconocido,
        ).mensajeUsuario,
      );
    }
  }

  /// Se conserva lo que ya se veía, pero se avisa que no está al día.
  void _fallo(String mensaje) {
    if (isClosed) return;
    emit(
      MisSolicitudesState(
        solicitudes: state.solicitudes,
        consultadoEn: state.consultadoEn,
        error: mensaje,
      ),
    );
  }
}
