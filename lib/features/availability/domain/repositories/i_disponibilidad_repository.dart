import '../entities/ausencia.dart';

/// Contrato del repositorio de disponibilidad del aliado autenticado.
/// Tenant y aliado los resuelve Core desde el JWT: nunca se envían.
/// Todas las operaciones lanzan `DisponibilidadFailure` ante errores.
abstract class IDisponibilidadRepository {
  Future<DisponibilidadAliado> obtener();

  Future<Ausencia> crear(BorradorAusencia borrador);

  Future<Ausencia> editar(String id, BorradorAusencia borrador);

  Future<void> eliminar(String id);
}
