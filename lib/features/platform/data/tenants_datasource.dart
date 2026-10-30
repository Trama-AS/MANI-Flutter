import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';

/// Estado de un tenant en la plataforma (HU-M12-07 / SCRUM-901).
enum EstadoTenant {
  activo('ACTIVE', 'Activo'),
  suspendido('SUSPENDED', 'Suspendido'),
  inactivo('INACTIVE', 'Inactivo');

  const EstadoTenant(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static EstadoTenant desde(String? valor) =>
      values.firstWhere((e) => e.valor == valor, orElse: () => inactivo);
}

class TenantPlataforma extends Equatable {
  const TenantPlataforma({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.estado,
  });

  factory TenantPlataforma.fromJson(Map<String, dynamic> json) =>
      TenantPlataforma(
        id: '${json['id']}',
        nombre: (json['name'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        estado: EstadoTenant.desde(json['status'] as String?),
      );

  final String id;
  final String nombre;
  final String slug;
  final EstadoTenant estado;

  @override
  List<Object?> get props => [id, nombre, slug, estado];
}

class CambioEstadoTenant extends Equatable {
  const CambioEstadoTenant({
    required this.anterior,
    required this.nuevo,
    required this.motivo,
    this.fecha,
  });

  factory CambioEstadoTenant.fromJson(Map<String, dynamic> json) =>
      CambioEstadoTenant(
        anterior: EstadoTenant.desde(json['estadoAnterior'] as String?),
        nuevo: EstadoTenant.desde(json['estadoNuevo'] as String?),
        motivo: (json['motivo'] as String?) ?? '',
        fecha: DateTime.tryParse('${json['fecha']}'),
      );

  final EstadoTenant anterior;
  final EstadoTenant nuevo;
  final String motivo;
  final DateTime? fecha;

  @override
  List<Object?> get props => [anterior, nuevo, motivo, fecha];
}

abstract interface class FuenteTenants {
  Future<List<TenantPlataforma>> listar();

  Future<TenantPlataforma> cambiarEstado(
    String tenantId,
    EstadoTenant estado,
    String motivo,
  );

  Future<List<CambioEstadoTenant>> historial(String tenantId);
}

/// Administración de tenants por el Gateway a Core (SCRUM-1364 y 901). Core
/// exige el permiso PLATFORM_ADMIN del JWT; la app no decide quién puede.
class GatewayFuenteTenants implements FuenteTenants {
  GatewayFuenteTenants(this._gateway);

  static const ruta = '/api/v1/core/tenants';

  final GatewayClient _gateway;

  @override
  Future<List<TenantPlataforma>> listar() async => [
    for (final t in ((await _gateway.get(ruta))['data'] as List? ?? const []))
      TenantPlataforma.fromJson(Map<String, dynamic>.from(t as Map)),
  ];

  @override
  Future<TenantPlataforma> cambiarEstado(
    String tenantId,
    EstadoTenant estado,
    String motivo,
  ) async {
    final res = await _gateway.patch('$ruta/$tenantId/estado', {
      'estado': estado.valor,
      'motivo': motivo.trim(),
    });
    final t = res['tenant'];
    if (t is! Map) {
      throw const FormatException('Respuesta de Core sin "tenant"');
    }
    return TenantPlataforma.fromJson(Map<String, dynamic>.from(t));
  }

  @override
  Future<List<CambioEstadoTenant>> historial(String tenantId) async => [
    for (final c
        in ((await _gateway.get('$ruta/$tenantId/estado/historial'))['cambios']
                as List? ??
            const []))
      CambioEstadoTenant.fromJson(Map<String, dynamic>.from(c as Map)),
  ];
}
