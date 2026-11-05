import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/utils/generador_id.dart';

import '../data/pagos_datasource.dart';
import '../domain/pago.dart';

enum FasePago { inicial, pagando, resultado }

class PagoState extends Equatable {
  const PagoState({
    this.fase = FasePago.inicial,
    this.escenario = EscenarioPago.aprobado,
    this.pago,
    this.comprobante,
    this.falloComprobante = false,
    this.error,
  });

  final FasePago fase;
  final EscenarioPago escenario;
  final Pago? pago;
  final ComprobantePago? comprobante;

  /// El pago se aprobó pero no se pudo traer el comprobante.
  final bool falloComprobante;
  final PagoFailure? error;

  bool get pagando => fase == FasePago.pagando;

  PagoState copiar({
    FasePago? fase,
    EscenarioPago? escenario,
    Pago? pago,
    ComprobantePago? comprobante,
    bool falloComprobante = false,
    PagoFailure? error,
  }) => PagoState(
    fase: fase ?? this.fase,
    escenario: escenario ?? this.escenario,
    pago: pago ?? this.pago,
    comprobante: comprobante ?? this.comprobante,
    falloComprobante: falloComprobante,
    error: error,
  );

  @override
  List<Object?> get props => [
    fase,
    escenario,
    pago,
    comprobante,
    falloComprobante,
    error,
  ];
}

/// Pago de una cotización aceptada en el sandbox (SCRUM-1432). Cada pulsación de
/// «Pagar» usa una clave de idempotencia nueva: reintentar tras un rechazo es un
/// intento distinto, y un doble toque lo evita el estado `pagando`. Que no se
/// cobre dos veces una cotización lo garantiza Core.
class PagoCubit extends Cubit<PagoState> {
  PagoCubit(
    this._fuente,
    this.cotizacionId, {
    String Function() generarClave = nuevoUuid,
  }) : _generarClave = generarClave,
       super(const PagoState());

  final FuentePagos _fuente;
  final String cotizacionId;
  final String Function() _generarClave;

  void elegirEscenario(EscenarioPago escenario) {
    if (state.pagando) return;
    emit(
      state.copiar(
        escenario: escenario,
        falloComprobante: state.falloComprobante,
      ),
    );
  }

  Future<void> pagar() async {
    if (state.pagando) return;
    emit(PagoState(fase: FasePago.pagando, escenario: state.escenario));
    try {
      final pago = await _fuente.pagar(
        cotizacionId,
        escenario: state.escenario,
        claveIdempotencia: _generarClave(),
      );
      if (isClosed) return;
      emit(
        PagoState(
          fase: FasePago.resultado,
          escenario: state.escenario,
          pago: pago,
        ),
      );
      if (pago.aprobado) await _cargarComprobante(pago);
    } on PagoFailure catch (f) {
      if (isClosed) return;
      // Un fallo no deja un pago a medias: se vuelve al formulario con el error.
      emit(PagoState(escenario: state.escenario, error: f));
    }
  }

  Future<void> _cargarComprobante(Pago pago) async {
    try {
      final comprobante = await _fuente.comprobante(pago.id);
      if (isClosed) return;
      emit(state.copiar(comprobante: comprobante));
    } on PagoFailure {
      if (isClosed) return;
      emit(state.copiar(falloComprobante: true));
    }
  }
}
