import 'package:flutter/material.dart';
import 'package:mani/core/session/rol_usuario.dart';

/// Entrada del menú superior: etiqueta visible, icono y ruta de go_router.
class EntradaMenu {
  const EntradaMenu({
    required this.etiqueta,
    required this.icono,
    required this.ruta,
  });

  final String etiqueta;
  final IconData icono;
  final String ruta;
}

const _inicio = EntradaMenu(
  etiqueta: 'Inicio',
  icono: Icons.home_outlined,
  ruta: '/inicio',
);

/// Bandeja de avisos (SCRUM-882 y 884): la ven todos los roles.
const _avisos = EntradaMenu(
  etiqueta: 'Avisos',
  icono: Icons.notifications_none,
  ruta: '/perfil/avisos',
);

const _miPerfil = EntradaMenu(
  etiqueta: 'Mi perfil',
  icono: Icons.person_outline,
  ruta: '/perfil/editar',
);

/// Entradas del menú superior por rol (US-11.2.1 / SCRUM-1444).
///
/// Solo se listan rutas que ya existen en `app_router.dart`. Ocultar una
/// entrada no protege la ruta: el bloqueo por rol es de SCRUM-1445 y la
/// autorización la hace el servidor.
List<EntradaMenu> entradasMenuPara(RolUsuario rol) {
  switch (rol) {
    case RolUsuario.cliente:
      return const [
        _inicio,
        EntradaMenu(
          etiqueta: 'Nueva solicitud',
          icono: Icons.add_circle_outline,
          ruta: '/cliente/solicitudes/nueva',
        ),
        EntradaMenu(
          etiqueta: 'Mis solicitudes',
          icono: Icons.list_alt_outlined,
          ruta: '/cliente/solicitudes',
        ),
        // Historial de servicios (SCRUM-879).
        EntradaMenu(
          etiqueta: 'Historial',
          icono: Icons.history,
          ruta: '/cliente/historial',
        ),
        EntradaMenu(
          etiqueta: 'Mis sedes',
          icono: Icons.apartment_outlined,
          ruta: '/cliente/sedes',
        ),
        // Quejas del cliente (SCRUM-895).
        EntradaMenu(
          etiqueta: 'Mis quejas',
          icono: Icons.feedback_outlined,
          ruta: '/cliente/quejas',
        ),
        // Sin entrada propia de mapa: el cliente mira el mapa para comprobar
        // dónde caen sus sedes, así que va dentro de «Mis sedes» (HU-M04-07).
        _avisos,
        _miPerfil,
      ];
    case RolUsuario.aliado:
      return const [
        _inicio,
        EntradaMenu(
          etiqueta: 'Solicitudes',
          icono: Icons.inbox_outlined,
          ruta: '/aliado/solicitudes',
        ),
        // Historial de trabajos (SCRUM-880).
        EntradaMenu(
          etiqueta: 'Historial',
          icono: Icons.history,
          ruta: '/aliado/historial',
        ),
        EntradaMenu(
          etiqueta: 'Cobertura',
          icono: Icons.checklist_outlined,
          ruta: '/aliado/cobertura',
        ),
        // Sin entrada propia de mapa: el aliado lo ve dentro de «Zona de
        // cobertura», donde marca y ve pintado lo que marca (HU-M04-07).
        EntradaMenu(
          etiqueta: 'Categorías',
          icono: Icons.category_outlined,
          ruta: '/categories',
        ),
        EntradaMenu(
          etiqueta: 'Mis cobros',
          icono: Icons.payments_outlined,
          ruta: '/aliado/cobros',
        ),
        EntradaMenu(
          etiqueta: 'Disponibilidad',
          icono: Icons.event_busy_outlined,
          ruta: '/aliado/disponibilidad',
        ),
        _avisos,
        _miPerfil,
      ];
    case RolUsuario.adminTenant:
      return const [
        _inicio,
        EntradaMenu(
          etiqueta: 'Verificación de aliados',
          icono: Icons.verified_user_outlined,
          ruta: '/admin/verificacion-aliados',
        ),
        EntradaMenu(
          etiqueta: 'Categorías',
          icono: Icons.category_outlined,
          ruta: '/admin/categorias',
        ),
        // Política de cancelación tardía (SCRUM-878).
        EntradaMenu(
          etiqueta: 'Cancelaciones',
          icono: Icons.event_busy_outlined,
          ruta: '/admin/politica-cancelacion',
        ),
        // Tarifario y cotizaciones fuera de rango (M-10: SCRUM-885 y 887).
        EntradaMenu(
          etiqueta: 'Tarifario',
          icono: Icons.price_change_outlined,
          ruta: '/admin/tarifas',
        ),
        EntradaMenu(
          etiqueta: 'Fuera de rango',
          icono: Icons.report_outlined,
          ruta: '/admin/reportes/cotizaciones-fuera-de-rango',
        ),
        // M-01 (SCRUM-1366).
        EntradaMenu(
          etiqueta: 'Reglas',
          icono: Icons.rule_outlined,
          ruta: '/admin/reglas',
        ),
        // Empleados directos (SCRUM-1376): los registra el administrador, como exige Core.
        EntradaMenu(
          etiqueta: 'Empleados',
          icono: Icons.badge_outlined,
          ruta: '/admin/empleados/nuevo',
        ),
        // Auditoría de transacciones (SCRUM-889) y conversación de una queja (SCRUM-883).
        EntradaMenu(
          etiqueta: 'Auditoría',
          icono: Icons.fact_check_outlined,
          ruta: '/admin/auditoria-transacciones',
        ),
        EntradaMenu(
          etiqueta: 'Conversaciones',
          icono: Icons.forum_outlined,
          ruta: '/admin/conversaciones',
        ),
        // M-12 (SCRUM-896 y 900).
        EntradaMenu(
          etiqueta: 'Quejas',
          icono: Icons.support_agent_outlined,
          ruta: '/admin/quejas',
        ),
        EntradaMenu(
          etiqueta: 'Métricas',
          icono: Icons.insights_outlined,
          ruta: '/admin/metricas',
        ),
        // Consulta del catálogo geográfico: muestra los límites de zonas y
        // barrios. No declara cobertura ni usa GPS (HU-M04-07).
        EntradaMenu(
          etiqueta: 'Mapa de zonas',
          icono: Icons.map_outlined,
          ruta: '/catalogo/mapa',
        ),
        _avisos,
        _miPerfil,
      ];
    case RolUsuario.adminPlataforma:
      return const [
        _inicio,
        EntradaMenu(
          etiqueta: 'Tenants',
          icono: Icons.domain_outlined,
          ruta: '/plataforma/tenants',
        ),
        _miPerfil,
      ];
    case RolUsuario.desconocido:
      return const [_inicio, _miPerfil];
  }
}

/// Nombre legible del rol para la cabecera.
String etiquetaRol(RolUsuario rol) {
  switch (rol) {
    case RolUsuario.cliente:
      return 'Cliente';
    case RolUsuario.aliado:
      return 'Aliado';
    case RolUsuario.adminTenant:
      return 'Administrador';
    case RolUsuario.adminPlataforma:
      return 'Administración de plataforma';
    case RolUsuario.desconocido:
      return 'Sin rol';
  }
}
