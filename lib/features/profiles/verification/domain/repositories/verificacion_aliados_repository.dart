import '../entities/decision_verificacion.dart';
import '../entities/documento_kyc.dart';
import '../entities/solicitud_aliado.dart';

/// Puerto del dominio. La implementación vive en `data/` (Supabase).
/// Todas las operaciones lanzan `VerificacionFailure` ante errores.
///
/// Ningún método recibe `tenantId`: el servidor lo deriva de la sesión del
/// administrador (anti tenant-spoofing).
abstract interface class VerificacionAliadosRepository {
  /// Todos los aliados del tenant del administrador autenticado.
  Future<List<SolicitudAliado>> listarSolicitudes();

  /// Lectura fresca de un aliado (con sus documentos) antes de decidir.
  Future<SolicitudAliado> obtenerDetalle(String aliadoId);

  /// Aplica la decisión y devuelve el aliado ya actualizado.
  Future<SolicitudAliado> resolver(
    String aliadoId,
    DecisionVerificacion decision,
  );

  /// URL firmada y temporal para visualizar un documento KYC.
  Future<Uri> urlDocumento(DocumentoKyc documento);
}
