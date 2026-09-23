import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_snackbar.dart';

import '../../domain/failures/asignacion_failure.dart';
import '../bloc/solicitudes_aliado_cubit.dart';
import '../widgets/dialogo_rechazo.dart';
import '../widgets/solicitud_card.dart';

/// US-04.1.4 — Bandeja de solicitudes del aliado: aceptar o rechazar sin
/// doble asignación. Requiere un [SolicitudesAliadoCubit] en el contexto.
///
/// Los accesos a cobertura y categorías los inyecta quien compone la
/// navegación (el router), para que esta feature no conozca otras rutas.
class SolicitudesAliadoPage extends StatefulWidget {
  const SolicitudesAliadoPage({
    super.key,
    this.onAbrirCobertura,
    this.onAbrirCategorias,
    this.intervaloRefresco = const Duration(seconds: 30),
  });

  final VoidCallback? onAbrirCobertura;
  final VoidCallback? onAbrirCategorias;

  /// Cada cuánto se refresca la bandeja para no ofrecer solicitudes que otro
  /// aliado ya tomó. `null` desactiva el refresco (tests).
  final Duration? intervaloRefresco;

  @override
  State<SolicitudesAliadoPage> createState() => _SolicitudesAliadoPageState();
}

class _SolicitudesAliadoPageState extends State<SolicitudesAliadoPage> {
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    final intervalo = widget.intervaloRefresco;
    if (intervalo != null) {
      _refresco = Timer.periodic(intervalo, (_) {
        final cubit = context.read<SolicitudesAliadoCubit>();
        if (!cubit.state.procesando) {
          cubit.cargar(silencioso: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SolicitudesAliadoCubit, SolicitudesAliadoState>(
      listenWhen: (antes, ahora) =>
          ahora.aviso != null && antes.aviso != ahora.aviso,
      listener: (context, state) => showManiSnackBar(
        context,
        state.aviso!.mensaje,
        esError: state.aviso!.tipo == TipoAviso.error,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _BarraSuperior(
                onAbrirCobertura: widget.onAbrirCobertura,
                onAbrirCategorias: widget.onAbrirCategorias,
              ),
              Expanded(
                child:
                    BlocBuilder<SolicitudesAliadoCubit, SolicitudesAliadoState>(
                      buildWhen: (a, b) => a.carga != b.carga,
                      builder: (context, state) => switch (state.carga) {
                        CargaSolicitudes.inicial ||
                        CargaSolicitudes.cargando => const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.dark,
                          ),
                        ),
                        CargaSolicitudes.error => _ErrorCarga(
                          falla: state.error,
                          onReintentar: () =>
                              context.read<SolicitudesAliadoCubit>().cargar(),
                        ),
                        CargaSolicitudes.listo => _Bandeja(
                          onAbrirCobertura: widget.onAbrirCobertura,
                          onAbrirCategorias: widget.onAbrirCategorias,
                        ),
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

class _Bandeja extends StatelessWidget {
  const _Bandeja({this.onAbrirCobertura, this.onAbrirCategorias});

  final VoidCallback? onAbrirCobertura;
  final VoidCallback? onAbrirCategorias;

  Future<void> _rechazar(BuildContext context, String id) async {
    final cubit = context.read<SolicitudesAliadoCubit>();
    final solicitud = cubit.state.bandeja.porId(id);
    if (solicitud == null) {
      return;
    }
    final confirmacion = await confirmarRechazo(context, solicitud);
    if (confirmacion != null) {
      await cubit.rechazar(id, motivo: confirmacion.motivo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SolicitudesAliadoCubit>();
    return BlocBuilder<SolicitudesAliadoCubit, SolicitudesAliadoState>(
      builder: (context, state) {
        final visibles = state.visibles;
        final enDisponibles = state.pestana == PestanaSolicitudes.disponibles;
        return RefreshIndicator(
          color: AppTheme.dark,
          backgroundColor: AppTheme.primary,
          onRefresh: () => cubit.cargar(silencioso: true),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: PageStorageKey('solicitudes-${state.pestana.name}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  _Pestanas(
                    seleccionada: state.pestana,
                    disponibles: state.bandeja.disponibles.length,
                    misTrabajos: state.bandeja.misTrabajos.length,
                    onCambiar: cubit.cambiarPestana,
                  ),
                  const SizedBox(height: 14),
                  if (enDisponibles && visibles.isNotEmpty) ...[
                    const _ComoFunciona(),
                    const SizedBox(height: 14),
                  ],
                  if (visibles.isEmpty)
                    enDisponibles
                        ? _SinDisponibles(
                            onAbrirCobertura: onAbrirCobertura,
                            onAbrirCategorias: onAbrirCategorias,
                          )
                        : const _SinTrabajos()
                  else
                    for (final s in visibles) ...[
                      SolicitudCard(
                        solicitud: s,
                        recienAsignada: s.id == state.recienAsignadaId,
                        accionEnCurso: state.procesandoId == s.id
                            ? state.accion
                            : null,
                        bloqueada: state.procesando,
                        onAceptar: () => cubit.aceptar(s.id),
                        onRechazar: () => _rechazar(context, s.id),
                      ),
                      const SizedBox(height: 14),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Pestanas extends StatelessWidget {
  const _Pestanas({
    required this.seleccionada,
    required this.disponibles,
    required this.misTrabajos,
    required this.onCambiar,
  });

  final PestanaSolicitudes seleccionada;
  final int disponibles;
  final int misTrabajos;
  final ValueChanged<PestanaSolicitudes> onCambiar;

  @override
  Widget build(BuildContext context) {
    Widget pestana(PestanaSolicitudes p, String etiqueta, int n) {
      final activa = p == seleccionada;
      return Expanded(
        child: Semantics(
          selected: activa,
          button: true,
          label: '$etiqueta: $n',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('tab-${p.name}'),
            onTap: () => onCambiar(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 50,
              color: activa ? AppTheme.primary : AppTheme.surface,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      etiqueta,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: activa ? AppTheme.dark : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: activa ? AppTheme.dark : AppTheme.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: activa ? AppTheme.primary : AppTheme.dark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowSm],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          pestana(PestanaSolicitudes.disponibles, 'Disponibles', disponibles),
          Container(width: 2, height: 50, color: AppTheme.dark),
          pestana(PestanaSolicitudes.misTrabajos, 'Mis trabajos', misTrabajos),
        ],
      ),
    );
  }
}

/// Explica la regla de asignación para que un "ya no disponible" no sorprenda.
class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt_rounded, color: AppTheme.dark),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estas solicitudes se ofrecen a varios aliados a la vez: '
              'el primero en aceptar se queda con el trabajo.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinDisponibles extends StatelessWidget {
  const _SinDisponibles({this.onAbrirCobertura, this.onAbrirCategorias});

  final VoidCallback? onAbrirCobertura;
  final VoidCallback? onAbrirCategorias;

  @override
  Widget build(BuildContext context) {
    return _Vacio(
      icono: Icons.inbox_outlined,
      titulo: 'No hay solicitudes nuevas',
      texto:
          'Aquí aparecerán las solicitudes de tus especialidades en tus zonas '
          'de cobertura. Revisa que estén al día para recibir más.',
      acciones: [
        if (onAbrirCobertura != null)
          ManiButton(
            key: const ValueKey('btn-vacio-cobertura'),
            etiqueta: 'Mis zonas',
            icono: Icons.map_outlined,
            variante: ManiButtonVariante.secundario,
            onPressed: onAbrirCobertura,
          ),
        if (onAbrirCategorias != null)
          ManiButton(
            key: const ValueKey('btn-vacio-categorias'),
            etiqueta: 'Mis especialidades',
            icono: Icons.handyman_outlined,
            variante: ManiButtonVariante.secundario,
            onPressed: onAbrirCategorias,
          ),
      ],
    );
  }
}

class _SinTrabajos extends StatelessWidget {
  const _SinTrabajos();

  @override
  Widget build(BuildContext context) => const _Vacio(
    icono: Icons.work_outline_rounded,
    titulo: 'Aún no tienes trabajos',
    texto: 'Cuando aceptes una solicitud aparecerá aquí con la dirección.',
  );
}

class _Vacio extends StatelessWidget {
  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.texto,
    this.acciones = const [],
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
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
          if (acciones.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 12, runSpacing: 12, children: acciones),
          ],
        ],
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({this.onAbrirCobertura, this.onAbrirCategorias});

  final VoidCallback? onAbrirCobertura;
  final VoidCallback? onAbrirCategorias;

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
              Icons.handyman_rounded,
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
                  'Solicitudes de servicio',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.dark,
                  ),
                ),
                Text(
                  'Panel del aliado',
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
          if (onAbrirCobertura != null)
            IconButton(
              key: const ValueKey('btn-ir-cobertura'),
              tooltip: 'Mis zonas de cobertura',
              onPressed: onAbrirCobertura,
              icon: const Icon(Icons.map_outlined, color: AppTheme.dark),
            ),
          if (onAbrirCategorias != null)
            IconButton(
              key: const ValueKey('btn-ir-especialidades'),
              tooltip: 'Mis especialidades',
              onPressed: onAbrirCategorias,
              icon: const Icon(Icons.handyman_outlined, color: AppTheme.dark),
            ),
          IconButton(
            key: const ValueKey('btn-actualizar-solicitudes'),
            tooltip: 'Actualizar',
            onPressed: () =>
                context.read<SolicitudesAliadoCubit>().cargar(silencioso: true),
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.dark),
          ),
        ],
      ),
    );
  }
}

class _ErrorCarga extends StatelessWidget {
  const _ErrorCarga({required this.falla, required this.onReintentar});

  final AsignacionFailure? falla;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final enRevision = falla?.tipo == AsignacionErrorTipo.aliadoNoVerificado;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enRevision
                  ? Icons.hourglass_top_rounded
                  : Icons.cloud_off_rounded,
              size: 48,
              color: AppTheme.dark,
            ),
            const SizedBox(height: 12),
            Text(
              falla?.mensajeUsuario ?? 'No pudimos cargar tus solicitudes.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ManiButton(
              key: const ValueKey('btn-reintentar-solicitudes'),
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
