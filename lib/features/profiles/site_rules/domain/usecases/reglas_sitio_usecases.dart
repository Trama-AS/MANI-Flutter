import 'package:mani/features/profiles/site_rules/domain/entities/reglas_sitio.dart';

class ReglasSitioFailure implements Exception {
  const ReglasSitioFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class IReglasSitioRepository {
  Future<ReglasContextualesSitio> obtenerReglas(String siteId);
  Future<ReglasContextualesSitio> configurarReglas(
    ReglasContextualesSitio reglas,
  );
}

class ObtenerReglasSitioUseCase {
  const ObtenerReglasSitioUseCase(this.repository);
  final IReglasSitioRepository repository;

  Future<ReglasContextualesSitio> call(String siteId) {
    if (siteId.trim().isEmpty) {
      throw const ReglasSitioFailure(
        'El identificador del sitio es obligatorio.',
      );
    }
    return repository.obtenerReglas(siteId.trim());
  }
}

class ConfigurarReglasSitioUseCase {
  const ConfigurarReglasSitioUseCase(this.repository);
  final IReglasSitioRepository repository;

  Future<ReglasContextualesSitio> call(ReglasContextualesSitio reglas) {
    if (reglas.siteId.trim().isEmpty) {
      throw const ReglasSitioFailure(
        'El identificador del sitio es obligatorio.',
      );
    }
    return repository.configurarReglas(reglas);
  }
}
