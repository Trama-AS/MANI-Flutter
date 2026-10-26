import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';
import 'package:mani/features/asignacion/presentation/pages/solicitudes_aliado_page.dart';
import 'package:mani/features/auth/presentation/pages/login_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_empresa_page.dart';
import 'package:mani/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:mani/features/auth/presentation/pages/olvide_contrasena_page.dart';
import 'package:mani/features/auth/presentation/pages/restablecer_contrasena_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_aliado_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_aliado_empresa_page.dart';
import 'package:mani/features/availability/presentation/pages/disponibilidad_page.dart';
import 'package:mani/features/profile_categories/presentation/pages/categories_page.dart';
import 'package:mani/features/profiles/coverage/presentation/pages/declarar_cobertura_page.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';
import 'package:mani/features/profiles/verification/presentation/pages/bandeja_verificacion_page.dart';
import 'package:mani/features/services/categories/presentation/bloc/categorias_cubit.dart';
import 'package:mani/features/services/categories/presentation/pages/gestion_categorias_page.dart';
import 'package:mani/features/services/requests/presentation/bloc/crear_solicitud_cubit.dart';
import 'package:mani/features/services/requests/presentation/pages/crear_solicitud_page.dart';
import 'package:mani/features/profiles/site_rules/presentation/bloc/reglas_sitio_cubit.dart';
import 'package:mani/features/profiles/site_rules/presentation/pages/reglas_sitio_page.dart';
import 'package:mani/features/profiles/company_sites/presentation/bloc/sedes_empresa_cubit.dart';
import 'package:mani/features/profiles/company_sites/presentation/pages/gestion_sedes_empresa_page.dart';
import 'package:mani/features/profiles/direct_employees/presentation/bloc/empleado_directo_cubit.dart';
import 'package:mani/features/profiles/direct_employees/presentation/pages/registrar_empleado_directo_page.dart';
import 'package:mani/features/profiles/own_profile/presentation/pages/editar_perfil_page.dart';

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
  '/register-cliente-empresa',
  '/forgot-password',
  '/reset-password',
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
/// - `/register-cliente-empresa`: Registro de cliente empresa con NIT y representante (HU-M02-07)
/// - `/forgot-password` y `/reset-password`: Recuperación de contraseña (HU-M02-10)
/// - `/categories`: Pantalla de selección de categorías del aliado (US-03.1.3)
/// - `/aliado/cobertura`: Zona de cobertura del aliado (US-02.1.4)
/// - `/aliado/disponibilidad`: Ausencias del aliado, "No disponible" (US-02.1.6)
/// - `/cliente/solicitudes/nueva`: El cliente publica su solicitud con fotos (US-04.1.1)
/// - `/aliado/solicitudes`: Bandeja del aliado para aceptar/rechazar solicitudes (US-04.1.4)
/// - `/admin/verificacion-aliados`: Bandeja de verificación del admin del tenant (US-02.1.3)
/// - `/admin/categorias`: Catálogo de categorías de servicio del tenant (US-03.1.1)
///
/// El `redirect` protege cualquier ruta que no esté en `_publicPaths`: si no
/// hay sesión activa en Supabase, el usuario es enviado a `/login`. Las rutas
/// de categorías, cobertura y verificación son privadas a propósito: solo un aliado o un
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
    // Recuperación de contraseña (HU-M02-10): el enlace del correo abre /reset-password con el token en la URL.
    GoRoute(
      path: '/forgot-password',
      name: 'forgot-password',
      builder: (context, state) => const OlvideContrasenaPage(),
    ),
    GoRoute(
      path: '/reset-password',
      name: 'reset-password',
      builder: (context, state) => RestablecerContrasenaPage(
        enlace: EnlaceRecuperacion.resolver(state.uri, Uri.base),
      ),
    ),
    // Ruta independiente: Registro de Cliente Empresa (HU-M02-07)
    GoRoute(
      path: '/register-cliente-empresa',
      name: 'register-cliente-empresa',
      builder: (context, state) => const RegistroClienteEmpresaPage(),
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
    // Configuración y consulta de reglas contextuales de un sitio (US-02.2.3 / SCRUM-853)
    GoRoute(
      path: '/sitios/:id/reglas',
      name: 'reglas-sitio',
      builder: (context, state) {
        final siteId = state.pathParameters['id'] ?? '';
        final esAliado = state.uri.queryParameters['esAliado'] == 'true';
        return BlocProvider(
          create: (_) => sl<ReglasSitioCubit>(),
          child: ReglasSitioPage(siteId: siteId, esVistaAliado: esAliado),
        );
      },
    ),
    // Edición del perfil propio de cliente o aliado (US-02.3.1 / SCRUM-854)
    GoRoute(
      path: '/perfil/editar',
      name: 'editar-perfil',
      builder: (context, state) => EditarPerfilPage(dataSource: sl()),
    ),
    // Gestión de múltiples sedes del cliente empresa (US-02.2.2 / SCRUM-852)
    GoRoute(
      path: '/cliente/sedes',
      name: 'sedes-empresa',
      builder: (context, state) {
        final clienteId =
            state.uri.queryParameters['clienteId'] ??
            Supabase.instance.client.auth.currentUser?.id ??
            '';
        return BlocProvider(
          create: (_) => sl<SedesEmpresaCubit>(),
          child: GestionSedesEmpresaPage(clienteId: clienteId),
        );
      },
    ),
    // Ruta independiente: Registro de empleado directo del aliado (US-02.1.5 / SCRUM-850)
    GoRoute(
      path: '/aliado/empleados/nuevo',
      name: 'registrar-empleado-directo',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<EmpleadoDirectoCubit>(),
        child: const RegistrarEmpleadoDirectoPage(),
      ),
    ),
    // Crear solicitud (US-04.1.1): el cliente describe su problema y adjunta
    // fotos; el tenant y el cliente salen de la sesión, nunca de la app.
    GoRoute(
      path: '/cliente/solicitudes/nueva',
      name: 'crear-solicitud',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<CrearSolicitudCubit>()..cargar(),
        child: CrearSolicitudPage(selectorFotos: sl()),
      ),
    ),
    // Bandeja del aliado (US-04.1.4). La asignación sin doble aliado la
    // garantiza el servidor (UPDATE condicional atómico, DD-MANI §7.1).
    GoRoute(
      path: '/aliado/solicitudes',
      name: 'solicitudes-aliado',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<SolicitudesAliadoCubit>()..cargar(),
        child: SolicitudesAliadoPage(
          onAbrirCobertura: () => context.push('/aliado/cobertura'),
          onAbrirCategorias: () => context.push('/categories'),
          onAbrirDisponibilidad: () => context.push('/aliado/disponibilidad'),
        ),
      ),
    ),
    // Ausencias del aliado (US-02.1.6). Rol y tenant los valida Core.
    GoRoute(
      path: '/aliado/disponibilidad',
      name: 'disponibilidad-aliado',
      builder: (context, state) => const DisponibilidadPage(),
    ),
    // Bandeja de verificación de aliados (US-02.1.3). La autorización real
    // la aplica el servidor: las RPC exigen rol ADMIN_TENANT.
    GoRoute(
      path: '/admin/verificacion-aliados',
      name: 'verificacion-aliados',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<BandejaVerificacionCubit>()..cargar(),
        child: BandejaVerificacionPage(
          onAbrirCategorias: () => context.push('/admin/categorias'),
        ),
      ),
    ),
    // Catálogo de categorías de servicio (US-03.1.1). Las RPC exigen rol
    // ADMIN_TENANT; el tenant sale de la sesión, nunca de la app.
    GoRoute(
      path: '/admin/categorias',
      name: 'categorias',
      builder: (context, state) => BlocProvider(
        create: (_) => sl<CategoriasCubit>()..cargar(),
        child: const GestionCategoriasPage(),
      ),
    ),
  ],
);
