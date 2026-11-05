import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

/// Categorías que atiende el aliado. `tenant_id` y `aliado_id` NUNCA se
/// envían: Core Node los toma del JWT verificado (ADR-0018/0032).
abstract interface class CategoriesRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategoriasTenant();
  Future<List<String>> obtenerMisCategorias();
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds);
}

/// Todas las operaciones salen por el API Gateway hacia Core Node
/// (`/api/v1/core/profiles/me/categories`); ninguna llama RPC ni tablas de
/// Supabase (ADR-0027, SCRUM-1380).
class GatewayCategoriesDataSource implements CategoriesRemoteDataSource {
  GatewayCategoriesDataSource(this._gateway);

  static const _ruta = '/api/v1/core/profiles/me/categories';

  final GatewayClient _gateway;

  /// Core responde `{id, name}`; el modelo de la feature lee `nombre`.
  @override
  Future<List<Map<String, dynamic>>> listarCategoriasTenant() async {
    final res = await _gateway.get('$_ruta/available');
    final lista = res['categories'];
    if (lista is! List) throw _respuestaInesperada;
    return lista
        .map((e) {
          final c = Map<String, dynamic>.from(e as Map);
          return <String, dynamic>{
            'id': c['id'],
            'nombre': c['name'] ?? c['nombre'],
          };
        })
        .toList(growable: false);
  }

  @override
  Future<List<String>> obtenerMisCategorias() async =>
      _ids(await _gateway.get(_ruta));

  /// Reemplazo total e idempotente: repetir el `PUT` deja el mismo conjunto.
  @override
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds) async =>
      _ids(await _gateway.put(_ruta, {'categoryIds': categoriaIds}));

  static List<String> _ids(Map<String, dynamic> res) {
    final ids = res['categoryIds'];
    if (ids is! List) throw _respuestaInesperada;
    return ids.cast<String>();
  }

  static const _respuestaInesperada = GatewayException(
    message: 'Respuesta inesperada del servidor',
    statusCode: 502,
  );
}
