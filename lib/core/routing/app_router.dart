import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/session/guardas_ruta.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/app_shell.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';
import 'package:mani/features/asignacion/presentation/pages/solicitudes_aliado_page.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/presentation/pages/login_page.dart';
import 'package:mani/features/home/data/resumen_inicio.dart';
import 'package:mani/features/home/presentation/pages/inicio_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_page.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_empresa_page.dart';
import 'package:mani/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:mani/features/auth/presentation/pages/olvide_contrasena_page.dart';
import 'package:mani/features/auth/presentation/pages/restablecer_contrasena_page.dart';
import 'package:mani/features/messaging/presentation/chat_cubit.dart';
import 'package:mani/features/messaging/presentation/chat_page.dart';
import 'package:mani/features/payments/presentation/pago_cubit.dart';
import 'package:mani/features/payments/presentation/pago_sandbox_page.dart';
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
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_cubit.dart';
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_page.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_cubit.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_page.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_cubit.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_page.dart';
import 'package:mani/features/services/additions/presentation/adiciones_cubit.dart';
import 'package:mani/features/services/additions/presentation/adiciones_seccion.dart';
import 'package:mani/features/services/execution/presentation/ejecucion_cubit.dart';
import 'package:mani/features/services/execution/presentation/ejecucion_seccion.dart';
import 'package:mani/features/services/events/presentation/eventos_cubit.dart';
import 'package:mani/features/services/events/presentation/eventos_seccion.dart';
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

/// Chat de un servicio (SCRUM-881). El Cubit consulta a Core cada pocos
/// segundos mientras la pantalla está abierta.
Widget _pantallaChat(String solicitudId) => BlocProvider(
  create: (_) => ChatCubit(sl(), solicitudId)..iniciar(),
  child: const ChatPage(),
);

/// Pantalla del servicio de una solicitud: la cotización (SCRUM-865 y 867), la
/// ejecución (SCRUM-868), las adiciones (SCRUM-872) y la bitácora (SCRUM-869 y
/// 870). Cada parte tiene su Cubit y consulta a Core por su lado.
Widget _pantallaServicio(
  String solicitudId, {
  required bool esAliado,
}) => MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => CotizacionCubit(sl(), solicitudId)..cargar()),
    BlocProvider(create: (_) => EjecucionCubit(sl(), solicitudId)..cargar()),
    BlocProvider(create: (_) => AdicionesCubit(sl(), solicitudId)..cargar()),
    BlocProvider(create: (_) => EventosCubit(sl(), solicitudId)..cargar()),
  ],
  child: Builder(
    builder: (context) => CotizacionPage(
      esAliado: esAliado,
      // El pago cobra el total vigente: cotización aceptada + adiciones
      // aceptadas (SCRUM-872). Sin resumen, el total de la cotización.
      alPagar: esAliado
          ? null
          : (cotizacionId, total) => context.push(
              '/cliente/pagos/$cotizacionId',
              extra:
                  context
                      .read<AdicionesCubit>()
                      .state
                      .datos
                      ?.resumen
                      ?.totalVigente ??
                  total,
            ),
      pie: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chat del servicio (HU-M09-02 / SCRUM-881): solo participan el cliente
          // y el aliado asignado; lo valida Core.
          ManiButton(
            key: const Key('btn-abrir-chat'),
            etiqueta: esAliado
                ? 'Mensajes con el cliente'
                : 'Mensajes con el aliado',
            icono: Icons.chat_bubble_outline,
            variante: ManiButtonVariante.secundario,
            expandir: true,
            onPressed: () => context.push(
              '/${esAliado ? 'aliado' : 'cliente'}/solicitudes/$solicitudId/chat',
            ),
          ),
          const SizedBox(height: 12),
          EjecucionSeccion(esAliado: esAliado),
          // Adiciones por imprevisto (SCRUM-872): el aliado las pide con el
          // servicio en ejecución; el cliente decide. Core aplica el tope.
          BlocBuilder<EjecucionCubit, EjecucionState>(
            buildWhen: (a, b) =>
                a.ejecucion?.enEjecucion != b.ejecucion?.enEjecucion,
            builder: (context, state) => AdicionesSeccion(
              esAliado: esAliado,
              puedePedir: esAliado && (state.ejecucion?.enEjecucion ?? false),
            ),
          ),
          // El aliado registra eventos solo con el servicio en ejecución (la regla
          // definitiva la aplica Core, MANI-EVT-409E); el cliente consulta la
          // bitácora en solo lectura (SCRUM-870).
          BlocBuilder<EjecucionCubit, EjecucionState>(
            buildWhen: (a, b) =>
                a.ejecucion?.enEjecucion != b.ejecucion?.enEjecucion,
            builder: (context, state) => EventosSeccion(
              puedeRegistrar:
                  esAliado && (state.ejecucion?.enEjecucion ?? false),
              urlOpener: sl(),
              selectorFotos: esAliado ? sl() : null,
            ),
          ),
        ],
      ),
      alRefrescar: () async {
        await Future.wait([
          context.read<EjecucionCubit>().cargar(),
          context.read<AdicionesCubit>().cargar(),
          context.read<EventosCubit>().cargar(),
        ]);
      },
    ),
  ),
);

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
/// - `/cliente/solicitudes`: Estado y zona declarada de las solicitudes del cliente (HU-M07-04)
/// - `/cliente/solicitudes/:id/aliados`: Aliados elegibles, por tipo y en el orden de Dispatch (SCRUM-1401)
/// - `/aliado/solicitudes`: Bandeja del aliado para aceptar/rechazar solicitudes (US-04.1.4)
/// - `/cliente/solicitudes/:id/cotizacion` y `/aliado/solicitudes/:id/cotizacion`: Pantalla del servicio:
///   cotización, ejecución y bitácora (US-04.2.1 a US-04.3.3)
/// - `/admin/verificacion-aliados`: Bandeja de verificación del admin del tenant (US-02.1.3)
/// - `/admin/categorias`: Catálogo de categorías de servicio del tenant (US-03.1.1)
///
/// El `redirect` protege cualquier ruta que no esté en `_publicPaths`: sin
/// sesión activa en Supabase el usuario va a `/login`, y con sesión una ruta
/// de otro rol lo devuelve al inicio del suyo (US-11.2.2 / SCRUM-1445,
/// `guardas_ruta.dart`). La autorización por rol la aplica, de todos modos,
/// el servidor con el token verificado.
final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _AuthChangeNotifier(),
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    return resolverRedireccion(
      ubicacion: state.matchedLocation,
      esPublica: _isPublicPath(state.matchedLocation),
      haySesion: session != null,
      rol: rolDesdeAccessToken(session?.accessToken),
    );
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
    // Pantallas con sesión dentro del menú superior por rol (US-11.2.1 /
    // SCRUM-1444). El shell solo pinta: la autorización la aplica el servidor.
    ShellRoute(
      builder: (context, state, child) => AppShell(
        rol: rolDesdeAccessToken(
          Supabase.instance.client.auth.currentSession?.accessToken,
        ),
        ubicacion: state.matchedLocation,
        fuenteDatos: sl<FuenteDatosSesion>(),
        onNavegar: (ruta) => context.go(ruta),
        onCerrarSesion: () => sl<IAuthRepository>().signOut(),
        child: child,
      ),
      routes: [
        // Inicio por tipo de usuario (US-11.2.3 / SCRUM-1446).
        GoRoute(
          path: rutaInicio,
          name: 'inicio',
          builder: (context, state) => InicioPage(
            rol: rolDesdeAccessToken(
              Supabase.instance.client.auth.currentSession?.accessToken,
            ),
            fuenteSesion: sl<FuenteDatosSesion>(),
            fuenteResumen: sl<FuenteResumenInicio>(),
            onNavegar: (ruta) => context.go(ruta),
          ),
        ),
        // Ruta independiente: Selección de categorías del aliado (US-03.1.3)
        GoRoute(
          path: '/categories',
          name: 'categories',
          builder: (context, state) => const CategoriesPage(),
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
        // Gestión de múltiples sedes del cliente empresa (US-02.2.2 /
        // SCRUM-852, SCRUM-1387). Core resuelve el cliente por el token.
        GoRoute(
          path: '/cliente/sedes',
          name: 'sedes-empresa',
          builder: (context, state) => BlocProvider(
            create: (_) => sl<SedesEmpresaCubit>(),
            child: const GestionSedesEmpresaPage(),
          ),
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
        // Mis solicitudes (HU-M07-04 / SCRUM-871): estado y zona declarada,
        // sin rastreo en vivo del aliado.
        GoRoute(
          path: '/cliente/solicitudes',
          name: 'mis-solicitudes',
          builder: (context, state) => BlocProvider(
            create: (_) => sl<MisSolicitudesCubit>()..cargar(),
            child: MisSolicitudesPage(
              onNuevaSolicitud: () => context.go('/cliente/solicitudes/nueva'),
              onVerCotizacion: (id) =>
                  context.push('/cliente/solicitudes/$id/cotizacion'),
              onVerAliados: (id) =>
                  context.push('/cliente/solicitudes/$id/aliados'),
            ),
          ),
        ),
        // Aliados elegibles de la solicitud (SCRUM-1398, 1400 y 1401): filtro
        // por tipo y el orden exacto de Dispatch. Solo el cliente (`/cliente/`).
        GoRoute(
          path: '/cliente/solicitudes/:id/aliados',
          name: 'aliados-elegibles',
          builder: (context, state) => BlocProvider(
            create: (_) =>
                AliadosElegiblesCubit(sl(), state.pathParameters['id']!)
                  ..cargar(),
            child: const AliadosElegiblesPage(),
          ),
        ),
        // Cotización del cliente (US-04.2.3 / SCRUM-867): acepta, rechaza o
        // pide ajuste. Solo el cliente dueño responde; lo valida Core.
        GoRoute(
          path: '/cliente/solicitudes/:id/cotizacion',
          name: 'cotizacion-cliente',
          builder: (context, state) =>
              _pantallaServicio(state.pathParameters['id']!, esAliado: false),
        ),
        // Pago de la cotización aceptada en el sandbox (HU-M11-01 / SCRUM-1432):
        // simulador sin dinero ni tarjetas reales. El monto lo calcula Core;
        // `extra` solo trae el total para mostrarlo antes de pagar.
        GoRoute(
          path: '/cliente/pagos/:cotizacionId',
          name: 'pago-sandbox',
          builder: (context, state) => BlocProvider(
            create: (_) =>
                PagoCubit(sl(), state.pathParameters['cotizacionId']!),
            child: PagoSandboxPage(total: state.extra as double?),
          ),
        ),
        // Chat del servicio (HU-M09-02 / SCRUM-881) para el cliente y para el
        // aliado asignado. Core decide quién participa; la app solo consulta.
        GoRoute(
          path: '/cliente/solicitudes/:id/chat',
          name: 'chat-cliente',
          builder: (context, state) =>
              _pantallaChat(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/aliado/solicitudes/:id/chat',
          name: 'chat-aliado',
          builder: (context, state) =>
              _pantallaChat(state.pathParameters['id']!),
        ),
        // Cotización del aliado (US-04.2.1 / SCRUM-865): solo el aliado
        // asignado emite; lo valida Core.
        GoRoute(
          path: '/aliado/solicitudes/:id/cotizacion',
          name: 'cotizacion-aliado',
          builder: (context, state) =>
              _pantallaServicio(state.pathParameters['id']!, esAliado: true),
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
              onAbrirDisponibilidad: () =>
                  context.push('/aliado/disponibilidad'),
              onCotizar: (id) =>
                  context.push('/aliado/solicitudes/$id/cotizacion'),
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
    ),
  ],
);
