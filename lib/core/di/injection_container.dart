import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/platform/url_opener.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/domain/usecases/login_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_aliado_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_empresa_usecase.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:mani/features/profile_categories/data/datasources/categories_remote_datasource.dart';
import 'package:mani/features/profile_categories/data/repositories/categories_repository_impl.dart';
import 'package:mani/features/profile_categories/domain/repositories/i_categories_repository.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_available_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/save_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/presentation/bloc/categories_cubit.dart';
import 'package:mani/features/profiles/coverage/domain/repositories/cobertura_repository.dart';
import 'package:mani/features/profiles/coverage/data/repositories/cobertura_repository_impl.dart';
import 'package:mani/features/profiles/coverage/data/datasources/cobertura_remote_datasource.dart';
import 'package:mani/features/profiles/coverage/presentation/controllers/cobertura_controller.dart';
import 'package:mani/features/profiles/verification/data/datasources/verificacion_remote_datasource.dart';
import 'package:mani/features/profiles/verification/data/repositories/verificacion_aliados_repository_impl.dart';
import 'package:mani/features/profiles/verification/domain/repositories/verificacion_aliados_repository.dart';
import 'package:mani/features/profiles/verification/domain/usecases/verificacion_usecases.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';
import 'package:mani/features/services/categories/data/datasources/categorias_remote_datasource.dart';
import 'package:mani/features/services/categories/data/repositories/categorias_repository_impl.dart';
import 'package:mani/features/services/categories/domain/repositories/categorias_repository.dart';
import 'package:mani/features/services/categories/domain/usecases/categoria_usecases.dart';
import 'package:mani/features/services/categories/presentation/bloc/categorias_cubit.dart';

final sl = GetIt.instance; // sl = service locator

Future<void> init() async {
  // External
  sl.registerLazySingleton(() => Supabase.instance.client);

  // Core
  // TODO: Network info, etc.
  sl.registerLazySingleton<UrlOpener>(() => const UrlLauncherOpener());

  // Features - Auth
  // Bloc
  sl.registerFactory(
    () => AuthCubit(
      loginUseCase: sl(),
      registerClienteUseCase: sl(),
      registerAliadoUseCase: sl(),
      registerEmpresaUseCase: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => LoginUseCase(sl()));
  sl.registerLazySingleton(() => RegisterClienteUseCase(sl()));
  sl.registerLazySingleton(() => RegisterAliadoUseCase(sl()));
  sl.registerLazySingleton(() => RegisterEmpresaUseCase(sl()));

  // Repository
  sl.registerLazySingleton<IAuthRepository>(
    () => AuthRepositoryImpl(remoteDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<IAuthRemoteDataSource>(
    () => AuthRemoteDataSource(client: sl()),
  );

  // Features - Profile Categories
  // Bloc
  sl.registerFactory(
    () => CategoriesCubit(
      getAvailableCategoriesUseCase: sl(),
      getSelectedCategoriesUseCase: sl(),
      saveSelectedCategoriesUseCase: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetAvailableCategoriesUseCase(sl()));
  sl.registerLazySingleton(() => GetSelectedCategoriesUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedCategoriesUseCase(sl()));

  // Repository
  sl.registerLazySingleton<ICategoriesRepository>(
    () => CategoriesRepositoryImpl(remoteDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<CategoriesRemoteDataSource>(
    () => SupabaseCategoriesDataSource(sl()),
  );

  // Features - Profiles / Coverage (US-02.1.4)
  sl.registerFactory(() => CoberturaController(sl()));
  sl.registerLazySingleton<CoberturaRepository>(
    () => CoberturaRepositoryImpl(sl()),
  );
  sl.registerLazySingleton(() => SupabaseCoberturaDataSource(sl()));

  // Features - Profiles / Verification (US-02.1.3)
  sl.registerFactory(
    () => BandejaVerificacionCubit(
      listar: sl(),
      obtenerDetalle: sl(),
      aprobar: sl(),
      rechazar: sl(),
      urlDocumento: sl(),
      urlOpener: sl(),
    ),
  );
  sl.registerLazySingleton(() => ListarSolicitudesAliados(sl()));
  sl.registerLazySingleton(() => ObtenerDetalleAliado(sl()));
  sl.registerLazySingleton(() => AprobarAliado(sl()));
  sl.registerLazySingleton(() => RechazarAliado(sl()));
  sl.registerLazySingleton(() => ObtenerUrlDocumento(sl()));
  sl.registerLazySingleton<VerificacionAliadosRepository>(
    () => VerificacionAliadosRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<VerificacionRemoteDataSource>(
    () => SupabaseVerificacionDataSource(sl()),
  );

  // Features - Services / Categories (US-03.1.1)
  sl.registerFactory(() => CategoriasCubit(listar: sl(), crear: sl()));
  sl.registerLazySingleton(() => ListarCategorias(sl()));
  sl.registerLazySingleton(() => CrearCategoria(sl()));
  sl.registerLazySingleton<CategoriasRepository>(
    () => CategoriasRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<CategoriasRemoteDataSource>(
    () => SupabaseCategoriasDataSource(sl()),
  );
}
