import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/session/rol_usuario.dart';

/// Un dato del resumen de inicio y la pantalla donde se gestiona.
class IndicadorResumen {
  const IndicadorResumen({
    required this.etiqueta,
    required this.ruta,
    this.valor,
  });

  final String etiqueta;
  final String ruta;

  /// `null` si no se pudo consultar: la tarjeta muestra «—» y sigue usable.
  final String? valor;
}

/// Fuente del resumen de inicio, separada para probar la pantalla sin red.
abstract interface class FuenteResumenInicio {
  Future<List<IndicadorResumen>> cargar(RolUsuario rol);
}

/// Resumen por rol contra Core por el Gateway (US-11.2.3 / SCRUM-1446).
///
/// Solo usa endpoints que ya existen. Cada indicador se consulta aparte y
/// un fallo deja ese valor en `null`, así que un endpoint caído no tumba
/// la pantalla de inicio.
class GatewayResumenInicio implements FuenteResumenInicio {
  GatewayResumenInicio(this._gateway);

  final GatewayClient _gateway;

  @override
  Future<List<IndicadorResumen>> cargar(RolUsuario rol) {
    switch (rol) {
      case RolUsuario.cliente:
        return _cliente();
      case RolUsuario.aliado:
        return _aliado();
      case RolUsuario.adminTenant:
        return _admin();
      case RolUsuario.adminPlataforma:
      case RolUsuario.desconocido:
        return Future.value(const []);
    }
  }

  /// Las sedes salen de `GET /solicitudes/sitios` (MANI-Node#67): Core
  /// resuelve el cliente por el usuario del token y responde a cualquier
  /// cliente activo. `/clients/me/sites` solo encuentra clientes empresa y a
  /// un cliente persona natural le respondía 404.
  Future<List<IndicadorResumen>> _cliente() async {
    final sedes = await _leer(
      '/api/v1/core/solicitudes/sitios',
      (r) => '${_largo(r['sitios']) ?? 0}',
    );
    return [
      IndicadorResumen(
        etiqueta: 'Sedes registradas',
        ruta: '/cliente/sedes',
        valor: sedes,
      ),
    ];
  }

  Future<List<IndicadorResumen>> _aliado() async {
    final categorias = _leer(
      '/api/v1/core/profiles/me/categories',
      (r) => '${_largo(r['data']) ?? 0}',
    );
    final ausencias = _mapa('/api/v1/core/profiles/me/unavailability');
    final cat = await categorias;
    final aus = await ausencias;
    final disponible = aus?['availableNow'];
    return [
      IndicadorResumen(
        etiqueta: 'Categorías que atiendo',
        ruta: '/categories',
        valor: cat,
      ),
      IndicadorResumen(
        etiqueta: 'Estado ahora',
        ruta: '/aliado/disponibilidad',
        valor: disponible is bool
            ? (disponible ? 'Disponible' : 'No disponible')
            : null,
      ),
      IndicadorResumen(
        etiqueta: 'Ausencias programadas',
        ruta: '/aliado/disponibilidad',
        valor: aus == null ? null : '${_largo(aus['data']) ?? 0}',
      ),
    ];
  }

  Future<List<IndicadorResumen>> _admin() async {
    final pendientes = _leer('/api/v1/core/aliados/verificacion', (r) {
      final items = r['data'];
      if (items is! List) return '0';
      final n = items
          .whereType<Map>()
          .where(
            (a) =>
                a['estado_verificacion']?.toString().toUpperCase() ==
                'PENDIENTE',
          )
          .length;
      return '$n';
    });
    final categorias = _leer(
      '/api/v1/core/catalog/categories',
      (r) => '${_largo(r['categories']) ?? 0}',
    );
    return [
      IndicadorResumen(
        etiqueta: 'Aliados por verificar',
        ruta: '/admin/verificacion-aliados',
        valor: await pendientes,
      ),
      IndicadorResumen(
        etiqueta: 'Categorías del catálogo',
        ruta: '/admin/categorias',
        valor: await categorias,
      ),
    ];
  }

  Future<String?> _leer(
    String ruta,
    String Function(Map<String, dynamic>) extraer,
  ) async {
    final r = await _mapa(ruta);
    return r == null ? null : extraer(r);
  }

  Future<Map<String, dynamic>?> _mapa(String ruta) async {
    try {
      return await _gateway.get(ruta);
    } on GatewayException {
      return null;
    }
  }

  static int? _largo(Object? lista) => lista is List ? lista.length : null;
}
