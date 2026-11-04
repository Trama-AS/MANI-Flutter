import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/routing/app_router.dart';
import 'package:mani/features/profiles/own_profile/data/datasources/perfil_propio_remote_datasource.dart';
import 'package:mani/features/profiles/own_profile/domain/entities/perfil_propio.dart';
import 'package:mani/features/profiles/own_profile/presentation/pages/editar_perfil_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _PkceEnMemoria extends GotrueAsyncStorage {
  final _datos = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _datos[key];
  @override
  Future<void> removeItem({required String key}) async => _datos.remove(key);
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _datos[key] = value;
}

/// La ruta solo se construye; la pantalla no se monta, así que ningún método
/// de la datasource se llega a invocar.
class _PerfilSinUso implements PerfilPropioRemoteDataSource {
  @override
  Future<PerfilPropio> obtenerPerfilPropio() => throw UnimplementedError();

  @override
  Future<PerfilPropio> actualizarPerfilPropio({
    required String fullName,
    required String phone,
    required String address,
  }) => throw UnimplementedError();

  @override
  Future<PerfilPropio> subirFotoPerfil({
    required String nombreArchivo,
    required Uint8List bytes,
  }) => throw UnimplementedError();
}

/// SCRUM-1389: en la app real el botón «Cambiar foto de perfil» no hacía nada
/// porque la ruta construía la página sin `selectorImagen`.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'clave-de-prueba',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _PkceEnMemoria(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    sl.registerSingleton<PerfilPropioRemoteDataSource>(_PerfilSinUso());
  });

  tearDownAll(sl.reset);

  GoRoute? buscar(List<RouteBase> rutas, String nombre) {
    for (final r in rutas) {
      if (r is GoRoute && r.name == nombre) return r;
      final hija = buscar(r.routes, nombre);
      if (hija != null) return hija;
    }
    return null;
  }

  testWidgets('/perfil/editar construye EditarPerfilPage con un selector de '
      'imagen real', (tester) async {
    final ruta = buscar(appRouter.configuration.routes, 'editar-perfil');
    expect(ruta, isNotNull);
    expect(ruta!.path, '/perfil/editar');

    late Widget construido;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          construido = ruta.builder!(
            context,
            GoRouterState(
              appRouter.configuration,
              uri: Uri.parse('/perfil/editar'),
              matchedLocation: '/perfil/editar',
              fullPath: '/perfil/editar',
              pathParameters: const {},
              pageKey: const ValueKey('/perfil/editar'),
            ),
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(construido, isA<EditarPerfilPage>());
    expect((construido as EditarPerfilPage).selectorImagen, isNotNull);
  });
}
