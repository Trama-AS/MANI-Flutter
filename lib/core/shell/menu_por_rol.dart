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
        EntradaMenu(
          etiqueta: 'Mis sedes',
          icono: Icons.apartment_outlined,
          ruta: '/cliente/sedes',
        ),
        // El cliente ve el catálogo geográfico con la ubicación de sus propias
        // sedes. No declara cobertura: eso es del aliado (HU-M04-07).
        EntradaMenu(
          etiqueta: 'Mapa de zonas',
          icono: Icons.map_outlined,
          ruta: '/catalogo/mapa',
        ),
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
        EntradaMenu(
          etiqueta: 'Cobertura',
          icono: Icons.checklist_outlined,
          ruta: '/aliado/cobertura',
        ),
        // El aliado ve en el mapa resaltada la cobertura que ya declaró. Es
        // consulta: para cambiarla usa «Zona de cobertura», que es por lista
        // y hasta localidad (HU-M04-07).
        EntradaMenu(
          etiqueta: 'Mapa de zonas',
          icono: Icons.map_outlined,
          ruta: '/catalogo/mapa',
        ),
        EntradaMenu(
          etiqueta: 'Categorías',
          icono: Icons.category_outlined,
          ruta: '/categories',
        ),
        EntradaMenu(
          etiqueta: 'Disponibilidad',
          icono: Icons.event_busy_outlined,
          ruta: '/aliado/disponibilidad',
        ),
        EntradaMenu(
          etiqueta: 'Empleados',
          icono: Icons.badge_outlined,
          ruta: '/aliado/empleados/nuevo',
        ),
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
        // Consulta del catálogo geográfico: muestra los límites de zonas y
        // barrios. No declara cobertura ni usa GPS (HU-M04-07).
        EntradaMenu(
          etiqueta: 'Mapa de zonas',
          icono: Icons.map_outlined,
          ruta: '/catalogo/mapa',
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
    case RolUsuario.desconocido:
      return 'Sin rol';
  }
}
