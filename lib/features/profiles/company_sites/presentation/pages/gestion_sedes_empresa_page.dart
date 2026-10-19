import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';
import 'package:mani/features/profiles/company_sites/presentation/bloc/sedes_empresa_cubit.dart';

/// Pantalla de gestión de múltiples sedes (`sitio`) para un Cliente Empresa
/// (US-02.2.2 / SCRUM-852).
class GestionSedesEmpresaPage extends StatefulWidget {
  const GestionSedesEmpresaPage({
    super.key,
    required this.clienteId,
    this.zonasDisponibles = const {
      'z-chapinero': 'Bogotá · Chapinero',
      'z-usaquen': 'Bogotá · Usaquén',
      'z-poblado': 'Medellín · El Poblado',
    },
  });

  final String clienteId;
  final Map<String, String> zonasDisponibles;

  @override
  State<GestionSedesEmpresaPage> createState() =>
      _GestionSedesEmpresaPageState();
}

class _GestionSedesEmpresaPageState extends State<GestionSedesEmpresaPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _direccionController = TextEditingController();
  final _contactoNombreController = TextEditingController();
  final _contactoTelefonoController = TextEditingController();

  late String _zonaSeleccionada;

  @override
  void initState() {
    super.initState();
    _zonaSeleccionada = widget.zonasDisponibles.keys.first;
    context.read<SedesEmpresaCubit>().cargarSedes(widget.clienteId);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _direccionController.dispose();
    _contactoNombreController.dispose();
    _contactoTelefonoController.dispose();
    super.dispose();
  }

  void _guardarSede() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<SedesEmpresaCubit>().agregarNuevaSede(
      clienteId: widget.clienteId,
      nombre: _nombreController.text,
      direccion: _direccionController.text,
      zonaId: _zonaSeleccionada,
      contactoNombre: _contactoNombreController.text,
      contactoTelefono: _contactoTelefonoController.text,
    );
    _nombreController.clear();
    _direccionController.clear();
    _contactoNombreController.clear();
    _contactoTelefonoController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Mis Sedes y Sucursales Corporativas',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.dark,
          ),
        ),
      ),
      body: BlocBuilder<SedesEmpresaCubit, SedesEmpresaState>(
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.error != null) ...[
                      Container(
                        key: const Key('banner_error_sedes'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXl,
                          ),
                          border: Border.all(color: AppTheme.error, width: 2),
                        ),
                        child: Text(
                          state.error!,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildFormularioNuevaSede(state.cargando),
                    const SizedBox(height: 24),
                    Text(
                      'Sedes Registradas (${state.sedes.length})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.dark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...state.sedes.map(_buildSedeCard),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormularioNuevaSede(bool cargando) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowSm],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Registrar Nueva Sede / Sucursal',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.dark,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('input_nombre_sede'),
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la sede (ej. Sede Norte)',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'El nombre de la sede es obligatorio'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('input_direccion_sede'),
              controller: _direccionController,
              decoration: const InputDecoration(
                labelText: 'Dirección física de la sede',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'La dirección es obligatoria'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('dropdown_zona_sede'),
              initialValue: _zonaSeleccionada,
              decoration: const InputDecoration(labelText: 'Zona de cobertura'),
              items: widget.zonasDisponibles.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _zonaSeleccionada = val);
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('input_contacto_sede'),
              controller: _contactoNombreController,
              decoration: const InputDecoration(
                labelText: 'Encargado en sitio (opcional)',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('btn_agregar_sede'),
              onPressed: cargando ? null : _guardarSede,
              child: Text(cargando ? 'GUARDANDO...' : 'AGREGAR SEDE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSedeCard(SedeEmpresa sede) {
    return Container(
      key: Key('sede_card_${sede.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.business_rounded, color: AppTheme.dark, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sede.nombre,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dark,
                  ),
                ),
                Text(
                  '${sede.direccion} · Zona: ${sede.zonaId}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
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
