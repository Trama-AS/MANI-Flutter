import '../entities/catalogo_solicitud.dart';
import '../entities/nueva_solicitud.dart';
import '../entities/solicitud_publicada.dart';

/// Puerto del dominio. La implementación vive en `data/` (Supabase).
/// Todas las operaciones lanzan `SolicitudFailure` ante errores.
///
/// Ningún método recibe `tenantId` ni `clienteId`: el servidor los deriva de
/// la sesión (anti tenant-spoofing).
abstract interface class SolicitudesClienteRepository {
  /// Categorías activas del tenant del cliente.
  Future<List<CategoriaDisponible>> categoriasDisponibles();

  /// Direcciones ya registradas por el cliente.
  Future<List<SitioCliente>> misSitios();

  /// Barrios o localidades cuyo nombre contiene [texto].
  Future<List<ZonaOpcion>> buscarZonas(String texto);

  /// Sube las fotos y publica la solicitud. Es idempotente por
  /// `claveIdempotencia`: un reintento devuelve la misma solicitud.
  ///
  /// Después avisa a los aliados elegibles. Si ese aviso falla, la solicitud
  /// igual queda publicada y vuelve con `aliadosAvisados = false`.
  Future<SolicitudPublicada> publicar(NuevaSolicitud solicitud);

  /// Repite el aviso a los aliados de una solicitud ya publicada.
  Future<void> avisarAliados(String solicitudId);
}
