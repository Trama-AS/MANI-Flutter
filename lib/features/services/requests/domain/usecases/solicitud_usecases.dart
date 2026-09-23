import '../entities/catalogo_solicitud.dart';
import '../entities/nueva_solicitud.dart';
import '../entities/solicitud_publicada.dart';
import '../repositories/solicitudes_cliente_repository.dart';

/// Carga en paralelo lo necesario para el formulario.
class CargarCatalogoSolicitud {
  const CargarCatalogoSolicitud(this._repo);
  final SolicitudesClienteRepository _repo;

  /// `Future.wait` (y no `(a, b).wait`) para que el `SolicitudFailure`
  /// llegue tal cual al llamador en vez de envuelto en `ParallelWaitError`.
  Future<CatalogoSolicitud> call() async {
    final r = await Future.wait<Object>([
      _repo.categoriasDisponibles(),
      _repo.misSitios(),
    ]);
    return CatalogoSolicitud(
      categorias: r[0] as List<CategoriaDisponible>,
      sitios: r[1] as List<SitioCliente>,
    );
  }
}

/// Busca barrios o localidades; con menos de 2 caracteres no consulta.
class BuscarZonas {
  const BuscarZonas(this._repo);
  final SolicitudesClienteRepository _repo;

  static const int minimo = 2;

  Future<List<ZonaOpcion>> call(String texto) {
    final t = texto.trim();
    if (t.length < minimo) {
      return Future.value(const []);
    }
    return _repo.buscarZonas(t);
  }
}

/// Publica la solicitud (ya validada al construir [NuevaSolicitud]).
class PublicarSolicitud {
  const PublicarSolicitud(this._repo);
  final SolicitudesClienteRepository _repo;

  Future<SolicitudPublicada> call(NuevaSolicitud solicitud) =>
      _repo.publicar(solicitud);
}
