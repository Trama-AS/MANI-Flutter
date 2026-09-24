import 'package:supabase_flutter/supabase_flutter.dart';

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
    } on PostgrestException catch (e) {
      throw mapearMensaje(e.message);
    } on AuthException catch (e) {
      throw CategoriesFailure(CategoriesErrorTipo.sinSesion, e.message);
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

  /// Traduce el prefijo `MANI-CAT-*` de las RPC.
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
