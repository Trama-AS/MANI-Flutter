import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// Límite geográfico de una zona del catálogo, listo para dibujar.
///
/// El contrato entrega GeoJSON (RFC 7946), donde cada punto va en orden
/// **longitud, latitud**. `LatLng` recibe **latitud primero**, así que la
/// conversión invierte el par. Equivocarse ahí no rompe nada visible en las
/// pruebas de unidad pero manda Bogotá al golfo de Adén, por eso la
/// inversión está en un solo lugar y con prueba propia.
class GeometriaZona extends Equatable {
  const GeometriaZona({
    required this.zonaId,
    required this.nombre,
    required this.nivel,
    required this.anillos,
    required this.atribucion,
  });

  final String zonaId;
  final String nombre;
  final String nivel;

  /// Un anillo por contorno. Un `Polygon` aporta uno (más sus huecos, que no
  /// se dibujan en esta versión); un `MultiPolygon`, varios.
  final List<List<LatLng>> anillos;

  /// Texto que la interfaz debe mostrar: lo exige la licencia de la fuente.
  final String atribucion;

  bool get tienePuntos => anillos.any((a) => a.length >= 3);

  /// Convierte un objeto `geometry` de GeoJSON. Devuelve los anillos vacíos si
  /// el tipo no es dibujable, en lugar de lanzar: una geometría inválida es un
  /// caso previsto del criterio C2 y la pantalla debe poder mostrar el estado
  /// controlado en vez de caerse.
  static List<List<LatLng>> anillosDesdeGeoJson(Object? geometry) {
    if (geometry is! Map) return const [];
    final tipo = geometry['type'];
    final coords = geometry['coordinates'];
    if (coords is! List) return const [];

    if (tipo == 'Polygon') {
      return _anillosDePoligono(coords);
    }
    if (tipo == 'MultiPolygon') {
      return coords.whereType<List>().expand(_anillosDePoligono).toList(growable: false);
    }
    return const [];
  }

  static List<List<LatLng>> _anillosDePoligono(List poligono) {
    return poligono
        .whereType<List>()
        .map(_puntos)
        .where((p) => p.length >= 3)
        .toList(growable: false);
  }

  static List<LatLng> _puntos(List anillo) {
    final puntos = <LatLng>[];
    for (final punto in anillo) {
      if (punto is! List || punto.length < 2) continue;
      final lon = punto[0];
      final lat = punto[1];
      if (lon is! num || lat is! num) continue;
      // GeoJSON: [longitud, latitud]. LatLng: (latitud, longitud).
      puntos.add(LatLng(lat.toDouble(), lon.toDouble()));
    }
    return puntos;
  }

  @override
  List<Object?> get props => [zonaId, nombre, nivel, anillos, atribucion];
}
