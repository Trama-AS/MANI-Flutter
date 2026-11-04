import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../data/auditoria_datasource.dart';
import '../domain/evento_transaccion.dart';

enum FaseAuditoria { cargando, listo, error }

class AuditoriaState extends Equatable {
  const AuditoriaState({
    this.fase = FaseAuditoria.cargando,
    this.eventos = const [],
    this.hayMas = false,
    this.cargandoMas = false,
    this.filtroPago,
    this.error,
  });

  final FaseAuditoria fase;
  final List<EventoTransaccion> eventos;
  final bool hayMas;
  final bool cargandoMas;
  final String? filtroPago;
  final String? error;

  @override
  List<Object?> get props => [
    fase,
    eventos,
    hayMas,
    cargandoMas,
    filtroPago,
    error,
  ];
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Auditoría de transacciones del administrador (SCRUM-889). Solo lee.
class AuditoriaCubit extends Cubit<AuditoriaState> {
  AuditoriaCubit(this._fuente, {this.tamanoPagina = 50})
    : super(const AuditoriaState());

  final FuenteAuditoria _fuente;
  final int tamanoPagina;

  /// Carga la primera página. Un [pagoId] que no es UUID se rechaza sin
  /// consultar: Core respondería 400.
  Future<void> cargar({String? pagoId}) async {
    final filtro = (pagoId ?? '').trim();
    if (filtro.isNotEmpty && !_uuid.hasMatch(filtro)) {
      emit(
        AuditoriaState(
          fase: FaseAuditoria.error,
          filtroPago: filtro,
          error: 'El identificador del pago no es válido.',
        ),
      );
      return;
    }
    emit(AuditoriaState(filtroPago: filtro.isEmpty ? null : filtro));
    await _pedir(despuesDe: null, acumulado: const []);
  }

  Future<void> cargarMas() async {
    if (!state.hayMas || state.cargandoMas || state.eventos.isEmpty) return;
    emit(
      AuditoriaState(
        fase: FaseAuditoria.listo,
        eventos: state.eventos,
        hayMas: true,
        cargandoMas: true,
        filtroPago: state.filtroPago,
      ),
    );
    await _pedir(despuesDe: state.eventos.last.id, acumulado: state.eventos);
  }

  Future<void> _pedir({
    required String? despuesDe,
    required List<EventoTransaccion> acumulado,
  }) async {
    final filtro = state.filtroPago;
    try {
      final pagina = await _fuente.listar(
        despuesDe: despuesDe,
        pagoId: filtro,
        limite: tamanoPagina,
      );
      emit(
        AuditoriaState(
          fase: FaseAuditoria.listo,
          eventos: [...acumulado, ...pagina],
          hayMas: pagina.length >= tamanoPagina,
          filtroPago: filtro,
        ),
      );
    } on GatewayException catch (e) {
      emit(
        AuditoriaState(
          fase: FaseAuditoria.error,
          eventos: acumulado,
          filtroPago: filtro,
          error: e.message,
        ),
      );
    } on FormatException {
      emit(
        AuditoriaState(
          fase: FaseAuditoria.error,
          eventos: acumulado,
          filtroPago: filtro,
          error: 'No pudimos leer la auditoría. Inténtalo de nuevo.',
        ),
      );
    }
  }
}
