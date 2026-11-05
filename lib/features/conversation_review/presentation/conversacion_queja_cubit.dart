import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../data/conversacion_queja_datasource.dart';
import '../domain/consulta_conversacion.dart';

enum FaseConversacion { formulario, consultando, listo, error }

class ConversacionQuejaState extends Equatable {
  const ConversacionQuejaState({
    this.fase = FaseConversacion.formulario,
    this.resultado,
    this.error,
  });

  final FaseConversacion fase;
  final ConversacionConsultada? resultado;
  final String? error;

  @override
  List<Object?> get props => [fase, resultado, error];
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _refValida = RegExp(r'^[A-Za-z0-9._:-]{1,100}$');

/// Consulta de la conversación de una queja (SCRUM-883). Valida lo mismo que
/// Core (id de solicitud UUID, motivo de 5 a 500 caracteres, referencia opcional)
/// para no gastar una consulta, que queda en la auditoría, en un dato inválido.
class ConversacionQuejaCubit extends Cubit<ConversacionQuejaState> {
  ConversacionQuejaCubit(this._fuente) : super(const ConversacionQuejaState());

  final FuenteConversacionQueja _fuente;

  Future<void> consultar({
    required String solicitudId,
    required String motivo,
    String? quejaRef,
  }) async {
    final id = solicitudId.trim();
    final m = motivo.trim();
    final ref = (quejaRef ?? '').trim();
    String? problema;
    if (!_uuid.hasMatch(id)) {
      problema = 'El identificador de la solicitud no es válido.';
    } else if (m.length < 5 || m.length > 500) {
      problema = 'El motivo debe tener entre 5 y 500 caracteres.';
    } else if (ref.isNotEmpty && !_refValida.hasMatch(ref)) {
      problema = 'La referencia de la queja tiene caracteres no permitidos.';
    }
    if (problema != null) {
      emit(
        ConversacionQuejaState(fase: FaseConversacion.error, error: problema),
      );
      return;
    }
    emit(const ConversacionQuejaState(fase: FaseConversacion.consultando));
    try {
      emit(
        ConversacionQuejaState(
          fase: FaseConversacion.listo,
          resultado: await _fuente.consultar(
            id,
            motivo: m,
            quejaRef: ref.isEmpty ? null : ref,
          ),
        ),
      );
    } on GatewayException catch (e) {
      emit(
        ConversacionQuejaState(fase: FaseConversacion.error, error: e.message),
      );
    } on FormatException {
      emit(
        const ConversacionQuejaState(
          fase: FaseConversacion.error,
          error: 'No pudimos leer la conversación. Inténtalo de nuevo.',
        ),
      );
    }
  }
}
