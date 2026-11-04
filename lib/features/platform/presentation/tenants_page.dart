import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import 'package:mani/core/widgets/mani_button.dart';

import '../data/tenants_datasource.dart';

class TenantsState extends Equatable {
  const TenantsState({
    this.cargando = false,
    this.tenants = const [],
    this.actualizandoId,
    this.error,
    this.aviso,
    this.avisoEsError = false,
  });

  final bool cargando;
  final List<TenantPlataforma> tenants;
  final String? actualizandoId;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  @override
  List<Object?> get props => [
    cargando,
    tenants,
    actualizandoId,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Administración de tenants (HU-M12-07 / SCRUM-901): el administrador de
/// plataforma habilita, suspende o inactiva un tenant con motivo. Core exige el
/// permiso PLATFORM_ADMIN y registra cada cambio.
class TenantsCubit extends Cubit<TenantsState> {
  TenantsCubit(this._fuente) : super(const TenantsState());

  final FuenteTenants _fuente;

  Future<void> cargar() async {
    emit(TenantsState(cargando: true, tenants: state.tenants));
    try {
      emit(TenantsState(tenants: await _fuente.listar()));
    } catch (e) {
      emit(TenantsState(tenants: state.tenants, error: mensajeErrorGateway(e)));
    }
  }

  Future<bool> cambiarEstado(
    TenantPlataforma tenant,
    EstadoTenant estado,
    String motivo,
  ) async {
    emit(TenantsState(tenants: state.tenants, actualizandoId: tenant.id));
    try {
      final actualizado = await _fuente.cambiarEstado(
        tenant.id,
        estado,
        motivo,
      );
      emit(
        TenantsState(
          tenants: [
            for (final t in state.tenants)
              t.id == actualizado.id ? actualizado : t,
          ],
          aviso:
              '${actualizado.nombre} quedó ${actualizado.estado.etiqueta.toLowerCase()}.',
        ),
      );
      return true;
    } catch (e) {
      emit(
        TenantsState(
          tenants: state.tenants,
          aviso: mensajeErrorGateway(e),
          avisoEsError: true,
        ),
      );
      return false;
    }
  }

  Future<List<CambioEstadoTenant>> historial(String tenantId) =>
      _fuente.historial(tenantId);
}

class TenantsPage extends StatelessWidget {
  const TenantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TenantsCubit, TenantsState>(
      listenWhen: (a, b) => b.aviso != null && a.aviso != b.aviso,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('tenants-aviso'),
              content: Text(state.aviso!),
              backgroundColor: state.avisoEsError
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          );
      },
      builder: (context, state) {
        final cubit = context.read<TenantsCubit>();
        final tema = Theme.of(context).textTheme;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: RefreshIndicator(
              onRefresh: cubit.cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Tenants de la plataforma', style: tema.headlineSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'Habilita, suspende o inactiva un tenant. Cada cambio pide '
                    'un motivo y queda registrado con tu usuario.',
                  ),
                  const SizedBox(height: 12),
                  if (state.cargando && state.tenants.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (state.error != null)
                    Card(
                      key: const Key('tenants-error'),
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(state.error!),
                        trailing: TextButton(
                          onPressed: cubit.cargar,
                          child: const Text('Reintentar'),
                        ),
                      ),
                    )
                  else
                    for (final t in state.tenants)
                      Card(
                        key: Key('tenant-${t.id}'),
                        child: ListTile(
                          title: Text(t.nombre),
                          subtitle: Text(t.slug),
                          leading: Chip(
                            key: Key('tenant-estado-${t.id}'),
                            label: Text(t.estado.etiqueta),
                          ),
                          trailing: state.actualizandoId == t.id
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : PopupMenuButton<String>(
                                  key: Key('tenant-acciones-${t.id}'),
                                  onSelected: (accion) => accion == 'historial'
                                      ? _verHistorial(context, cubit, t)
                                      : _cambiar(
                                          context,
                                          cubit,
                                          t,
                                          EstadoTenant.desde(accion),
                                        ),
                                  itemBuilder: (_) => [
                                    for (final e in EstadoTenant.values)
                                      if (e != t.estado)
                                        PopupMenuItem(
                                          key: Key('tenant-${e.valor}-${t.id}'),
                                          value: e.valor,
                                          child: Text(switch (e) {
                                            EstadoTenant.activo => 'Habilitar',
                                            EstadoTenant.suspendido =>
                                              'Suspender',
                                            EstadoTenant.inactivo =>
                                              'Inactivar',
                                          }),
                                        ),
                                    PopupMenuItem(
                                      key: Key('tenant-historial-${t.id}'),
                                      value: 'historial',
                                      child: const Text('Historial'),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _cambiar(
  BuildContext context,
  TenantsCubit cubit,
  TenantPlataforma tenant,
  EstadoTenant estado,
) async {
  final motivo = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoMotivo(tenant: tenant, estado: estado),
  );
  if (motivo == null) return;
  await cubit.cambiarEstado(tenant, estado, motivo);
}

Future<void> _verHistorial(
  BuildContext context,
  TenantsCubit cubit,
  TenantPlataforma tenant,
) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Historial · ${tenant.nombre}'),
    content: SizedBox(
      width: 460,
      child: FutureBuilder<List<CambioEstadoTenant>>(
        future: cubit.historial(tenant.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) return Text(mensajeErrorGateway(snap.error!));
          final cambios = snap.data!;
          if (cambios.isEmpty) return const Text('Sin cambios registrados.');
          return ListView(
            shrinkWrap: true,
            children: [
              for (final c in cambios)
                ListTile(
                  dense: true,
                  title: Text('${c.anterior.etiqueta} → ${c.nuevo.etiqueta}'),
                  subtitle: Text('${c.fecha?.toLocal() ?? ''} · ${c.motivo}'),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);

/// Motivo del cambio: entre 10 y 500 caracteres, como exige Core.
class _DialogoMotivo extends StatefulWidget {
  const _DialogoMotivo({required this.tenant, required this.estado});

  final TenantPlataforma tenant;
  final EstadoTenant estado;

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _valido {
    final n = _motivo.text.trim().runes.length;
    return n >= 10 && n <= 500;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.estado.etiqueta}: ${widget.tenant.nombre}'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('tenant-motivo'),
          controller: _motivo,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Motivo del cambio',
            helperText: 'Mínimo 10 caracteres',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ManiButton(
          key: const Key('tenant-confirmar'),
          etiqueta: 'Confirmar',
          onPressed: _valido
              ? () => Navigator.of(context).pop(_motivo.text.trim())
              : null,
        ),
      ],
    );
  }
}
