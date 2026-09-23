import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/features/auth/presentation/pages/login_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_aliado_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_aliado_empresa_page.dart';
import 'package:mani/features/profile_categories/presentation/pages/categories_page.dart';
import 'package:mani/features/profiles/coverage/presentation/pages/declarar_cobertura_page.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';
import 'package:mani/features/profiles/verification/presentation/pages/bandeja_verificacion_page.dart';

/// Notifica a go_router cada vez que cambia el estado de autenticación de
/// Supabase, para que el `redirect` de abajo se reevalúe automáticamente
/// (por ejemplo, cuando expira la sesión o el usuario cierra sesión).
class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  _AuthChangeNotifier() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Rutas accesibles sin sesión activa (login y los flujos de registro).
const _publicPaths = {
  '/login',
  '/register-cliente',
  '/register-aliado',
  '/register-empresa',
  '/categories', // TODO: quitar de público una vez esté integrada post-login
};

bool _isPublicPath(String path) {
  return _publicPaths.contains(path) ||
      path == '/register' ||
      path == '/registro' ||
      path.startsWith('/registro-');
}

/// Configuración de rutas declarativas limpias para MANI Web (sin hash #).
/// - `/login`: Pantalla de inicio de sesión
/// - `/register-cliente`: Pantalla independiente de registro para clientes (US-02.2.1)
/// - `/register-aliado`: Pantalla independiente de registro para aliados técnicos (US-02.1.1)
/// - `/register-empresa`: Pantalla independiente de registro para aliados empresas (US-02.1.2)
/// - `/categories`: Pantalla de selección de categorías del aliado (US-03.1.3)
/// - `/aliado/cobertura`: Zona de cobertura del aliado (US-02.1.4)
/// - `/admin/verificacion-aliados`: Bandeja de verificación del admin del tenant (US-02.1.3)
///
/// El `redirect` protege cualquier ruta que no esté en `_publicPaths`: si no
/// hay sesión activa en Supabase, el usuario es enviado a `/login`. Las rutas
/// de cobertura y verificación son privadas a propósito: solo un aliado o un
/// administrador autenticados deben llegar a ellas; la autorización por rol
/// la aplican, de todos modos, las RPC del servidor.
final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _AuthChangeNotifier(),
  redirect: (context, state) {
    final isLoggedIn = Supabase.instance.client.auth.currentSession != null;
    if (!isLoggedIn && !_isPublicPath(state.matchedLocation)) {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (context, state) => '/login'),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginPage(),
    ),
    // Ruta independiente: Registro de Cliente (US-02.2.1)
    GoRoute(
      path: '/register-cliente',
      name: 'register-cliente',
      builder: (context, state) => const RegistroClientePage(),
    ),
    GoRoute(
      path: '/registro-cliente',
      redirect: (context, state) => '/register-cliente',
    ),
    // Ruta independiente: Registro de Aliado Técnico (US-02.1.1)
    GoRoute(
      path: '/register-aliado',
      name: 'register-aliado',
      builder: (context, state) => const RegistroAliadoPage(),
    ),
    GoRoute(
      path: '/registro-aliado',
      redirect: (context, state) => '/register-aliado',
    ),
    // Ruta independiente: Registro de Aliado Empresa (US-02.1.2)
    GoRoute(
      path: '/register-empresa',
      name: 'register-empresa',
      builder: (context, state) => const RegistroAliadoEmpresaPage(),
    ),
    GoRoute(
      path: '/registro-empresa',
      redirect: (context, state) => '/register-empresa',
    ),
    // Ruta independiente: Selección de categorías del aliado (US-03.1.3)
    GoRoute(
      path: '/categories',
      name: 'categories',
      builder: (context, state) => const CategoriesPage(),
    ),
    // Redirecciones por compatibilidad
    GoRoute(
      path: '/register',
      redirect: (context, state) {
        final rolParam = state.uri.queryParameters['rol']?.toLowerCase();
        if (rolParam == 'empresa') return '/register-empresa';
        if (rolParam == 'aliado') return '/register-aliado';
        return '/register-cliente';
      },
    ),
    GoRoute(
      path: '/registro',
      redirect: (context, state) => '/register-cliente',
    ),
    // Ruta independiente: Zona de Cobertura (US-02.1.4)
    GoRoute(
      path: '/aliado/cobertura',
      name: 'declarar-cobertura',
      builder: (context, state) => DeclararCoberturaPage(controller: sl()),
    ),
    // Bandeja de verificación de aliados (US-02.1.3). La autorización real
    // la aplica el servidor: las RPC exigen rol ADMIN_TENANT.
    GoRoute(
      path: '/admin/verificacion-aliados',
      name: 'verificacion-aliados',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<BandejaVerificacionCubit>()..cargar(),
        child: const BandejaVerificacionPage(),
      ),
    ),
  ],
);
