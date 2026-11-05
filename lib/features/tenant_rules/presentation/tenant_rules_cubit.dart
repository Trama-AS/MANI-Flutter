import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import '../data/tenant_rules_datasource.dart';
import '../domain/regla_tenant.dart';

sealed class TenantRulesState {
  const TenantRulesState();
}

class TenantRulesInitial extends TenantRulesState {
  const TenantRulesInitial();
}

class TenantRulesLoading extends TenantRulesState {
  const TenantRulesLoading();
}

class TenantRulesLoaded extends TenantRulesState {
  const TenantRulesLoaded({
    required this.vigente,
    required this.historial,
    this.guardando = false,
    this.mensajeExito,
    this.mensajeError,
  });

  final ReglaTenantVigente vigente;
  final List<ReglaTenantHistorialItem> historial;
  final bool guardando;
  final String? mensajeExito;
  final String? mensajeError;

  TenantRulesLoaded copyWith({
    ReglaTenantVigente? vigente,
    List<ReglaTenantHistorialItem>? historial,
    bool? guardando,
    String? mensajeExito,
    String? mensajeError,
  }) {
    return TenantRulesLoaded(
      vigente: vigente ?? this.vigente,
      historial: historial ?? this.historial,
      guardando: guardando ?? this.guardando,
      mensajeExito: mensajeExito,
      mensajeError: mensajeError,
    );
  }
}

class TenantRulesError extends TenantRulesState {
  const TenantRulesError(this.mensaje);
  final String mensaje;
}

class TenantRulesCubit extends Cubit<TenantRulesState> {
  TenantRulesCubit(this._fuente) : super(const TenantRulesInitial());

  final FuenteReglasTenant _fuente;

  Future<void> cargar() async {
    emit(const TenantRulesLoading());
    try {
      final vigente = await _fuente.getVigente();
      final historial = await _fuente.getHistorial();
      emit(TenantRulesLoaded(vigente: vigente, historial: historial));
    } catch (e) {
      emit(TenantRulesError(mensajeErrorGateway(e)));
    }
  }

  Future<bool> guardar(ReglasOperativas reglas) async {
    final estado = state;
    if (estado is! TenantRulesLoaded) return false;

    emit(
      estado.copyWith(guardando: true, mensajeError: null, mensajeExito: null),
    );
    try {
      final actualizada = await _fuente.actualizar(
        expectedVersion: estado.vigente.version,
        reglas: reglas,
      );
      List<ReglaTenantHistorialItem> nuevoHistorial;
      try {
        nuevoHistorial = await _fuente.getHistorial();
      } catch (_) {
        nuevoHistorial = estado.historial;
      }
      emit(
        TenantRulesLoaded(
          vigente: actualizada,
          historial: nuevoHistorial,
          guardando: false,
          mensajeExito:
              'Reglas actualizadas a la versión ${actualizada.version} correctamente.',
        ),
      );
      return true;
    } catch (e) {
      ReglaTenantVigente nuevaVigente = estado.vigente;
      List<ReglaTenantHistorialItem> nuevoHistorial = estado.historial;
      final es409 =
          (e is GatewayException && e.statusCode == 409) ||
          e.toString().contains('409');
      if (es409) {
        try {
          nuevaVigente = await _fuente.getVigente();
          nuevoHistorial = await _fuente.getHistorial();
        } catch (_) {}
      }
      emit(
        estado.copyWith(
          vigente: nuevaVigente,
          historial: nuevoHistorial,
          guardando: false,
          mensajeError: mensajeErrorGateway(e),
        ),
      );
      return false;
    }
  }
}
