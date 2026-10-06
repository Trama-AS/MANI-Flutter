import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/utils/generador_id.dart';

/// Devuelve el JWT de la sesión actual, o `null` si no hay sesión.
typedef TokenProvider = Future<String?> Function();

/// Callback invocado cuando el Gateway responde 401. Devuelve `true` si
/// se logró refrescar la sesión y se debe reintentar la petición, o `false`
/// si el refresco falló.
typedef TokenRefreshCallback = Future<bool> Function();

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
/// Soporta:
/// - Verbos HTTP completos: `get`, `postJson`, `postMultipart`, `put`, `patch`, `delete`.
/// - Parámetros de consulta (`queryParameters`).
/// - Reintentos con backoff exponencial para operaciones idempotentes (GET o con
///   cabecera `Idempotency-Key` / `X-Idempotency-Key`) ante caídas de red,
///   timeouts y errores del gateway (502, 503, 504).
/// - Manejo y refresco transparente de sesión ante 401 vía [onTokenExpired].
/// - Trazabilidad y logs estructurados vía [StructuredLogger].
class GatewayClient {
  GatewayClient({
    required String baseUrl,
    required TokenProvider tokenProvider,
    http.Client? httpClient,
    String Function()? correlationId,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(milliseconds: 300),
    this.retryMultiplier = 2.0,
    TokenRefreshCallback? onTokenExpired,
    StructuredLogger? logger,
  }) : _baseUri = Uri.parse(baseUrl),
       _tokenProvider = tokenProvider,
       _http = httpClient ?? http.Client(),
       _correlationId = correlationId ?? nuevoUuid,
       _onTokenExpired = onTokenExpired,
       _logger = logger ?? StructuredLogger(canal: 'gateway_client');

  static const headerCorrelationId = 'X-Correlation-ID';
  static const headerIdempotencyKey = 'Idempotency-Key';
  static const headerAltIdempotencyKey = 'X-Idempotency-Key';

  final Uri _baseUri;
  final TokenProvider _tokenProvider;
  final http.Client _http;
  final String Function() _correlationId;
  final Duration timeout;
  final int maxRetries;
  final Duration initialRetryDelay;
  final double retryMultiplier;
  final TokenRefreshCallback? _onTokenExpired;
  final StructuredLogger? _logger;

  /// Ejecuta una petición GET contra [path], soportando [queryParameters].
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path, queryParameters);
    return _ejecutar(
      metodo: 'GET',
      uri: uri,
      crearRequest: () => http.Request('GET', uri),
      headers: headers,
    );
  }

  /// Ejecuta una petición POST con cuerpo JSON codificado.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path);
    final encoded = jsonEncode(body);
    return _ejecutar(
      metodo: 'POST',
      uri: uri,
      crearRequest: () => http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..body = encoded,
      headers: headers,
    );
  }

  /// Ejecuta una petición POST multipart con campos de formulario y archivos binarios.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> campos,
    List<ArchivoMultipart> archivos = const [],
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path);
    return _ejecutar(
      metodo: 'POST',
      uri: uri,
      crearRequest: () => http.MultipartRequest('POST', uri)
        ..fields.addAll(campos)
        ..files.addAll([
          for (final a in archivos)
            http.MultipartFile.fromBytes(a.campo, a.bytes, filename: a.nombre),
        ]),
      headers: headers,
    );
  }

  /// Ejecuta una petición PUT con cuerpo JSON opcional.
  Future<Map<String, dynamic>> put(
    String path,
    dynamic body, {
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path);
    return _ejecutar(
      metodo: 'PUT',
      uri: uri,
      crearRequest: () {
        final req = http.Request('PUT', uri);
        if (body != null) {
          req.headers['Content-Type'] = 'application/json; charset=utf-8';
          req.body = body is String ? body : jsonEncode(body);
        }
        return req;
      },
      headers: headers,
    );
  }

  /// Ejecuta una petición PATCH con cuerpo JSON opcional.
  Future<Map<String, dynamic>> patch(
    String path,
    dynamic body, {
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path);
    return _ejecutar(
      metodo: 'PATCH',
      uri: uri,
      crearRequest: () {
        final req = http.Request('PATCH', uri);
        if (body != null) {
          req.headers['Content-Type'] = 'application/json; charset=utf-8';
          req.body = body is String ? body : jsonEncode(body);
        }
        return req;
      },
      headers: headers,
    );
  }

  /// Ejecuta una petición DELETE contra [path].
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    dynamic body,
    Map<String, String> headers = const {},
  }) {
    final uri = _resolver(path, queryParameters);
    return _ejecutar(
      metodo: 'DELETE',
      uri: uri,
      crearRequest: () {
        final req = http.Request('DELETE', uri);
        if (body != null) {
          req.headers['Content-Type'] = 'application/json; charset=utf-8';
          req.body = body is String ? body : jsonEncode(body);
        }
        return req;
      },
      headers: headers,
    );
  }

  Uri _resolver(String path, [Map<String, dynamic>? queryParameters]) {
    final base = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    final uriPath = Uri.parse(path);
    final cleanPath = uriPath.path.startsWith('/')
        ? uriPath.path
        : '/${uriPath.path}';
    final fullPath = '$base$cleanPath';

    final Map<String, String> mergedQueries = {
      ..._baseUri.queryParameters,
      ...uriPath.queryParameters,
    };
    if (queryParameters != null) {
      for (final entry in queryParameters.entries) {
        if (entry.value != null) {
          mergedQueries[entry.key] = entry.value.toString();
        }
      }
    }

    return _baseUri.replace(
      path: fullPath,
      queryParameters: mergedQueries.isNotEmpty ? mergedQueries : null,
    );
  }

  bool _esIdempotente(String metodo, Map<String, String> headers) {
    if (metodo.toUpperCase() == 'GET' || metodo.toUpperCase() == 'HEAD') {
      return true;
    }
    return headers.keys.any((k) {
      final lower = k.toLowerCase();
      return lower == 'idempotency-key' || lower == 'x-idempotency-key';
    });
  }

  bool _esStatusReintentable(int statusCode) =>
      statusCode == 502 || statusCode == 503 || statusCode == 504;

  Duration _calcularBackoff(int intento) {
    final delayMs =
        (initialRetryDelay.inMilliseconds * pow(retryMultiplier, intento))
            .round();
    return Duration(milliseconds: delayMs);
  }

  Future<Map<String, dynamic>> _ejecutar({
    required String metodo,
    required Uri uri,
    required http.BaseRequest Function() crearRequest,
    required Map<String, String> headers,
  }) async {
    final correlationId = _correlationId();
    final esIdempotente = _esIdempotente(metodo, headers);
    final reintentosMaximos = esIdempotente ? maxRetries : 0;

    int intento = 0;
    bool yaRefrescoToken = false;

    while (true) {
      final request = crearRequest();
      request.headers.addAll(headers);
      request.headers['Accept'] = 'application/json';
      request.headers[headerCorrelationId] = correlationId;

      final token = await _tokenProvider();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final sw = Stopwatch()..start();
      _logger?.info(
        'HTTP $metodo ${uri.path}',
        traceId: correlationId,
        extra: {
          'method': metodo,
          'path': uri.path,
          'attempt': intento + 1,
          'query': uri.query.isNotEmpty ? uri.query : null,
        },
      );

      http.Response response;
      try {
        final streamed = await _http.send(request).timeout(timeout);
        response = await http.Response.fromStream(streamed).timeout(timeout);
      } on Object catch (error) {
        sw.stop();
        final esReintentable =
            esIdempotente &&
            (error is http.ClientException || error is TimeoutException);

        if (esReintentable && intento < reintentosMaximos) {
          final delay = _calcularBackoff(intento);
          _logger?.info(
            'Reintentando HTTP $metodo ${uri.path} tras error de red o timeout (intento ${intento + 1}/$reintentosMaximos)',
            traceId: correlationId,
            extra: {
              'method': metodo,
              'path': uri.path,
              'retry_delay_ms': delay.inMilliseconds,
              'error': error.toString(),
            },
          );
          intento++;
          if (delay > Duration.zero) await Future.delayed(delay);
          continue;
        }

        _logger?.error(
          'HTTP $metodo ${uri.path} falló sin respuesta',
          traceId: correlationId,
          extra: {
            'method': metodo,
            'path': uri.path,
            'duration_ms': sw.elapsedMilliseconds,
            'error': error.toString(),
          },
        );

        if (error is TimeoutException) {
          throw GatewayException(
            message:
                'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
            correlationId: correlationId,
          );
        }
        if (error is http.ClientException) {
          throw GatewayException(
            message: 'No pudimos conectar con el servidor. Revisa tu conexión.',
            correlationId: correlationId,
          );
        }
        throw GatewayException(
          message: 'Error inesperado de comunicación: $error',
          correlationId: correlationId,
        );
      }

      sw.stop();
      final cuerpo = _decodificar(response);

      // 2xx Exitoso
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logger?.info(
          'HTTP $metodo ${uri.path} -> ${response.statusCode} (${sw.elapsedMilliseconds}ms)',
          traceId: correlationId,
          extra: {
            'method': metodo,
            'path': uri.path,
            'status_code': response.statusCode,
            'duration_ms': sw.elapsedMilliseconds,
          },
        );
        return cuerpo ?? const {};
      }

      // 401: Intento de refresco de token si no se ha refrescado en esta llamada
      if (response.statusCode == 401 &&
          _onTokenExpired != null &&
          !yaRefrescoToken) {
        yaRefrescoToken = true;
        _logger?.info(
          'Token expirado (401). Intentando refrescar sesión...',
          traceId: correlationId,
        );
        final refrescado = await _onTokenExpired();
        if (refrescado) {
          _logger?.info(
            'Sesión refrescada con éxito. Reintentando HTTP $metodo ${uri.path}...',
            traceId: correlationId,
          );
          continue;
        }
      }

      // Reintento de status de Gateway (502, 503, 504) para peticiones idempotentes
      if (esIdempotente &&
          _esStatusReintentable(response.statusCode) &&
          intento < reintentosMaximos) {
        final delay = _calcularBackoff(intento);
        _logger?.info(
          'Reintentando HTTP $metodo ${uri.path} tras status ${response.statusCode} (intento ${intento + 1}/$reintentosMaximos)',
          traceId: correlationId,
          extra: {
            'method': metodo,
            'path': uri.path,
            'status_code': response.statusCode,
            'retry_delay_ms': delay.inMilliseconds,
          },
        );
        intento++;
        if (delay > Duration.zero) await Future.delayed(delay);
        continue;
      }

      // Error final no reintentable
      _logger?.error(
        'HTTP $metodo ${uri.path} respondió error ${response.statusCode}',
        traceId: correlationId,
        extra: {
          'method': metodo,
          'path': uri.path,
          'status_code': response.statusCode,
          'duration_ms': sw.elapsedMilliseconds,
        },
      );

      throw GatewayException.fromStatus(
        response.statusCode,
        detalle: _detalle(cuerpo),
        correlationId: correlationId,
      );
    }
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
