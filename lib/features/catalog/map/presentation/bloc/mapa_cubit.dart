import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/catalog/map/data/mapa_remote_datasource.dart';
import 'package:mani/features/catalog/map/domain/entities/geometria_zona.dart';

enum MapaEstado { inicial, cargando, listo, vacio, error }

class MapaState extends Equatable {
  const MapaState({
    this.estado = MapaEstado.inicial,
    this.localidades = const [],
    this.localidadId,
    this.geometrias = const [],
    this.sinGeometria = const [],
    this.atribuciones = const [],
    this.mensajeError,
  });

  final MapaEstado estado;

  /// Localidades del catálogo, para elegir qué pintar.
  final List<Map<String, dynamic>> localidades;
  final String? localidadId;

  final List<GeometriaZona> geometrias;

  /// Zonas del catálogo que todavía no tienen límite cargado. Se muestran para
  /// que el usuario sepa que faltan, en lugar de dibujar algo inventado (C2).
  final List<String> sinGeometria;
  final List<String> atribuciones;
  final String? mensajeError;

  MapaState copyWith({
    MapaEstado? estado,
    List<Map<String, dynamic>>? localidades,
    String? localidadId,
    List<GeometriaZona>? geometrias,
    List<String>? sinGeometria,
    List<String>? atribuciones,
    String? mensajeError,
  }) {
    return MapaState(
      estado: estado ?? this.estado,
      localidades: localidades ?? this.localidades,
      localidadId: localidadId ?? this.localidadId,
      geometrias: geometrias ?? this.geometrias,
      sinGeometria: sinGeometria ?? this.sinGeometria,
      atribuciones: atribuciones ?? this.atribuciones,
      mensajeError: mensajeError,
    );
  }

  @override
  List<Object?> get props => [
    estado,
    localidades,
    localidadId,
    geometrias,
    sinGeometria,
    atribuciones,
    mensajeError,
  ];
}

/// Visualización cartográfica del catálogo (HU-M04-07 / SCRUM-1396).
///
/// Pinta los límites reales de una localidad y de sus barrios. No usa GPS ni
/// ubicación del dispositivo: las coordenadas salen del catálogo, que es lo
/// que la historia pide y lo que ADR-0011 permite, porque esto no decide
/// elegibilidad ni cobertura.
class MapaCubit extends Cubit<MapaState> {
  MapaCubit(this._datos) : super(const MapaState());

  final MapaRemoteDataSource _datos;

  Future<void> cargar() async {
    emit(state.copyWith(estado: MapaEstado.cargando));
    try {
      final zonas = await _datos.listarZonas();
      final localidades = zonas
          .where((z) => z['level'] == 'LOCALIDAD' && z['selectable'] != false)
          .toList(growable: false);
      if (localidades.isEmpty) {
        emit(state.copyWith(estado: MapaEstado.vacio, localidades: const []));
        return;
      }
      _zonas = zonas;
      emit(state.copyWith(estado: MapaEstado.listo, localidades: localidades));
      await seleccionar('${localidades.first['id']}');
    } on GatewayException catch (e) {
      emit(state.copyWith(estado: MapaEstado.error, mensajeError: e.message));
    }
  }

  Future<void> seleccionar(String localidadId) async {
    emit(state.copyWith(estado: MapaEstado.cargando, localidadId: localidadId));
    try {
      final barrios = _zonas
          .where((z) => z['parentId'] == localidadId && z['level'] == 'BARRIO')
          .map((z) => '${z['id']}')
          .toList();
      final pedidas = <String>[localidadId, ...barrios];
      final res = await _datos.obtenerGeometrias(pedidas);
      final dibujables = res.geometrias.where((g) => g.tienePuntos).toList(growable: false);
      emit(
        state.copyWith(
          // Sin ningún límite dibujable el mapa queda vacío, y eso se dice:
          // no se rellena con una forma aproximada (C2).
          estado: dibujables.isEmpty ? MapaEstado.vacio : MapaEstado.listo,
          geometrias: dibujables,
          sinGeometria: res.sinGeometria,
          atribuciones: res.atribuciones,
        ),
      );
    } on GatewayException catch (e) {
      emit(state.copyWith(estado: MapaEstado.error, mensajeError: e.message));
    }
  }

  List<Map<String, dynamic>> _zonas = const [];
}
