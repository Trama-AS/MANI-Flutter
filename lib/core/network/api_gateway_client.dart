import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/generador_id.dart';

/// Excepción emitida cuando el API Gateway rechaza una petición
/// por falta de autenticación, token inválido o ausencia del claim de tenant.
class ApiGatewayAuthException implements Exception {
  final int statusCode;
  final String error;
  final String message;
  final String? correlationId;

  const ApiGatewayAuthException({
    required this.statusCode,
    required this.error,
    required this.message,
    this.correlationId,
  });

  @override
  String toString() =>
      'ApiGatewayAuthException($statusCode): $message (error: $error, correlationId: $correlationId)';
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
  final http.Client _httpClient;

  ApiGatewayClient({
    String? baseUrl,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
  }) : baseUrl = baseUrl ?? 'http://localhost:80',
       _supabaseClient = supabaseClient,
       _httpClient = httpClient ?? http.Client();

  /// Obtiene el token JWT actual emitido por Supabase Auth.
  String? get currentAccessToken {
    try {
      final client = _supabaseClient ?? Supabase.instance.client;
      return client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Ejecuta una petición HTTP al API Gateway con inyección de JWT y Correlation ID.
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? tenantSlug,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-Correlation-ID': nuevoUuid(),
    };

    if (tenantSlug != null && tenantSlug.isNotEmpty) {
      requestHeaders['X-Tenant-Slug'] = tenantSlug;
    }

    final token = currentAccessToken;
    if (token != null && token.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $token';
    }

    if (headers != null) {
      requestHeaders.addAll(headers);
    }

    final http.Response response;
    final encodedBody = body != null ? jsonEncode(body) : null;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(uri, headers: requestHeaders);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        );
        break;
      default:
        throw UnsupportedError('Método HTTP no soportado: $method');
    }

    Map<String, dynamic> responseJson = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          responseJson = decoded;
        } else {
          responseJson = {'data': decoded};
        }
      } catch (_) {
        responseJson = {'raw': response.body};
      }
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiGatewayAuthException(
        statusCode: response.statusCode,
        error: responseJson['error']?.toString() ?? 'UNAUTHORIZED',
        message:
            responseJson['message']?.toString() ??
            'Petición rechazada en el API Gateway',
        correlationId:
            response.headers['x-correlation-id'] ??
            responseJson['correlationId']?.toString(),
      );
    }

    if (response.statusCode >= 400) {
      throw http.ClientException(
        'Error ${response.statusCode}: ${responseJson['message'] ?? response.body}',
        uri,
      );
    }

    return responseJson;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
  }) {
    return sendRequest(method: 'GET', path: path, headers: headers);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? tenantSlug,
  }) {
    return sendRequest(
      method: 'POST',
      path: path,
      body: body,
      headers: headers,
      tenantSlug: tenantSlug,
    );
  }

  void close() {
    _httpClient.close();
  }
}
