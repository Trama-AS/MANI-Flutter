import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/utils/generador_id.dart';

/// Devuelve el JWT de la sesión actual, o `null` si no hay sesión.
typedef TokenProvider = Future<String?> Function();

/// Archivo que viaja como parte de una petición multipart.
class ArchivoMultipart {
  const ArchivoMultipart({
    required this.campo,
    required this.nombre,
    required this.bytes,
  });

  final String campo;
  final String nombre;
  final Uint8List bytes;
}

/// Cliente HTTP único contra el NGINX API Gateway (ADR-0019).
///
/// Sustituye a `SupabaseClient` en los datasources migrados: todas las
/// peticiones salen hacia [baseUrl] (nunca a los puertos internos de los
/// servicios) con `Authorization: Bearer <JWT>` si hay sesión y un
/// `X-Correlation-ID` nuevo por petición. Las respuestas no 2xx y los fallos
/// de red se lanzan como [GatewayException].
///
/// No reintenta: las operaciones que lo usan hoy (registro) no son
/// idempotentes. La política de reintentos queda para CFG-34.
class GatewayClient {
  GatewayClient({
    required String baseUrl,
    required TokenProvider tokenProvider,
    http.Client? httpClient,
    String Function()? correlationId,
    this.timeout = const Duration(seconds: 30),
  }) : _baseUri = Uri.parse(baseUrl),
       _tokenProvider = tokenProvider,
       _http = httpClient ?? http.Client(),
       _correlationId = correlationId ?? nuevoUuid;

  static const headerCorrelationId = 'X-Correlation-ID';

  final Uri _baseUri;
  final TokenProvider _tokenProvider;
  final http.Client _http;
  final String Function() _correlationId;
  final Duration timeout;

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request('POST', _resolver(path))
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode(body);
    return _enviar(request, headers);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> campos,
    List<ArchivoMultipart> archivos = const [],
    Map<String, String> headers = const {},
  }) async {
    final request = http.MultipartRequest('POST', _resolver(path))
      ..fields.addAll(campos)
      ..files.addAll([
        for (final a in archivos)
          http.MultipartFile.fromBytes(a.campo, a.bytes, filename: a.nombre),
      ]);
    return _enviar(request, headers);
  }

  Uri _resolver(String path) {
    final base = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$base$path');
  }

  Future<Map<String, dynamic>> _enviar(
    http.BaseRequest request,
    Map<String, String> headers,
  ) async {
    final correlationId = _correlationId();
    request.headers.addAll(headers);
    request.headers['Accept'] = 'application/json';
    request.headers[headerCorrelationId] = correlationId;
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw GatewayException(
        message:
            'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
        correlationId: correlationId,
      );
    } on http.ClientException {
      throw GatewayException(
        message: 'No pudimos conectar con el servidor. Revisa tu conexión.',
        correlationId: correlationId,
      );
    }

    final cuerpo = _decodificar(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return cuerpo ?? const {};
    }
    throw GatewayException.fromStatus(
      response.statusCode,
      detalle: _detalle(cuerpo),
      correlationId: correlationId,
    );
  }

  Map<String, dynamic>? _decodificar(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return json is Map<String, dynamic> ? json : {'data': json};
    } on FormatException {
      return null;
    }
  }

  String? _detalle(Map<String, dynamic>? cuerpo) {
    final valor = cuerpo?['message'] ?? cuerpo?['error'];
    return valor is String && valor.trim().isNotEmpty ? valor : null;
  }
}
