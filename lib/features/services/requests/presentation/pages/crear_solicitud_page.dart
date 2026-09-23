import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_snackbar.dart';

import '../bloc/crear_solicitud_cubit.dart';
import '../widgets/indicador_pasos.dart';
import '../widgets/paso_categoria.dart';
import '../widgets/paso_detalle.dart';
import '../widgets/paso_revision.dart';
import '../widgets/paso_ubicacion.dart';
import '../widgets/solicitud_publicada_vista.dart';

/// US-04.1.1 — El cliente publica su problema locativo (descripción + fotos)
/// para que los aliados le envíen sus cotizaciones. Asistente de 4 pasos.
/// Requiere un [CrearSolicitudCubit] en el contexto.
class CrearSolicitudPage extends StatefulWidget {
  const CrearSolicitudPage({
    super.key,
    required this.selectorFotos,
    this.esperaBusqueda = const Duration(milliseconds: 300),
  });

  final SelectorFotos selectorFotos;

  /// Pausa antes de buscar barrios mientras el usuario escribe.
  final Duration esperaBusqueda;

  @override
  State<CrearSolicitudPage> createState() => _CrearSolicitudPageState();
}

class _CrearSolicitudPageState extends State<CrearSolicitudPage> {
  final _descripcion = TextEditingController();
  final _direccion = TextEditingController();
  final _busquedaZona = TextEditingController();
  Timer? _espera;

  @override
  void dispose() {
    _espera?.cancel();
    _descripcion.dispose();
    _direccion.dispose();
    _busquedaZona.dispose();
    super.dispose();
  }

  CrearSolicitudCubit get _cubit => context.read<CrearSolicitudCubit>();

  Future<void> _agregarFotos() async {
    final archivos = await widget.selectorFotos.seleccionar();
    if (archivos.isNotEmpty && mounted) {
      _cubit.agregarFotos(archivos);
    }
  }

  void _buscarZona(String texto) {
    _espera?.cancel();
    _espera = Timer(widget.esperaBusqueda, () => _cubit.buscarZonas(texto));
  }

  Future<void> _nuevaSolicitud() async {
    _descripcion.clear();
    _direccion.clear();
    _busquedaZona.clear();
    await _cubit.nuevaSolicitud();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<CrearSolicitudCubit, CrearSolicitudState>(
          listenWhen: (antes, ahora) =>
              ahora.aviso != null && antes.aviso != ahora.aviso,
          listener: (context, state) => showManiSnackBar(
            context,
            state.aviso!.mensaje,
            esError: state.aviso!.esError,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          ),
        ),
        // Al publicar, ningún aviso viejo debe tapar la confirmación.
        BlocListener<CrearSolicitudCubit, CrearSolicitudState>(
          listenWhen: (antes, ahora) =>
              antes.publicada == null && ahora.publicada != null,
          listener: (context, _) =>
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ],
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              const _BarraSuperior(),
              Expanded(
                child: BlocBuilder<CrearSolicitudCubit, CrearSolicitudState>(
                  buildWhen: (a, b) =>
                      a.carga != b.carga ||
                      a.paso != b.paso ||
                      a.publicada != b.publicada,
                  builder: (context, state) {
                    if (state.publicada != null) {
                      return SolicitudPublicadaVista(
                        solicitud: state.publicada!,
                        onNueva: _nuevaSolicitud,
                      );
                    }
                    return switch (state.carga) {
                      CargaFormulario.inicial ||
                      CargaFormulario.cargando => const Center(
                        child: CircularProgressIndicator(color: AppTheme.dark),
                      ),
                      CargaFormulario.error => _ErrorCarga(
                        mensaje:
                            state.error?.mensajeUsuario ??
                            'No pudimos cargar el formulario.',
                        onReintentar: _cubit.cargar,
                      ),
                      CargaFormulario.listo => _Asistente(
                        paso: state.paso,
                        pasoActual: switch (state.paso) {
                          PasoSolicitud.categoria => const PasoCategoria(),
                          PasoSolicitud.detalle => PasoDetalle(
                            descripcion: _descripcion,
                            onAgregarFotos: _agregarFotos,
                          ),
                          PasoSolicitud.ubicacion => PasoUbicacion(
                            direccion: _direccion,
                            busquedaZona: _busquedaZona,
                            onBuscarZona: _buscarZona,
                          ),
                          PasoSolicitud.revision => const PasoRevision(),
                        },
                      ),
                    };
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

class _Asistente extends StatelessWidget {
  const _Asistente({required this.paso, required this.pasoActual});

  final PasoSolicitud paso;
  final Widget pasoActual;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey('paso-${paso.name}'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IndicadorPasos(actual: paso),
                    const SizedBox(height: 24),
                    pasoActual,
                  ],
                ),
              ),
            ),
          ),
        ),
        const _BarraAcciones(),
      ],
    );
  }
}

/// Atrás / Continuar / Publicar, siempre visible.
class _BarraAcciones extends StatelessWidget {
  const _BarraAcciones();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CrearSolicitudCubit>().state;
    final cubit = context.read<CrearSolicitudCubit>();
    // En el paso 1, elegir una categoría ya avanza: no hace falta "Continuar".
    if (state.paso == PasoSolicitud.categoria) {
      return const SizedBox.shrink();
    }
    final esRevision = state.paso == PasoSolicitud.revision;
    final pista = switch (state.paso) {
      PasoSolicitud.detalle when !state.completo(state.paso) =>
        'Describe el problema para continuar.',
      PasoSolicitud.ubicacion when !state.completo(state.paso) =>
        state.modo == ModoUbicacion.nuevaDireccion && state.zona == null
            ? 'Escribe la dirección y elige el barrio.'
            : 'Completa la dirección para continuar.',
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pista != null) ...[
                  Text(
                    pista,
                    key: const ValueKey('pista-paso'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ManiButton(
                        key: const ValueKey('btn-atras'),
                        etiqueta: 'Atrás',
                        icono: Icons.arrow_back_rounded,
                        variante: ManiButtonVariante.secundario,
                        expandir: true,
                        onPressed: state.publicando ? null : cubit.anterior,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: esRevision
                          ? ManiButton(
                              key: const ValueKey('btn-publicar'),
                              etiqueta: state.publicando
                                  ? 'Publicando…'
                                  : 'Publicar solicitud',
                              icono: Icons.campaign_rounded,
                              expandir: true,
                              cargando: state.publicando,
                              onPressed: state.puedeAvanzar
                                  ? cubit.publicar
                                  : null,
                            )
                          : ManiButton(
                              key: const ValueKey('btn-continuar'),
                              etiqueta: 'Continuar',
                              icono: Icons.arrow_forward_rounded,
                              expandir: true,
                              onPressed: state.puedeAvanzar
                                  ? cubit.siguiente
                                  : null,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
              Icons.home_repair_service_rounded,
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
                  'Nueva solicitud',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.dark,
                  ),
                ),
                Text(
                  'Cuéntanos qué necesitas reparar',
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
        ],
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
              key: const ValueKey('btn-reintentar-formulario'),
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
