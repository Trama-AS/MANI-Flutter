import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Tipos de documento de identidad que acepta Core para el empleado directo.
const List<String> tiposDocumentoEmpleado = ['CC', 'CE', 'PASSPORT'];

/// Peso máximo de la copia del documento de identidad (decisión del PO, RF-05).
const int maxBytesDocumentoIdentidad = 5 * 1024 * 1024;

/// Copia del documento de identidad (PDF, JPG o PNG, hasta 5 MB).
class DocumentoIdentidad extends Equatable {
  const DocumentoIdentidad({required this.nombre, required this.bytes});

  final String nombre;
  final Uint8List bytes;

  /// MIME según la extensión, o `null` si no es PDF, JPG ni PNG.
  String? get tipoContenido {
    final n = nombre.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    return null;
  }

  @override
  List<Object?> get props => [nombre, bytes.length];
}

/// Datos de entrada para registrar un empleado directo del tenant (US-02.1.5 / SCRUM-850 / SCRUM-1376).
/// Obligatorios por decisión del PO: nombre, tipo y número de documento, correo, teléfono, categorías y la copia
/// del documento de identidad.
class NuevoEmpleadoDirecto extends Equatable {
  const NuevoEmpleadoDirecto({
    required this.email,
    required this.password,
    required this.nombreCompleto,
    required this.categoriaIds,
    required this.telefono,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.documento,
  });

  final String email;
  final String password;
  final String nombreCompleto;
  final List<String> categoriaIds;
  final String telefono;
  final String tipoDocumento;
  final String numeroDocumento;
  final DocumentoIdentidad documento;

  @override
  List<Object?> get props => [
    email,
    password,
    nombreCompleto,
    categoriaIds,
    telefono,
    tipoDocumento,
    numeroDocumento,
    documento,
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
    // Core responde `{ employee: {...} }`; se conserva `data` por compatibilidad.
    final data = (json['employee'] is Map<String, dynamic>)
        ? json['employee'] as Map<String, dynamic>
        : (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;
    final rawCats = data['categoriaIds'] ?? data['categorias'] ?? const [];
    return EmpleadoDirectoCreado(
      id: (data['id'] ?? data['aliadoId'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? data['userId'] ?? '').toString(),
      tenantId: (data['tenantId'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      nombreCompleto: (data['fullName'] ?? data['nombreCompleto'] ?? '')
          .toString(),
      estadoVerificacion: (data['estadoVerificacion'] ?? 'VERIFICADO')
          .toString(),
      esEmpleadoDirecto:
          data['esEmpleadoDirecto'] as bool? ??
          (data['tipo'] ?? 'EMPLEADO_DIRECTO') == 'EMPLEADO_DIRECTO',
      categoriaIds: rawCats is List
          ? rawCats.map((e) => e.toString()).toList()
          : const [],
      telefono: (data['phone'] ?? data['telefono'])?.toString(),
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
