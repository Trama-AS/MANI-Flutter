import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/session/rol_usuario.dart';

/// Usuario de un tenant con el que el administrador de plataforma puede actuar.
class UsuarioTenant extends Equatable {
  const UsuarioTenant({
    required this.id,
    required this.email,
    required this.rol,
    this.estado = '',
  });

  factory UsuarioTenant.fromJson(Map<String, dynamic> json) => UsuarioTenant(
    id: '${json['id']}',
    email: (json['email'] as String?) ?? '',
    rol: (json['rol'] as String?) ?? '',
    estado: (json['estado'] as String?) ?? '',
  );

  final String id;
  final String email;

  /// Rol en la base (`CLIENTE`, `ALIADO`, `ADMIN_TENANT`).
  final String rol;
  final String estado;

  /// Rol con el que la app pinta el menú cuando se actúa como este usuario.
  RolUsuario get rolApp => switch (rol.toUpperCase()) {
    'CLIENTE' => RolUsuario.cliente,
    'ALIADO' => RolUsuario.aliado,
    'ADMIN_TENANT' => RolUsuario.adminTenant,
    _ => RolUsuario.desconocido,
  };

  @override
  List<Object?> get props => [id, email, rol, estado];
}

/// Consulta los usuarios de un tenant (`GET /api/v1/core/tenants/:id/usuarios`,
/// solo para el permiso de plataforma, SCRUM-901).
abstract interface class FuenteUsuariosTenant {
  Future<List<UsuarioTenant>> listar(String tenantId);
}

class GatewayFuenteUsuariosTenant implements FuenteUsuariosTenant {
  GatewayFuenteUsuariosTenant(this._gateway);

  final GatewayClient _gateway;

  static String ruta(String tenantId) =>
      '/api/v1/core/tenants/${Uri.encodeComponent(tenantId)}/usuarios';

  @override
  Future<List<UsuarioTenant>> listar(String tenantId) async => [
    for (final u
        in ((await _gateway.get(ruta(tenantId)))['usuarios'] as List? ??
            const []))
      if (u is Map) UsuarioTenant.fromJson(Map<String, dynamic>.from(u)),
  ];
}

/// Contexto del administrador de plataforma (SCRUM-901): el tenant que
/// administra y, si lo eligió, el usuario de ese tenant con el que actúa.
///
/// La app lo envía en cada petición (cabeceras `X-Mani-Tenant` y
/// `X-Mani-Actuar-Como`); Core y Dispatch las validan y solo las aceptan para
/// ese permiso. Sin tenant elegido, administra el suyo.
class ContextoPlataforma extends ChangeNotifier {
  String? _tenantId;
  String? _tenantNombre;
  UsuarioTenant? _actuarComo;
  int _version = 0;

  String? get tenantId => _tenantId;
  String? get tenantNombre => _tenantNombre;
  UsuarioTenant? get actuarComo => _actuarComo;

  /// Cambia con cada contexto nuevo: la app la usa para recargar la pantalla.
  int get version => _version;

  /// Rol de las pantallas que se muestran: el del usuario con el que actúa, o
  /// el de administrador del tenant si no actúa como nadie.
  RolUsuario get rolEfectivo => _actuarComo?.rolApp ?? RolUsuario.adminTenant;

  Map<String, String> get cabeceras => {
    'X-Mani-Tenant': ?_tenantId,
    'X-Mani-Actuar-Como': ?_actuarComo?.id,
  };

  /// Administra [tenantId]; deja de actuar como otro usuario.
  void elegirTenant(String tenantId, String nombre) {
    if (_tenantId == tenantId && _actuarComo == null) return;
    _tenantId = tenantId;
    _tenantNombre = nombre;
    _actuarComo = null;
    _cambio();
  }

  /// Actúa como [usuario] del tenant elegido; con null, vuelve a administrar.
  void actuarComoUsuario(UsuarioTenant? usuario) {
    if (_actuarComo == usuario) return;
    _actuarComo = usuario;
    _cambio();
  }

  /// Al cerrar sesión: nada del contexto anterior pasa a la siguiente.
  void limpiar() {
    if (_tenantId == null && _actuarComo == null) return;
    _tenantId = null;
    _tenantNombre = null;
    _actuarComo = null;
    _cambio();
  }

  void _cambio() {
    _version++;
    notifyListeners();
  }
}
