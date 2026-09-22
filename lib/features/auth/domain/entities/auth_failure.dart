/// Excepción de dominio para errores de autenticación.
///
/// La capa de datos (repositorio/datasource) mapea los errores específicos
/// del proveedor (Supabase, Firebase, etc.) a esta clase antes de propagarlos
/// hacia arriba. Esto garantiza que la presentación no dependa de ningún SDK
/// externo de infraestructura.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}
