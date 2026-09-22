import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mani/core/platform/url_opener.dart';

import '../../domain/entities/documento_kyc.dart';
import '../../domain/entities/solicitud_aliado.dart';
import '../../domain/failures/verificacion_failure.dart';
import '../../domain/usecases/verificacion_usecases.dart';

part 'bandeja_verificacion_state.dart';

/// Estado y acciones de la bandeja de verificación de aliados (US-02.1.3).
class BandejaVerificacionCubit extends Cubit<BandejaVerificacionState> {
  BandejaVerificacionCubit({
    required ListarSolicitudesAliados listar,
    required ObtenerDetalleAliado obtenerDetalle,
    required AprobarAliado aprobar,
    required RechazarAliado rechazar,
    required ObtenerUrlDocumento urlDocumento,
    required UrlOpener urlOpener,
  }) : _listar = listar,
       _obtenerDetalle = obtenerDetalle,
       _aprobar = aprobar,
       _rechazar = rechazar,
       _urlDocumento = urlDocumento,
       _urlOpener = urlOpener,
       super(const BandejaVerificacionState());

  final ListarSolicitudesAliados _listar;
  final ObtenerDetalleAliado _obtenerDetalle;
  final AprobarAliado _aprobar;
  final RechazarAliado _rechazar;
  final ObtenerUrlDocumento _urlDocumento;
  final UrlOpener _urlOpener;
  int _secuenciaAvisos = 0;

  // ------------------------------------------------------------------ carga
  /// Carga la bandeja. Con [silencioso] conserva la lista actual en pantalla
  /// mientras llega la nueva (pull-to-refresh / botón actualizar).
  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso || state.carga != EstadoCarga.listo) {
      emit(state.copyWith(carga: EstadoCarga.cargando, error: null));
    }
    try {
      final solicitudes = await _listar();
      if (isClosed) return;
      final sigueExistiendo = solicitudes.any(
        (s) => s.id == state.seleccionadaId,
      );
      emit(
        state.copyWith(
          carga: EstadoCarga.listo,
          solicitudes: solicitudes,
          error: null,
          seleccionadaId: sigueExistiendo ? state.seleccionadaId : null,
        ),
      );
    } on VerificacionFailure catch (f) {
      if (isClosed) return;
      if (state.carga == EstadoCarga.listo) {
        _avisar(f.mensajeUsuario, esError: true);
      } else {
        emit(state.copyWith(carga: EstadoCarga.error, error: f));
      }
    }
  }

  // ---------------------------------------------------------------- filtros
  void cambiarFiltro(EstadoVerificacion filtro) {
    if (filtro == state.filtro) return;
    emit(state.copyWith(filtro: filtro, seleccionadaId: null));
  }

  void buscar(String texto) => emit(state.copyWith(busqueda: texto));

  // -------------------------------------------------------------- selección
  /// Selecciona un aliado y trae su versión fresca (documentos incluidos).
  Future<void> seleccionar(String aliadoId) async {
    emit(state.copyWith(seleccionadaId: aliadoId, cargandoDetalleId: aliadoId));
    try {
      final detalle = await _obtenerDetalle(aliadoId);
      if (isClosed) return;
      emit(state.copyWith(solicitudes: _reemplazar(detalle)));
    } on VerificacionFailure catch (f) {
      if (isClosed) return;
      if (f.tipo == VerificacionErrorTipo.noEncontrado) {
        emit(
          state.copyWith(
            solicitudes: state.solicitudes
                .where((s) => s.id != aliadoId)
                .toList(growable: false),
            seleccionadaId: state.seleccionadaId == aliadoId
                ? null
                : state.seleccionadaId,
          ),
        );
      }
      _avisar(f.mensajeUsuario, esError: true);
    } finally {
      if (!isClosed && state.cargandoDetalleId == aliadoId) {
        emit(state.copyWith(cargandoDetalleId: null));
      }
    }
  }

  void cerrarDetalle() => emit(state.copyWith(seleccionadaId: null));

  // --------------------------------------------------------------- decisión
  /// Devuelve `true` si el aliado quedó aprobado.
  Future<bool> aprobar(String aliadoId) => _resolver(
    aliadoId,
    (aliado) => _aprobar(aliado),
    (aliado) =>
        '${aliado.nombre} fue aprobado. Ya puede recibir solicitudes de servicio.',
  );

  /// Devuelve `true` si el aliado quedó rechazado.
  Future<bool> rechazar(String aliadoId, String motivo) => _resolver(
    aliadoId,
    (aliado) => _rechazar(aliado, motivo),
    (aliado) => 'Rechazaste a ${aliado.nombre}. Le notificamos el motivo.',
  );

  Future<bool> _resolver(
    String aliadoId,
    Future<SolicitudAliado> Function(SolicitudAliado) accion,
    String Function(SolicitudAliado) mensajeExito,
  ) async {
    final aliado = state.porId(aliadoId);
    if (aliado == null || state.procesando) return false;

    // Al resolver, la bandeja avanza al siguiente pendiente para revisar en serie.
    final siguienteId = _siguienteVisible(aliadoId);
    emit(state.copyWith(procesandoId: aliadoId));
    try {
      final actualizado = await accion(aliado);
      if (isClosed) return true;
      emit(
        state.copyWith(
          solicitudes: _reemplazar(actualizado),
          procesandoId: null,
          seleccionadaId: state.seleccionadaId == aliadoId
              ? siguienteId
              : state.seleccionadaId,
        ),
      );
      _avisar(mensajeExito(actualizado));
      return true;
    } on VerificacionFailure catch (f) {
      if (isClosed) return false;
      emit(state.copyWith(procesandoId: null));
      _avisar(f.mensajeUsuario, esError: true);
      // Otro administrador se adelantó: se trae el estado real del aliado.
      if (f.tipo == VerificacionErrorTipo.yaResuelta) {
        await seleccionar(aliadoId);
      }
      return false;
    }
  }

  // ------------------------------------------------------------- documentos
  Future<void> abrirDocumento(DocumentoKyc documento) async {
    try {
      final url = await _urlDocumento(documento);
      final abierto = await _urlOpener.abrir(url);
      if (!abierto) {
        _avisar(
          const VerificacionFailure(
            VerificacionErrorTipo.documentoNoDisponible,
          ).mensajeUsuario,
          esError: true,
        );
      }
    } on VerificacionFailure catch (f) {
      _avisar(f.mensajeUsuario, esError: true);
    }
  }

  // ---------------------------------------------------------------- interno
  List<SolicitudAliado> _reemplazar(SolicitudAliado nuevo) => [
    for (final s in state.solicitudes) s.id == nuevo.id ? nuevo : s,
  ];

  String? _siguienteVisible(String aliadoId) {
    final visibles = state.visibles;
    final i = visibles.indexWhere((s) => s.id == aliadoId);
    if (i == -1 || visibles.length < 2) return null;
    return visibles[i + 1 < visibles.length ? i + 1 : i - 1].id;
  }

  void _avisar(String mensaje, {bool esError = false}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        aviso: AvisoVerificacion(++_secuenciaAvisos, mensaje, esError: esError),
      ),
    );
  }
}
