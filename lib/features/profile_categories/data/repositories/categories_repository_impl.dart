import 'package:mani/core/network/gateway_exception.dart';

import '../../domain/entities/category_entity.dart';
import '../../domain/failures/categories_failure.dart';
import '../../domain/repositories/i_categories_repository.dart';
import '../datasources/categories_remote_datasource.dart';
import '../models/category_model.dart';

class CategoriesRepositoryImpl implements ICategoriesRepository {
  final CategoriesRemoteDataSource remoteDataSource;

  CategoriesRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<CategoryEntity>> getAvailableCategories() => _guard(
    () async => (await remoteDataSource.listarCategoriasTenant())
        .map<CategoryEntity>(CategoryModel.fromJson)
        .toList(),
  );

  @override
  Future<Set<String>> getSelectedCategoryIds() => _guard(
    () async => (await remoteDataSource.obtenerMisCategorias()).toSet(),
  );

  @override
  Future<Set<String>> saveSelectedCategories(Set<String> categoryIds) => _guard(
    () async => (await remoteDataSource.guardarMisCategorias(
      categoryIds.toList(),
    )).toSet(),
  );

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapearError(e);
    } on CategoriesFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('TimeoutException')) {
        throw CategoriesFailure(CategoriesErrorTipo.sinConexion, s);
      }
      throw CategoriesFailure(CategoriesErrorTipo.desconocido, s);
    }
  }

  /// Traduce el error del Gateway: primero el `code` `MANI-CAT-*` que Core pone
  /// en el cuerpo y, si no lo hay, el status HTTP.
  static CategoriesFailure mapearError(GatewayException e) {
    final code = e.cuerpo?['code'];
    if (code is String) {
      final porCodigo = mapearMensaje(code);
      if (porCodigo.tipo != CategoriesErrorTipo.desconocido) return porCodigo;
    }
    if (e.isConnectionError) {
      return CategoriesFailure(CategoriesErrorTipo.sinConexion, e.message);
    }
    if (e.isUnauthorized) {
      return CategoriesFailure(CategoriesErrorTipo.sinSesion, e.message);
    }
    if (e.isForbidden) {
      return CategoriesFailure(CategoriesErrorTipo.noEsAliado, e.message);
    }
    return CategoriesFailure(CategoriesErrorTipo.desconocido, e.message);
  }

  /// Traduce el prefijo `MANI-CAT-*` del código o del mensaje.
  static CategoriesFailure mapearMensaje(String mensaje) {
    const tabla = <String, CategoriesErrorTipo>{
      'MANI-CAT-401': CategoriesErrorTipo.sinSesion,
      'MANI-CAT-403': CategoriesErrorTipo.noEsAliado,
      'MANI-CAT-422V': CategoriesErrorTipo.seleccionVacia,
      'MANI-CAT-422C': CategoriesErrorTipo.categoriaNoDisponible,
    };
    for (final e in tabla.entries) {
      if (mensaje.startsWith(e.key)) return CategoriesFailure(e.value, mensaje);
    }
    if (mensaje.contains('JWT') || mensaje.contains('permission denied')) {
      return CategoriesFailure(CategoriesErrorTipo.sinSesion, mensaje);
    }
    return CategoriesFailure(CategoriesErrorTipo.desconocido, mensaje);
  }
}
