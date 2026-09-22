import '../entities/seleccion_cobertura.dart';
import '../entities/zona.dart';
import '../failures/cobertura_failure.dart';
import '../repositories/cobertura_repository.dart';

/// Declara (reemplaza) la cobertura del aliado autenticado.
/// Valida en cliente lo mismo que valida la RPC, para fallar rápido y sin red.
class DeclararCobertura {
  const DeclararCobertura(this._repo);
  final CoberturaRepository _repo;

  Future<Set<String>> call(SeleccionCobertura seleccion) {
    if (seleccion.estaVacia) {
      throw const CoberturaFailure(CoberturaErrorTipo.seleccionVacia);
    }
    if (seleccion.cantidad > CoberturaFailure.maxZonas) {
      throw const CoberturaFailure(CoberturaErrorTipo.limiteExcedido);
    }
    if (seleccion.desactivadas.isNotEmpty) {
      throw const CoberturaFailure(CoberturaErrorTipo.zonaInvalida);
    }
    return _repo.declararCobertura(seleccion.ids);
  }
}

class ObtenerMiCobertura {
  const ObtenerMiCobertura(this._repo);
  final CoberturaRepository _repo;

  Future<SeleccionCobertura> call() async =>
      SeleccionCobertura.desde(await _repo.obtenerMiCobertura());
}

class ConsultarCatalogoZonas {
  const ConsultarCatalogoZonas(this._repo);
  final CoberturaRepository _repo;

  Future<List<Zona>> ciudades() => _repo.listarZonas();

  Future<List<Zona>> hijas(String padreId) =>
      _repo.listarZonas(padreId: padreId);

  Future<List<Zona>> buscar(String ciudadId, String texto) {
    final t = texto.trim();
    if (t.length < 2) return Future.value(const []);
    return _repo.buscarZonas(ciudadId: ciudadId, texto: t);
  }
}
