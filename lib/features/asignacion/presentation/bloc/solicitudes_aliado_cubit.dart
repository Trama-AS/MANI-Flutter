import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/bandeja_solicitudes.dart';
import '../../domain/entities/motivo_rechazo.dart';
import '../../domain/entities/solicitud_entity.dart';
import '../../domain/failures/asignacion_failure.dart';
import '../../domain/usecases/asignacion_usecases.dart';

part 'solicitudes_aliado_state.dart';

/// Estado y acciones de la bandeja de solicitudes del aliado (US-04.1.4).
class SolicitudesAliadoCubit extends Cubit<SolicitudesAliadoState> {
  SolicitudesAliadoCubit({
    required ListarSolicitudesAliado listar,
    required AceptarSolicitud aceptar,
    required RechazarSolicitud rechazar,
  }) : _listar = listar,
       _aceptar = aceptar,
       _rechazar = rechazar,
       super(const SolicitudesAliadoState());

  final ListarSolicitudesAliado _listar;
  final AceptarSolicitud _aceptar;
  final RechazarSolicitud _rechazar;
  int _secuenciaAvisos = 0;

  /// Carga la bandeja. Con [silencioso] conserva lo que hay en pantalla
  /// mientras llega lo nuevo (refresco periódico, botón actualizar).
  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso || state.carga != CargaSolicitudes.listo) {
      emit(state.copyWith(carga: CargaSolicitudes.cargando, error: null));
    }
    try {
      final bandeja = await _listar();
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          carga: CargaSolicitudes.listo,
          bandeja: bandeja,
          error: null,
        ),
      );
    } on AsignacionFailure catch (f) {
      if (isClosed) {
        return;
      }
      if (state.carga == CargaSolicitudes.listo) {
        _avisar(f.mensajeUsuario, TipoAviso.error);
      } else {
        emit(state.copyWith(carga: CargaSolicitudes.error, error: f));
      }
    }
  }

  void cambiarPestana(PestanaSolicitudes pestana) =>
      emit(state.copyWith(pestana: pestana));

  /// Devuelve `true` si el aliado ganó la solicitud.
  Future<bool> aceptar(String solicitudId) async {
    final solicitud = state.bandeja.porId(solicitudId);
    if (solicitud == null || state.procesando) {
      return false;
    }
    emit(
      state.copyWith(
        procesandoId: solicitudId,
        accion: AccionSolicitud.aceptando,
      ),
    );
    try {
      final asignada = await _aceptar(solicitud);
      if (isClosed) {
        return true;
      }
      emit(
        state.copyWith(
          bandeja: state.bandeja.conAsignada(asignada),
          pestana: PestanaSolicitudes.misTrabajos,
          recienAsignadaId: asignada.id,
          procesandoId: null,
          accion: null,
        ),
      );
      _avisar(
        '¡La solicitud de ${asignada.categoria} es tuya! '
        'Ya puedes ver la dirección del cliente.',
        TipoAviso.exito,
      );
      return true;
    } on AsignacionFailure catch (f) {
      if (isClosed) {
        return false;
      }
      await _trasFallo(solicitudId, f);
      return false;
    }
  }

  /// Devuelve `true` si la solicitud quedó rechazada para este aliado.
  Future<bool> rechazar(String solicitudId, {MotivoRechazo? motivo}) async {
    final solicitud = state.bandeja.porId(solicitudId);
    if (solicitud == null || state.procesando) {
      return false;
    }
    emit(
      state.copyWith(
        procesandoId: solicitudId,
        accion: AccionSolicitud.rechazando,
      ),
    );
    try {
      await _rechazar(solicitud, motivo: motivo);
      if (isClosed) {
        return true;
      }
      emit(
        state.copyWith(
          bandeja: state.bandeja.sin(solicitudId),
          procesandoId: null,
          accion: null,
        ),
      );
      _avisar(
        'Solicitud descartada. Seguirá disponible para otros aliados.',
        TipoAviso.info,
      );
      return true;
    } on AsignacionFailure catch (f) {
      if (isClosed) {
        return false;
      }
      await _trasFallo(solicitudId, f);
      return false;
    }
  }

  /// Si la solicitud ya no se puede tomar, se quita de la bandeja y se trae
  /// el estado real del servidor para no mostrar datos viejos.
  Future<void> _trasFallo(String solicitudId, AsignacionFailure f) async {
    final obsoleta = switch (f.tipo) {
      AsignacionErrorTipo.yaNoDisponible ||
      AsignacionErrorTipo.noEncontrada ||
      AsignacionErrorTipo.noElegible ||
      AsignacionErrorTipo.yaEsTuya => true,
      _ => false,
    };
    emit(
      state.copyWith(
        bandeja: obsoleta ? state.bandeja.sin(solicitudId) : state.bandeja,
        procesandoId: null,
        accion: null,
      ),
    );
    _avisar(f.mensajeUsuario, TipoAviso.error);
    if (obsoleta) {
      await cargar(silencioso: true);
    }
  }

  void _avisar(String mensaje, TipoAviso tipo) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        aviso: AvisoSolicitudes(++_secuenciaAvisos, mensaje, tipo),
      ),
    );
  }
}
