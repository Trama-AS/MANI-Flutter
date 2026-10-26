/// Datos del registro de cliente empresa (HU-M02-07): cuenta con NIT y
/// representante legal, sin sitios. El tenant solo resuelve el registro
/// (viaja en X-Tenant-Slug, ADR-0018).
class RegistroClienteEmpresa {
  const RegistroClienteEmpresa({
    required this.email,
    required this.password,
    required this.razonSocial,
    required this.nit,
    required this.nombreRepresentante,
    required this.tenantId,
    this.telefono,
  });

  final String email;
  final String password;
  final String razonSocial;
  final String nit;
  final String nombreRepresentante;
  final String tenantId;
  final String? telefono;
}
