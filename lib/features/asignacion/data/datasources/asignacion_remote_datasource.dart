import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/network/gateway_client.dart';

/// Acceso crudo a Supabase. Ni `tenant_id` ni `aliado_id` viajan desde la
/// app: las RPC los derivan de `auth.uid()`
/// (migración 005_aceptar_rechazar_solicitud.sql).
abstract interface class AsignacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listar();
  Future<Map<String, dynamic>> aceptar(String solicitudId);
  Future<void> rechazar(String solicitudId, String? motivo);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseAsignacionDataSource implements AsignacionRemoteDataSource {
  SupabaseAsignacionDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _client.rpc('listar_solicitudes_aliado');
    if (res is! List) {
      return const [];
    }
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async {
    final res = await _client.rpc(
      'aceptar_solicitud',
      params: {'p_solicitud_id': solicitudId},
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw const PostgrestException(
      message: 'Respuesta inesperada del servidor',
    );
  }

  @override
  Future<void> rechazar(String solicitudId, String? motivo) => _client.rpc(
    'rechazar_solicitud',
    params: {'p_solicitud_id': solicitudId, 'p_motivo': motivo},
  );

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}

/// Aceptar y rechazar van a Dispatch por el Gateway (TEC-18 / SCRUM-1465):
/// `POST /api/v1/dispatch/requests/{id}/accept` y `.../reject`. Dispatch
/// toma el tenant y el aliado del JWT verificado; la app solo envía el id
/// de la solicitud y el motivo.
///
/// El listado sigue en la RPC `listar_solicitudes_aliado` de [rpc]: ni Core
/// ni Dispatch exponen todavía la bandeja de ofertas del aliado
/// (`assignments/me` solo devuelve los ids ya asignados). Cuando exista ese
/// endpoint, solo cambia [listar].
class GatewayAsignacionDataSource implements AsignacionRemoteDataSource {
  GatewayAsignacionDataSource(
    this._gateway, {
    required AsignacionRemoteDataSource rpc,
  }) : _rpc = rpc;

  static String rutaAceptar(String solicitudId) =>
      '/api/v1/dispatch/requests/${Uri.encodeComponent(solicitudId)}/accept';
  static String rutaRechazar(String solicitudId) =>
      '/api/v1/dispatch/requests/${Uri.encodeComponent(solicitudId)}/reject';

  final GatewayClient _gateway;
  final AsignacionRemoteDataSource _rpc;

  @override
  Future<List<Map<String, dynamic>>> listar() => _rpc.listar();

  /// Dispatch responde solo `requestId`, `assignedAllyId` y `status`, sin la
  /// dirección que el aliado ve al ganar. Por eso, tras un 200 se relee la
  /// bandeja y se devuelve la solicitud ya asignada. Si no aparece (bandeja
  /// caída o desfasada), se devuelve lo mínimo para marcarla como propia:
  /// la aceptación ya quedó confirmada en el servidor y no se reporta como
  /// error.
  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async {
    await _gateway.postJson(rutaAceptar(solicitudId), const {});
    try {
      for (final s in await _rpc.listar()) {
        if (s['id'] == solicitudId) {
          return s;
        }
      }
    } catch (_) {
      // La aceptación ya se confirmó; la relectura es solo para mostrarla.
    }
    return {'id': solicitudId, 'estado': 'ASIGNADA', 'es_mia': true};
  }

  @override
  Future<void> rechazar(String solicitudId, String? motivo) =>
      _gateway.postJson(rutaRechazar(solicitudId), {'motivo': ?motivo});

  @override
  String? get tenantIdSesion => _rpc.tenantIdSesion;
}
