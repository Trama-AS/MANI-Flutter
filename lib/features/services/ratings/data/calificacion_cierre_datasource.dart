import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/calificacion_cierre_modelos.dart';

/// Fuente de datos del Módulo C (M-08: Calificación, Cierre, Penalización e
/// Historial), desacoplada para pruebas unitarias y de integración.
abstract interface class FuenteModuloM08 {
  /// SCRUM-874 (Cliente -> Aliado) y SCRUM-875 (Aliado -> Cliente).
  Future<ResumenCalificacionesSolicitud> registrarCalificacion({
    required String solicitudId,
    required int puntaje,
    String? comentario,
  });

  /// SCRUM-1418 / SCRUM-874 / SCRUM-875: consulta las calificaciones y el
  /// estado de cierre de la solicitud.
  Future<ResumenCalificacionesSolicitud> obtenerCalificaciones(
    String solicitudId,
  );

  /// SCRUM-1418: declara el cierre definitivo de la solicitud (exige ambas
  /// calificaciones).
  Future<EstadoCierreSolicitud> cerrarSolicitud(String solicitudId);

  /// SCRUM-876: listado de aliados del tenant con su calificación agregada.
  Future<List<CalificacionAgregadaAliado>> listarCalificacionesAliados({
    String? categoriaId,
    String? zonaId,
  });

  /// SCRUM-878: vista previa de penalización antes de cancelar la solicitud.
  Future<VistaPreviaPenalizacion> previsualizarCancelacion(String solicitudId);

  /// SCRUM-879: historial cronológico de servicios del cliente.
  Future<List<RegistroHistorialServicio>> listarHistorialCliente();

  /// SCRUM-880: historial cronológico de trabajos del aliado.
  Future<List<RegistroHistorialServicio>> listarHistorialAliado();
}

/// Implementación HTTP vía API Gateway (`/api/v1/core/...`, directriz T6).
class GatewayFuenteModuloM08 implements FuenteModuloM08 {
  GatewayFuenteModuloM08(this._gateway);

  static String rutaCalificacionesSolicitud(String solicitudId) =>
      '/api/v1/core/solicitudes/${Uri.encodeComponent(solicitudId)}/calificaciones';

  static String rutaCerrarSolicitud(String solicitudId) =>
      '/api/v1/core/solicitudes/${Uri.encodeComponent(solicitudId)}/cerrar';

  static const rutaCalificacionesAliados =
      '/api/v1/core/aliados/calificaciones';

  static String rutaPreviewCancelacion(String solicitudId) =>
      '/api/v1/core/solicitudes/me/${Uri.encodeComponent(solicitudId)}/cancelacion-preview';

  static const rutaHistorialCliente = '/api/v1/core/solicitudes/me/historial';
  static const rutaHistorialAliado = '/api/v1/core/allies/me/history';

  final GatewayClient _gateway;

  @override
  Future<ResumenCalificacionesSolicitud> registrarCalificacion({
    required String solicitudId,
    required int puntaje,
    String? comentario,
  }) async {
    try {
      final res = await _gateway
          .postJson(rutaCalificacionesSolicitud(solicitudId), {
            'puntaje': puntaje,
            if (comentario != null && comentario.trim().isNotEmpty)
              'comentario': comentario.trim(),
          });
      final califRaw = res['calificacion'];
      final cierreRaw = res['cierre'];
      if (califRaw is! Map || cierreRaw is! Map) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "calificacion" o "cierre"',
        );
      }
      final calif = CalificacionServicio.fromJson(
        Map<String, dynamic>.from(califRaw),
      );
      final cierre = EstadoCierreSolicitud.fromJson(
        Map<String, dynamic>.from(cierreRaw),
      );
      return ResumenCalificacionesSolicitud(
        solicitudId: solicitudId,
        estado: cierre.estadoSolicitud,
        cierre: cierre,
        clienteAAliado: calif.esDeCliente ? calif : null,
        aliadoACliente: calif.esDeAliado ? calif : null,
      );
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<ResumenCalificacionesSolicitud> obtenerCalificaciones(
    String solicitudId,
  ) async {
    try {
      final res = await _gateway.get(rutaCalificacionesSolicitud(solicitudId));
      return ResumenCalificacionesSolicitud.fromJson(res);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<EstadoCierreSolicitud> cerrarSolicitud(String solicitudId) async {
    try {
      final res = await _gateway.postJson(rutaCerrarSolicitud(solicitudId), {});
      final cierre = res['cierre'];
      if (cierre is! Map) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "cierre"',
        );
      }
      return EstadoCierreSolicitud.fromJson(Map<String, dynamic>.from(cierre));
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<List<CalificacionAgregadaAliado>> listarCalificacionesAliados({
    String? categoriaId,
    String? zonaId,
  }) async {
    try {
      final query = <String, String>{
        if (categoriaId != null && categoriaId.trim().isNotEmpty)
          'categoriaId': categoriaId.trim(),
        if (zonaId != null && zonaId.trim().isNotEmpty) 'zonaId': zonaId.trim(),
      };
      final ruta = query.isEmpty
          ? rutaCalificacionesAliados
          : Uri(
              path: rutaCalificacionesAliados,
              queryParameters: query,
            ).toString();
      final res = await _gateway.get(ruta);
      final lista = res['aliados'];
      if (lista is! List) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "aliados"',
        );
      }
      return lista
          .whereType<Map>()
          .map(
            (e) => CalificacionAgregadaAliado.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<VistaPreviaPenalizacion> previsualizarCancelacion(
    String solicitudId,
  ) async {
    try {
      final res = await _gateway.get(rutaPreviewCancelacion(solicitudId));
      return VistaPreviaPenalizacion.fromJson(res);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<List<RegistroHistorialServicio>> listarHistorialCliente() async {
    try {
      final res = await _gateway.get(rutaHistorialCliente);
      final lista = res['historial'];
      if (lista is! List) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "historial"',
        );
      }
      return lista
          .whereType<Map>()
          .map(
            (e) => RegistroHistorialServicio.desdeHistorialCliente(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  @override
  Future<List<RegistroHistorialServicio>> listarHistorialAliado() async {
    try {
      final res = await _gateway.get(rutaHistorialAliado);
      final lista = res['trabajos'] ?? res['historial'];
      if (lista is! List) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "trabajos"',
        );
      }
      return lista
          .whereType<Map>()
          .map(
            (e) => RegistroHistorialServicio.desdeHistorialAliado(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
  }

  static ModuloM08Failure mapearGateway(GatewayException e) {
    final codigo = e.cuerpo?['code'] as String?;
    final status = e.statusCode;
    if (status == null) {
      return ModuloM08Failure(ModuloM08ErrorTipo.sinConexion, e.message);
    }
    if (codigo == 'MANI-CAL-422P') {
      return ModuloM08Failure(ModuloM08ErrorTipo.puntajeInvalido, e.message);
    }
    if (codigo == 'MANI-CAL-422C') {
      return ModuloM08Failure(ModuloM08ErrorTipo.comentarioInvalido, e.message);
    }
    if (codigo == 'MANI-CAL-409D') {
      return ModuloM08Failure(
        ModuloM08ErrorTipo.calificacionDuplicada,
        e.message,
      );
    }
    if (codigo == 'MANI-CAL-409E') {
      return ModuloM08Failure(
        ModuloM08ErrorTipo.servicioNoEjecutado,
        e.message,
      );
    }
    if (codigo == 'MANI-CAL-409C') {
      return ModuloM08Failure(ModuloM08ErrorTipo.cierreIncompleto, e.message);
    }
    if (status == 401 ||
        codigo == 'MANI-CAL-401' ||
        codigo == 'MANI-HIS-401' ||
        codigo == 'MANI-PEN-401') {
      return ModuloM08Failure(ModuloM08ErrorTipo.sinSesion, e.message);
    }
    if (status == 403 ||
        (codigo != null &&
            (codigo.startsWith('MANI-CAL-403') ||
                codigo.startsWith('MANI-HIS-403') ||
                codigo.startsWith('MANI-PEN-403')))) {
      return ModuloM08Failure(ModuloM08ErrorTipo.sinPermiso, e.message);
    }
    if (status == 404 ||
        codigo == 'MANI-CAL-404' ||
        codigo == 'MANI-CAL-404A' ||
        codigo == 'MANI-HIS-404') {
      return ModuloM08Failure(ModuloM08ErrorTipo.noEncontrado, e.message);
    }
    if (status >= 500) {
      return ModuloM08Failure(
        ModuloM08ErrorTipo.servicioNoDisponible,
        e.message,
      );
    }
    return ModuloM08Failure(ModuloM08ErrorTipo.desconocido, e.message);
  }
}
