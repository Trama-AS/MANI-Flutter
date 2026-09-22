import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_snackbar.dart';

import '../../domain/entities/solicitud_aliado.dart';
import '../bloc/bandeja_verificacion_cubit.dart';
import '../widgets/detalle_aliado_panel.dart';
import '../widgets/filtro_estado_tabs.dart';
import '../widgets/solicitud_aliado_card.dart';
import 'detalle_aliado_page.dart';

/// US-02.1.3 — Bandeja de verificación de aliados del Administrador del Tenant.
///
/// En escritorio muestra la lista y el perfil lado a lado (maestro-detalle);
/// en móvil el perfil se abre en su propia pantalla. Requiere un
/// [BandejaVerificacionCubit] provisto por el contexto.
class BandejaVerificacionPage extends StatelessWidget {
  const BandejaVerificacionPage({super.key});

  static const double anchoEscritorio = 960;

  /// Los avisos flotan por encima de la barra Aprobar/Rechazar para no taparla
  /// mientras el administrador revisa en serie.
  static const EdgeInsets _margenAvisos = EdgeInsets.fromLTRB(16, 0, 16, 104);

  @override
  Widget build(BuildContext context) {
    return BlocListener<BandejaVerificacionCubit, BandejaVerificacionState>(
      listenWhen: (antes, ahora) =>
          ahora.aviso != null && antes.aviso != ahora.aviso,
      listener: (context, state) => showManiSnackBar(
        context,
        state.aviso!.mensaje,
        esError: state.aviso!.esError,
        margin: _margenAvisos,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              const _BarraSuperior(),
              Expanded(
                child:
                    BlocBuilder<
                      BandejaVerificacionCubit,
                      BandejaVerificacionState
                    >(
                      buildWhen: (a, b) => a.carga != b.carga,
                      builder: (context, state) => switch (state.carga) {
                        EstadoCarga.inicial ||
                        EstadoCarga.cargando => const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.dark,
                          ),
                        ),
                        EstadoCarga.error => _ErrorCarga(
                          mensaje:
                              state.error?.mensajeUsuario ??
                              'No pudimos cargar la bandeja.',
                          onReintentar: () =>
                              context.read<BandejaVerificacionCubit>().cargar(),
                        ),
                        EstadoCarga.listo => const _Contenido(),
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido();

  void _abrirEnMovil(BuildContext context, String aliadoId) {
    final cubit = context.read<BandejaVerificacionCubit>()
      ..seleccionar(aliadoId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: DetalleAliadoPage(aliadoId: aliadoId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cubit = context.read<BandejaVerificacionCubit>();
        if (constraints.maxWidth < BandejaVerificacionPage.anchoEscritorio) {
          return _Bandeja(
            resaltarSeleccion: false,
            onSeleccionar: (id) => _abrirEnMovil(context, id),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 440,
              child: _Bandeja(
                resaltarSeleccion: true,
                onSeleccionar: cubit.seleccionar,
              ),
            ),
            Container(width: 2, color: AppTheme.dark),
            Expanded(
              child:
                  BlocBuilder<
                    BandejaVerificacionCubit,
                    BandejaVerificacionState
                  >(
                    buildWhen: (a, b) => a.seleccionadaId != b.seleccionadaId,
                    builder: (context, state) {
                      final id = state.seleccionadaId;
                      if (id == null) return const _SinSeleccion();
                      return DetalleAliadoPanel(
                        key: ValueKey('panel-$id'),
                        aliadoId: id,
                        onCerrar: cubit.cerrarDetalle,
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _Bandeja extends StatelessWidget {
  const _Bandeja({
    required this.resaltarSeleccion,
    required this.onSeleccionar,
  });

  final bool resaltarSeleccion;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BandejaVerificacionCubit>();
    return BlocBuilder<BandejaVerificacionCubit, BandejaVerificacionState>(
      builder: (context, state) {
        final visibles = state.visibles;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Solicitudes de aliados',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Revisa los documentos de cada candidato y decide quién entra a tu red de técnicos.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FiltroEstadoTabs(
                    seleccionado: state.filtro,
                    conteo: state.conteo,
                    onCambiar: cubit.cambiarFiltro,
                  ),
                  const SizedBox(height: 12),
                  _CampoBusqueda(onCambio: cubit.buscar),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.dark,
                backgroundColor: AppTheme.primary,
                onRefresh: () => cubit.cargar(silencioso: true),
                child: visibles.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          _BandejaVacia(
                            filtro: state.filtro,
                            busqueda: state.busqueda,
                          ),
                        ],
                      )
                    : ListView.separated(
                        key: PageStorageKey('lista-${state.filtro.name}'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 24, 24),
                        itemCount: visibles.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final aliado = visibles[i];
                          return SolicitudAliadoCard(
                            aliado: aliado,
                            seleccionada:
                                resaltarSeleccion &&
                                aliado.id == state.seleccionadaId,
                            onTap: () => onSeleccionar(aliado.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CampoBusqueda extends StatefulWidget {
  const _CampoBusqueda({required this.onCambio});

  final ValueChanged<String> onCambio;

  @override
  State<_CampoBusqueda> createState() => _CampoBusquedaState();
}

class _CampoBusquedaState extends State<_CampoBusqueda> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      borderSide: const BorderSide(color: AppTheme.dark, width: 2),
    );
    return TextField(
      key: const ValueKey('buscar-aliado'),
      controller: _controller,
      onChanged: (t) {
        setState(() {});
        widget.onCambio(t);
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
        hintText: 'Buscar por nombre, correo o especialidad',
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppTheme.textSecondary,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onCambio('');
                },
              ),
        enabledBorder: borde,
        focusedBorder: borde.copyWith(
          borderSide: const BorderSide(color: AppTheme.dark, width: 2.5),
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior();

  @override
  Widget build(BuildContext context) {
    final puedeVolver = Navigator.of(context).canPop();
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (puedeVolver) ...[
            IconButton(
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.dark),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 2),
              boxShadow: const [AppTheme.hardShadowSm],
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppTheme.dark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Verificación de aliados',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.dark,
                  ),
                ),
                Text(
                  'Panel del administrador',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('btn-actualizar'),
            tooltip: 'Actualizar bandeja',
            onPressed: () => context.read<BandejaVerificacionCubit>().cargar(
              silencioso: true,
            ),
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.dark),
          ),
        ],
      ),
    );
  }
}

class _BandejaVacia extends StatelessWidget {
  const _BandejaVacia({required this.filtro, required this.busqueda});

  final EstadoVerificacion filtro;
  final String busqueda;

  @override
  Widget build(BuildContext context) {
    final buscando = busqueda.trim().isNotEmpty;
    final (icono, titulo, texto) = buscando
        ? (
            Icons.search_off_rounded,
            'Sin resultados',
            'Ningún aliado coincide con "${busqueda.trim()}".',
          )
        : switch (filtro) {
            EstadoVerificacion.pendiente => (
              Icons.celebration_rounded,
              '¡Bandeja al día!',
              'No hay aliados esperando revisión. Los nuevos registros aparecerán aquí.',
            ),
            EstadoVerificacion.aprobado => (
              Icons.verified_outlined,
              'Aún no hay aliados aprobados',
              'Cuando apruebes un registro lo verás en esta pestaña.',
            ),
            EstadoVerificacion.rechazado => (
              Icons.inbox_outlined,
              'No hay aliados rechazados',
              'Los registros que rechaces quedarán aquí con su motivo.',
            ),
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.dark, width: 2),
              boxShadow: const [AppTheme.hardShadowSm],
            ),
            child: Icon(icono, size: 32, color: AppTheme.dark),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SinSeleccion extends StatelessWidget {
  const _SinSeleccion();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            SizedBox(height: 12),
            Text(
              'Selecciona un aliado',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Verás su perfil, sus documentos y las opciones para aprobarlo o rechazarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCarga extends StatelessWidget {
  const _ErrorCarga({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.dark),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ManiButton(
              key: const ValueKey('btn-reintentar'),
              etiqueta: 'Reintentar',
              icono: Icons.refresh_rounded,
              onPressed: onReintentar,
            ),
          ],
        ),
      ),
    );
  }
}
