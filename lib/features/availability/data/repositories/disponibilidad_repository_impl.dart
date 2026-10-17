import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/ausencia.dart';
import '../../domain/failures/disponibilidad_failure.dart';
import '../../domain/repositories/i_disponibilidad_repository.dart';
import '../datasources/disponibilidad_remote_datasource.dart';
import '../models/ausencia_model.dart';

class DisponibilidadRepositoryImpl implements IDisponibilidadRepository {
  DisponibilidadRepositoryImpl({required this.remoteDataSource});

  final DisponibilidadRemoteDataSource remoteDataSource;

  @override
  Future<DisponibilidadAliado> obtener() => _guard(() async {
    final json = await remoteDataSource.listar();
    final data = json['data'] as List<dynamic>? ?? const [];
    return DisponibilidadAliado(
      ausencias: data
          .map(
            (e) => AusenciaModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
      disponibleAhora: json['availableNow'] as bool? ?? true,
    );
  });

  @override
  Future<Ausencia> crear(BorradorAusencia borrador) => _guard(() async {
    final json = await remoteDataSource.crear(AusenciaModel.toJson(borrador));
    return AusenciaModel.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    );
  });

  @override
  Future<Ausencia> editar(String id, BorradorAusencia borrador) =>
      _guard(() async {
        final json = await remoteDataSource.editar(
          id,
          AusenciaModel.toJson(borrador),
        );
        return AusenciaModel.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        );
      });

  @override
  Future<void> eliminar(String id) =>
      _guard(() => remoteDataSource.eliminar(id));

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapear(e);
    } on DisponibilidadFailure {
      rethrow;
    } catch (e) {
      throw DisponibilidadFailure(DisponibilidadErrorTipo.desconocido, '$e');
    }
  }

  /// Traduce el status HTTP y el prefijo `MANI-AUS-*` del mensaje de Core.
  static DisponibilidadFailure mapear(GatewayException e) {
    if (e.isConnectionError) {
      return DisponibilidadFailure(
        DisponibilidadErrorTipo.sinConexion,
        e.message,
      );
    }
    final tipo = switch (e.statusCode) {
      401 => DisponibilidadErrorTipo.sinSesion,
      403 => DisponibilidadErrorTipo.noEsAliado,
      404 => DisponibilidadErrorTipo.noEncontrada,
      409 => DisponibilidadErrorTipo.solapamiento,
      422 || 400 =>
        e.message.startsWith('MANI-AUS-422V')
            ? DisponibilidadErrorTipo.datosInvalidos
            : DisponibilidadErrorTipo.horarioInvalido,
      _ => DisponibilidadErrorTipo.desconocido,
    };
    return DisponibilidadFailure(tipo, e.message);
  }
}
