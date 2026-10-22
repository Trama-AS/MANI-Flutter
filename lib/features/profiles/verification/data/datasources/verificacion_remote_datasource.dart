import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase. `tenant_id` NUNCA se envía: las RPC lo derivan
/// de `auth.uid()` (migración 002_verificacion_aliados.sql).
abstract interface class VerificacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarAliados();
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId);
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  );
  Future<String> urlFirmada(String rutaStorage);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseVerificacionDataSource implements VerificacionRemoteDataSource {
  SupabaseVerificacionDataSource(
    this._client, {
    this.bucket = 'kyc',
    this.vigenciaUrl = const Duration(minutes: 5),
  });

  final SupabaseClient _client;

  /// Bucket privado donde el registro de aliados guarda los documentos KYC.
  final String bucket;

  /// Vida de la URL firmada: corta, porque los documentos son datos sensibles.
  final Duration vigenciaUrl;

  @override
  Future<List<Map<String, dynamic>>> listarAliados() async {
    final res = await _client.rpc('listar_aliados_verificacion');
    if (res is! List) return const [];
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId) async =>
      _comoMapa(
        await _client.rpc(
          'obtener_aliado_verificacion',
          params: {'p_aliado_id': aliadoId},
        ),
      );

  @override
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  ) async => _comoMapa(
    await _client.rpc(
      'resolver_verificacion_aliado',
      params: {
        'p_aliado_id': aliadoId,
        'p_decision': decision,
        'p_motivo': motivo,
      },
    ),
  );

  @override
  Future<String> urlFirmada(String rutaStorage) {
    // El registro guarda rutas con el bucket como prefijo ("kyc/<tenant>/…").
    final prefijo = '$bucket/';
    final ruta = rutaStorage.startsWith(prefijo)
        ? rutaStorage.substring(prefijo.length)
        : rutaStorage;
    return _client.storage
        .from(bucket)
        .createSignedUrl(ruta, vigenciaUrl.inSeconds);
  }

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }

  static Map<String, dynamic> _comoMapa(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw const PostgrestException(
      message: 'Respuesta inesperada del servidor',
    );
  }
}
