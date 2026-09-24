import '../entities/decision_verificacion.dart';
import '../entities/documento_kyc.dart';
import '../entities/solicitud_aliado.dart';
import '../failures/verificacion_failure.dart';
import '../repositories/verificacion_aliados_repository.dart';

/// Carga la bandeja ordenada para atender primero a quien más lleva esperando:
/// pendientes del más antiguo al más reciente (FIFO) y, después, las ya
/// resueltas de la más reciente a la más antigua.
class ListarSolicitudesAliados {
  const ListarSolicitudesAliados(this._repo);
  final VerificacionAliadosRepository _repo;

  Future<List<SolicitudAliado>> call() async {
    final todas = await _repo.listarSolicitudes();
    return List.of(todas)..sort(_orden);
  }

  static int _orden(SolicitudAliado a, SolicitudAliado b) {
    if (a.estaPendiente != b.estaPendiente) return a.estaPendiente ? -1 : 1;
    if (a.estaPendiente) return a.fechaRegistro.compareTo(b.fechaRegistro);
    final fa = a.fechaVerificacion ?? a.fechaRegistro;
    final fb = b.fechaVerificacion ?? b.fechaRegistro;
    return fb.compareTo(fa);
  }
}

class ObtenerDetalleAliado {
  const ObtenerDetalleAliado(this._repo);
  final VerificacionAliadosRepository _repo;

  Future<SolicitudAliado> call(String aliadoId) =>
      _repo.obtenerDetalle(aliadoId);
}

class AprobarAliado {
  const AprobarAliado(this._repo);
  final VerificacionAliadosRepository _repo;

  Future<SolicitudAliado> call(SolicitudAliado aliado) {
    if (!aliado.estaPendiente) {
      throw const VerificacionFailure(VerificacionErrorTipo.yaResuelta);
    }
    if (!aliado.tieneDocumentos) {
      throw const VerificacionFailure(VerificacionErrorTipo.sinDocumentos);
    }
    return _repo.resolver(aliado.id, const DecisionVerificacion.aprobar());
  }
}

class RechazarAliado {
  const RechazarAliado(this._repo);
  final VerificacionAliadosRepository _repo;

  Future<SolicitudAliado> call(SolicitudAliado aliado, String motivo) {
    if (!aliado.estaPendiente) {
      throw const VerificacionFailure(VerificacionErrorTipo.yaResuelta);
    }
    return _repo.resolver(aliado.id, DecisionVerificacion.rechazar(motivo));
  }
}

class ObtenerUrlDocumento {
  const ObtenerUrlDocumento(this._repo);
  final VerificacionAliadosRepository _repo;

  Future<Uri> call(DocumentoKyc documento) => _repo.urlDocumento(documento);
}
