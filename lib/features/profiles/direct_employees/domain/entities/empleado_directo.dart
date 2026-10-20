import 'package:equatable/equatable.dart';

/// Datos de entrada para registrar un empleado directo del tenant (US-02.1.5 / SCRUM-850).
class NuevoEmpleadoDirecto extends Equatable {
  const NuevoEmpleadoDirecto({
    required this.email,
    required this.password,
    required this.nombreCompleto,
    required this.categoriaIds,
    this.telefono,
  });

  final String email;
  final String password;
  final String nombreCompleto;
  final List<String> categoriaIds;
  final String? telefono;

  @override
  List<Object?> get props => [
    email,
    password,
    nombreCompleto,
    categoriaIds,
    telefono,
  ];
}

/// Resultado de un empleado directo creado y activado de forma inmediata
/// con estado `VERIFICADO` y `esEmpleadoDirecto = true` (US-02.1.5 / SCRUM-850).
class EmpleadoDirectoCreado extends Equatable {
  const EmpleadoDirectoCreado({
    required this.id,
    required this.usuarioId,
    required this.tenantId,
    required this.email,
    required this.nombreCompleto,
    required this.estadoVerificacion,
    required this.esEmpleadoDirecto,
    required this.categoriaIds,
    this.telefono,
  });

  final String id;
  final String usuarioId;
  final String tenantId;
  final String email;
  final String nombreCompleto;
  final String estadoVerificacion;
  final bool esEmpleadoDirecto;
  final List<String> categoriaIds;
  final String? telefono;

  factory EmpleadoDirectoCreado.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;
    final rawCats = data['categoriaIds'] ?? data['categorias'] ?? const [];
    return EmpleadoDirectoCreado(
      id: (data['id'] ?? data['aliadoId'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? data['userId'] ?? '').toString(),
      tenantId: (data['tenantId'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      nombreCompleto: (data['nombreCompleto'] ?? '').toString(),
      estadoVerificacion: (data['estadoVerificacion'] ?? 'VERIFICADO')
          .toString(),
      esEmpleadoDirecto: data['esEmpleadoDirecto'] as bool? ?? true,
      categoriaIds: rawCats is List
          ? rawCats.map((e) => e.toString()).toList()
          : const [],
      telefono: data['telefono']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    usuarioId,
    tenantId,
    email,
    nombreCompleto,
    estadoVerificacion,
    esEmpleadoDirecto,
    categoriaIds,
    telefono,
  ];
}
