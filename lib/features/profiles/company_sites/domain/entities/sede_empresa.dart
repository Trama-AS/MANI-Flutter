import 'package:equatable/equatable.dart';

/// Entidad que representa una sede o sucursal (`sitio`) de un cliente corporativo
/// (US-02.2.2 / SCRUM-852).
class SedeEmpresa extends Equatable {
  const SedeEmpresa({
    required this.id,
    required this.clienteId,
    required this.tenantId,
    required this.nombre,
    required this.direccion,
    required this.zonaId,
    this.contactoNombre,
    this.contactoTelefono,
    this.activo = true,
  });

  final String id;
  final String clienteId;
  final String tenantId;
  final String nombre;
  final String direccion;
  final String zonaId;
  final String? contactoNombre;
  final String? contactoTelefono;
  final bool activo;

  factory SedeEmpresa.fromJson(Map<String, dynamic> json) {
    return SedeEmpresa(
      id: (json['id'] ?? '').toString(),
      clienteId: (json['clienteId'] ?? json['cliente_id'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? json['tenant_id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      direccion: (json['direccion'] ?? '').toString(),
      zonaId: (json['zonaId'] ?? json['zona_id'] ?? '').toString(),
      contactoNombre: (json['contactoNombre'] ?? json['contacto_nombre'])
          ?.toString(),
      contactoTelefono: (json['contactoTelefono'] ?? json['contacto_telefono'])
          ?.toString(),
      activo: json['activo'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
    id,
    clienteId,
    tenantId,
    nombre,
    direccion,
    zonaId,
    contactoNombre,
    contactoTelefono,
    activo,
  ];
}

/// Zona del catálogo de Core (`GET /catalog/zones`, SCRUM-1393). Una sede solo
/// puede quedar en una zona [seleccionable] con zona padre (barrio o
/// localidad), igual que la dirección de una solicitud.
class ZonaSede extends Equatable {
  const ZonaSede({
    required this.id,
    required this.nombre,
    this.padreId,
    this.seleccionable = false,
  });

  final String id;
  final String nombre;
  final String? padreId;
  final bool seleccionable;

  factory ZonaSede.fromJson(Map<String, dynamic> json) {
    return ZonaSede(
      id: (json['id'] ?? '').toString(),
      nombre: (json['name'] ?? '').toString(),
      padreId: json['parentId']?.toString(),
      seleccionable: json['selectable'] == true,
    );
  }

  /// Se puede elegir para una sede: activa y con zona padre.
  bool get elegible => seleccionable && padreId != null;

  @override
  List<Object?> get props => [id, nombre, padreId, seleccionable];
}

/// Datos para agregar una nueva sucursal o sede al cliente corporativo (SCRUM-852).
class NuevaSedeEmpresa extends Equatable {
  const NuevaSedeEmpresa({
    required this.nombre,
    required this.direccion,
    required this.zonaId,
    this.contactoNombre,
    this.contactoTelefono,
  });

  final String nombre;
  final String direccion;
  final String zonaId;
  final String? contactoNombre;
  final String? contactoTelefono;

  @override
  List<Object?> get props => [
    nombre,
    direccion,
    zonaId,
    contactoNombre,
    contactoTelefono,
  ];
}
