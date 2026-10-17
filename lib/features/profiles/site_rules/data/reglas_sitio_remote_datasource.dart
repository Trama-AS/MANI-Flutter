import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/profiles/site_rules/domain/entities/reglas_sitio.dart';
import 'package:mani/features/profiles/site_rules/domain/usecases/reglas_sitio_usecases.dart';

abstract class IReglasSitioRemoteDataSource {
  Future<ReglasContextualesSitio> obtenerReglas(String siteId);
  Future<ReglasContextualesSitio> configurarReglas(
    ReglasContextualesSitio reglas,
  );
}

/// Datasource HTTP para consultar y configurar las reglas contextuales de un
/// sitio vía el API Gateway (`GET/PUT /api/v1/sites/:siteId/rules`,
/// US-02.2.3 / SCRUM-853, ADR-0027).
class ReglasSitioRemoteDataSource implements IReglasSitioRemoteDataSource {
  const ReglasSitioRemoteDataSource({required this.gateway});

  final GatewayClient gateway;

  static String rutaReglasSitio(String siteId) => '/api/v1/sites/$siteId/rules';

  @override
  Future<ReglasContextualesSitio> obtenerReglas(String siteId) async {
    final respuesta = await gateway.get(rutaReglasSitio(siteId));
    return ReglasContextualesSitio.fromJson(siteId, respuesta);
  }

  @override
  Future<ReglasContextualesSitio> configurarReglas(
    ReglasContextualesSitio reglas,
  ) async {
    final respuesta = await gateway.put(
      rutaReglasSitio(reglas.siteId),
      reglas.toPayload(),
    );
    return ReglasContextualesSitio.fromJson(reglas.siteId, respuesta);
  }
}

class ReglasSitioRepositoryImpl implements IReglasSitioRepository {
  const ReglasSitioRepositoryImpl({required this.remoteDataSource});

  final IReglasSitioRemoteDataSource remoteDataSource;

  @override
  Future<ReglasContextualesSitio> obtenerReglas(String siteId) async {
    try {
      return await remoteDataSource.obtenerReglas(siteId);
    } on GatewayException catch (e) {
      throw ReglasSitioFailure(e.message);
    } catch (_) {
      throw const ReglasSitioFailure(
        'No fue posible consultar las reglas del sitio.',
      );
    }
  }

  @override
  Future<ReglasContextualesSitio> configurarReglas(
    ReglasContextualesSitio reglas,
  ) async {
    try {
      return await remoteDataSource.configurarReglas(reglas);
    } on GatewayException catch (e) {
      throw ReglasSitioFailure(e.message);
    } catch (_) {
      throw const ReglasSitioFailure(
        'No fue posible guardar las reglas del sitio.',
      );
    }
  }
}
