import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/generador_id.dart';

/// Excepción emitida cuando el API Gateway rechaza una petición
/// por falta de autenticación, token inválido o ausencia del claim de tenant.
class ApiGatewayAuthException implements Exception {
  final int statusCode;
  final String error;
  final String message;
  final String? correlationId;

  ApiGatewayAuthException({
    required this.statusCode,
    required this.error,
    required this.message,
    this.correlationId,
  });

  @override
  String toString() => 'ApiGatewayAuthException($statusCode): $message (error: $error, correlationId: $correlationId)';
}

/// Cliente HTTP para comunicación entre Flutter y el API Gateway NGINX.
///
/// Implementa los lineamientos de CFG-22 / ADR-0018 / ADR-0027:
/// 1. Adjunta automáticamente el token JWT de la sesión activa de Supabase Auth
///    en el encabezado `Authorization: Bearer <JWT>`.
/// 2. Propaga el identificador único `X-Correlation-ID` en cada llamada.
/// 3. Intercepta respuestas HTTP 401/403 del API Gateway cuando un token
///    carece de claims válidos de tenant o ha expirado.
class ApiGatewayClient {
  final String baseUrl;
  final SupabaseClient? _supabaseClient;
  final HttpClient _httpClient;

  ApiGatewayClient({
    String? baseUrl,
    SupabaseClient? supabaseClient,
    HttpClient? httpClient,
  })  : baseUrl = baseUrl ?? 'http://localhost:80',
        _supabaseClient = supabaseClient,
        _httpClient = httpClient ?? HttpClient();

  /// Obtiene el token JWT actual emitido por Supabase Auth
  String? get currentAccessToken {
    try {
      final client = _supabaseClient ?? Supabase.instance.client;
      return client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Ejecuta una petición HTTP al API Gateway
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? tenantSlug,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = await _httpClient.openUrl(method, uri);

    // Encabezados estándar
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    request.headers.set('X-Correlation-ID', nuevoUuid());

    // Si es pre-autenticación y se especifica un slug de tenant (ADR-0018)
    if (tenantSlug != null && tenantSlug.isNotEmpty) {
      request.headers.set('X-Tenant-Slug', tenantSlug);
    }

    // Inyectar JWT emitido por Supabase Auth
    final token = currentAccessToken;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    // Encabezados adicionales si aplican
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

    // Enviar cuerpo si existe
    if (body != null) {
      final jsonBody = jsonEncode(body);
      request.write(jsonBody);
    }

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    Map<String, dynamic> responseJson = {};
    if (responseBody.isNotEmpty) {
      try {
        responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (_) {
        responseJson = {'raw': responseBody};
      }
    }

    // Validación de respuesta del Gateway (CFG-22)
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiGatewayAuthException(
        statusCode: response.statusCode,
        error: responseJson['error']?.toString() ?? 'UNAUTHORIZED',
        message: responseJson['message']?.toString() ?? 'Petición rechazada en el API Gateway',
        correlationId: response.headers.value('x-correlation-id') ?? responseJson['correlationId']?.toString(),
      );
    }

    if (response.statusCode >= 400) {
      throw HttpException(
        'Error ${response.statusCode}: ${responseJson['message'] ?? responseBody}',
        uri: uri,
      );
    }

    return responseJson;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers}) {
    return sendRequest(method: 'GET', path: path, headers: headers);
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, Map<String, String>? headers, String? tenantSlug}) {
    return sendRequest(method: 'POST', path: path, body: body, headers: headers, tenantSlug: tenantSlug);
  }
}
