import 'package:equatable/equatable.dart';

/// Entidad de dominio para el perfil propio del usuario autenticado (US-02.3.1 / SCRUM-854).
class PerfilPropio extends Equatable {
  const PerfilPropio({
    required this.id,
    required this.tenantId,
    required this.role,
    required this.fullName,
    required this.status,
    this.phone,
    this.address,
    this.photoUrl,
  });

  final String id;
  final String tenantId;
  final String role;
  final String fullName;
  final String status;
  final String? phone;
  final String? address;
  final String? photoUrl;

  factory PerfilPropio.fromJson(Map<String, dynamic> json) {
    final map = json['profile'] is Map<String, dynamic>
        ? json['profile'] as Map<String, dynamic>
        : json;
    return PerfilPropio(
      id: (map['id'] ?? '').toString(),
      tenantId: (map['tenantId'] ?? map['tenant_id'] ?? '').toString(),
      role: (map['role'] ?? 'CLIENT').toString(),
      fullName: (map['fullName'] ?? map['nombre'] ?? '').toString(),
      status: (map['status'] ?? 'VERIFIED').toString(),
      phone: map['phone'] as String? ?? map['telefono'] as String?,
      address: map['address'] as String? ?? map['direccion'] as String?,
      photoUrl: map['photoUrl'] as String? ?? map['foto_url'] as String?,
    );
  }

  PerfilPropio copyWith({
    String? fullName,
    String? phone,
    String? address,
    String? photoUrl,
  }) {
    return PerfilPropio(
      id: id,
      tenantId: tenantId,
      role: role,
      fullName: fullName ?? this.fullName,
      status: status,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  List<Object?> get props => [
    id,
    tenantId,
    role,
    fullName,
    status,
    phone,
    address,
    photoUrl,
  ];
}
