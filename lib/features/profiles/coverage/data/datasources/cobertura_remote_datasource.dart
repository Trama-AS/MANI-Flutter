import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/core/session/tenant_sesion.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a la cobertura del aliado. `tenant_id` y `aliado_id` NUNCA se
/// envían: Core Node los toma del JWT verificado (ADR-0018/0032).
///
/// Las filas conservan la forma que ya leía [ZonaModel] (`id`, `nombre`,
/// `nivel`, `zona_padre_id`, `ancestros`, `tiene_hijas`, `estado`).
abstract interface class CoberturaRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId);
  Future<List<Map<String, dynamic>>> buscarZonas(String ciudadId, String texto);
  Future<List<Map<String, dynamic>>> obtenerMiCobertura();
  Future<List<Map<String, dynamic>>> declararCobertura(List<String> zonaIds);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

/// Todas las operaciones salen por el API Gateway hacia Core Node; ninguna
/// llama RPC ni tablas de Supabase (ADR-0027, SCRUM-1380). Supabase solo se usa
/// para leer la sesión local.
///
/// - Las zonas vienen de `GET /catalog/zones`, el catálogo global y jerárquico.
///   Se descarga completo una vez (se reutiliza [_vigencia]) y la navegación por
///   hijas, los ancestros y la búsqueda por nombre se resuelven en memoria.
/// - La cobertura propia se lee y se reemplaza con `GET`/`PUT
///   /profiles/me/coverage`.
class GatewayCoberturaDataSource implements CoberturaRemoteDataSource {
  GatewayCoberturaDataSource(
    this._gateway, {
    SupabaseClient? sesion,
    DateTime Function()? ahora,
  }) : _sesion = sesion,
       _ahora = ahora ?? DateTime.now;

  static const _rutaZonas = '/api/v1/core/catalog/zones';
  static const _rutaCobertura = '/api/v1/core/profiles/me/coverage';
  static const _vigencia = Duration(minutes: 10);

  final GatewayClient _gateway;
  final SupabaseClient? _sesion;
  final DateTime Function() _ahora;

  _Catalogo? _catalogo;
  DateTime? _cargadoEn;

  @override
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId) async {
    final c = await _cargar();
    final zonas = padreId == null
        ? c.zonas.where((z) => z.nivel == 'CIUDAD' && z.activa)
        : (c.hijas[padreId] ?? const <_Zona>[]).where((z) => z.activa);
    return _ordenadas(zonas).map(c.aFila).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(
    String ciudadId,
    String texto,
  ) async {
    final c = await _cargar();
    final buscado = _plano(texto);
    if (buscado.isEmpty) return const [];
    final coinciden = c.zonas.where(
      (z) =>
          z.activa &&
          c.ancestros(z).contains(ciudadId) &&
          _plano(z.nombre).contains(buscado),
    );
    return _ordenadas(coinciden).map(c.aFila).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerMiCobertura() async {
    final res = await _gateway.get(_rutaCobertura);
    return _zonasDeCobertura(res);
  }

  /// Reemplazo total e idempotente. Devuelve `{zona_id}` por cada zona que
  /// quedó guardada, que es lo que lee el repositorio.
  @override
  Future<List<Map<String, dynamic>>> declararCobertura(
    List<String> zonaIds,
  ) async {
    final res = await _gateway.put(_rutaCobertura, {'zoneIds': zonaIds});
    final ids = res['zoneIds'];
    if (ids is! List) throw _respuestaInesperada;
    return ids
        .map((id) => <String, dynamic>{'zona_id': id as String})
        .toList(growable: false);
  }

  @override
  String? get tenantIdSesion {
    final auth = _sesion?.auth;
    return auth == null ? null : tenantIdDeSesion(auth);
  }

  Future<List<Map<String, dynamic>>> _zonasDeCobertura(
    Map<String, dynamic> res,
  ) async {
    final lista = res['zones'];
    if (lista is! List) throw _respuestaInesperada;
    if (lista.isEmpty) return const [];
    final c = await _cargar();
    return lista
        .map((e) {
          final zona = Map<String, dynamic>.from(e as Map);
          // El catálogo aporta ancestros y si tiene hijas; la zona que Core
          // devuelve manda en `estado` (una desactivada se ve inactiva).
          final delCatalogo = c.porId[zona['id']];
          final fila = delCatalogo != null
              ? c.aFila(delCatalogo)
              : _filaDe(_Zona.desdeJson(zona), const [], false);
          fila['estado'] = zona['active'] == false ? 'inactiva' : 'activa';
          return fila;
        })
        .toList(growable: false);
  }

  Future<_Catalogo> _cargar() async {
    final vigente =
        _catalogo != null &&
        _cargadoEn != null &&
        _ahora().difference(_cargadoEn!) < _vigencia;
    if (vigente) return _catalogo!;
    final res = await _gateway.get(_rutaZonas);
    final lista = res['zones'];
    if (lista is! List) throw _respuestaInesperada;
    final catalogo = _Catalogo([
      for (final e in lista)
        _Zona.desdeJson(Map<String, dynamic>.from(e as Map)),
    ]);
    _catalogo = catalogo;
    _cargadoEn = _ahora();
    return catalogo;
  }

  static List<_Zona> _ordenadas(Iterable<_Zona> zonas) =>
      zonas.toList()..sort((a, b) => a.nombre.compareTo(b.nombre));

  /// Minúsculas y sin tildes, para que "chapinero" encuentre "Chapinéro".
  static String _plano(String s) {
    const de = 'áàäâéèëêíìïîóòöôúùüûñ';
    const a = 'aaaaeeeeiiiioooouuuun';
    var r = s.trim().toLowerCase();
    for (var i = 0; i < de.length; i++) {
      r = r.replaceAll(de[i], a[i]);
    }
    return r;
  }

  static const _respuestaInesperada = GatewayException(
    message: 'Respuesta inesperada del servidor',
    statusCode: 502,
  );
}

Map<String, dynamic> _filaDe(
  _Zona z,
  List<String> ancestros,
  bool tieneHijas,
) => {
  'id': z.id,
  'nombre': z.nombre,
  'nivel': z.nivel,
  'zona_padre_id': z.padreId,
  'ancestros': ancestros,
  'tiene_hijas': tieneHijas,
  'estado': z.activa ? 'activa' : 'inactiva',
};

class _Zona {
  const _Zona({
    required this.id,
    required this.nombre,
    required this.nivel,
    required this.padreId,
    required this.activa,
  });

  factory _Zona.desdeJson(Map<String, dynamic> j) => _Zona(
    id: j['id'] as String,
    nombre: j['name'] as String,
    nivel: (j['level'] as String? ?? '').toUpperCase(),
    padreId: j['parentId'] as String?,
    activa: j['active'] != false,
  );

  final String id;
  final String nombre;
  final String nivel;
  final String? padreId;
  final bool activa;
}

/// Catálogo en memoria: índice por id y por padre.
class _Catalogo {
  _Catalogo(this.zonas) : porId = {for (final z in zonas) z.id: z}, hijas = {} {
    for (final z in zonas) {
      final padre = z.padreId;
      if (padre != null) (hijas[padre] ??= []).add(z);
    }
  }

  final List<_Zona> zonas;
  final Map<String, _Zona> porId;
  final Map<String, List<_Zona>> hijas;

  /// Del padre inmediato a la raíz. El tope de saltos evita un ciclo si la base
  /// trae una relación inconsistente.
  List<String> ancestros(_Zona z) {
    final r = <String>[];
    var actual = z;
    for (var saltos = 0; saltos < zonas.length; saltos++) {
      final padre = actual.padreId == null ? null : porId[actual.padreId];
      if (padre == null) break;
      r.add(padre.id);
      actual = padre;
    }
    return r;
  }

  Map<String, dynamic> aFila(_Zona z) => _filaDe(
    z,
    ancestros(z),
    (hijas[z.id] ?? const <_Zona>[]).any((h) => h.activa),
  );
}
