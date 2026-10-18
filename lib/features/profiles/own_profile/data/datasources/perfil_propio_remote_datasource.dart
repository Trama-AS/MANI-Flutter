import 'dart:typed_data';

import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/own_profile/domain/entities/perfil_propio.dart';

abstract interface class PerfilPropioRemoteDataSource {
  Future<PerfilPropio> obtenerPerfilPropio();

  Future<PerfilPropio> actualizarPerfilPropio({
    required String fullName,
    required String phone,
    required String address,
  });

  Future<PerfilPropio> subirFotoPerfil({
    required String nombreArchivo,
    required Uint8List bytes,
  });
}

/// Adaptador HTTP hacia el NGINX API Gateway para `US-02.3.1` (`SCRUM-854`).
class GatewayPerfilPropioDataSource implements PerfilPropioRemoteDataSource {
  GatewayPerfilPropioDataSource(this._gatewayClient);

  final GatewayClient _gatewayClient;

  static const _formatosSoportados = ['.png', '.jpg', '.jpeg', '.webp'];

  static bool esFormatoImagenSoportado(String nombreArchivo) {
    final lower = nombreArchivo.trim().toLowerCase();
    return _formatosSoportados.any(lower.endsWith);
  }

  @override
  Future<PerfilPropio> obtenerPerfilPropio() async {
    final res = await _gatewayClient.get('/api/v1/profiles/me');
    return PerfilPropio.fromJson(res);
  }

  @override
  Future<PerfilPropio> actualizarPerfilPropio({
    required String fullName,
    required String phone,
    required String address,
  }) async {
    final res = await _gatewayClient.patch('/api/v1/profiles/me', {
      'fullName': fullName.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
    });
    return PerfilPropio.fromJson(res);
  }

  @override
  Future<PerfilPropio> subirFotoPerfil({
    required String nombreArchivo,
    required Uint8List bytes,
  }) async {
    if (!esFormatoImagenSoportado(nombreArchivo)) {
      throw ArgumentError(
        'Formato de imagen no soportado. Usa PNG, JPG, JPEG o WEBP.',
      );
    }
    final res = await _gatewayClient.postMultipart(
      '/api/v1/profiles/me/photo',
      campos: const {},
      archivos: [
        ArchivoMultipart(campo: 'photo', nombre: nombreArchivo, bytes: bytes),
      ],
    );
    return PerfilPropio.fromJson(res);
  }
}
