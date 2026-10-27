import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/catalog/domain/entities/zona_catalogo.dart';

abstract class IZonasCatalogoRemoteDataSource {
  /// Jerarquía completa del catálogo. Con [soloActivas] las zonas
  /// desactivadas no vienen en la respuesta.
  Future<List<ZonaCatalogo>> consultarJerarquia({bool soloActivas});

  /// Zonas de un nivel concreto, con su etiqueta jerárquica ya armada, en el
  /// formato `{ id: etiqueta }` que consumen los desplegables.
  Future<Map<String, String>> opcionesSeleccionables({String? nivel});
}

/// Datasource HTTP del catálogo geográfico a través del API Gateway
/// (`GET /api/v1/core/catalog/zones`, HU-M04-04).
///
/// Nunca va al puerto interno de Core: la URL base es la del Gateway, que es
/// quien valida el JWT y rechaza en el borde sin token.
class ZonasCatalogoRemoteDataSource implements IZonasCatalogoRemoteDataSource {
  const ZonasCatalogoRemoteDataSource({required this.gateway});

  final GatewayClient gateway;

  static const rutaZonas = '/api/v1/core/catalog/zones';

  @override
  Future<List<ZonaCatalogo>> consultarJerarquia({
    bool soloActivas = true,
  }) async {
    final respuesta = await gateway.get(
      rutaZonas,
      queryParameters: {if (soloActivas) 'onlyActive': 'true'},
    );
    final raw = respuesta['tree'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ZonaCatalogo.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Map<String, String>> opcionesSeleccionables({String? nivel}) async {
    final jerarquia = await consultarJerarquia();
    final opciones = <String, String>{};

    void recorrer(ZonaCatalogo zona, List<String> ancestros) {
      // Una zona no seleccionable se omite como opción pero se sigue
      // recorriendo: sus hijos pueden ser válidos.
      final coincideNivel = nivel == null || zona.nivel == nivel;
      if (zona.seleccionable && coincideNivel) {
        opciones[zona.id] = zona.etiquetaCon(ancestros);
      }
      for (final hijo in zona.hijos) {
        recorrer(hijo, [...ancestros, zona.nombre]);
      }
    }

    for (final raiz in jerarquia) {
      recorrer(raiz, const []);
    }
    return opciones;
  }
}
