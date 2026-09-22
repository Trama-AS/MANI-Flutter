import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

typedef LogSink = void Function(String linea);

/// Log JSON estructurado con los campos acordados por el equipo
/// (timestamp, level, service_id, trace_id, tenant_id, message) — mismo
/// formato exigido en el criterio de aceptación de US-03.1.1 y reutilizado
/// por cualquier feature que necesite trazabilidad (coverage, verification…).
/// Nunca registrar datos personales: solo ids, conteos y códigos.
class StructuredLogger {
  StructuredLogger({
    required String canal,
    LogSink? sink,
    this.serviceId = 'mani-flutter',
  }) : _sink = sink ?? ((l) => developer.log(l, name: canal));

  final LogSink _sink;
  final String serviceId;
  static final Random _rnd = Random.secure();

  static String nuevoTraceId() => List.generate(
    16,
    (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void info(
    String message, {
    required String traceId,
    String? tenantId,
    Map<String, Object?> extra = const {},
  }) => _emitir('INFO', message, traceId, tenantId, extra);

  void error(
    String message, {
    required String traceId,
    String? tenantId,
    Map<String, Object?> extra = const {},
  }) => _emitir('ERROR', message, traceId, tenantId, extra);

  void _emitir(
    String level,
    String message,
    String traceId,
    String? tenantId,
    Map<String, Object?> extra,
  ) {
    _sink(
      jsonEncode({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'service_id': serviceId,
        'trace_id': traceId,
        'tenant_id': tenantId,
        'message': message,
        ...extra,
      }),
    );
  }
}
