import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/features/profiles/direct_employees/presentation/bloc/empleado_directo_cubit.dart';

/// Pantalla de administración del Tenant para registrar empleados directos
/// que quedan con estado `VERIFICADO` inmediato sin pasar por cola KYC (US-02.1.5 / SCRUM-850).
class RegistrarEmpleadoDirectoPage extends StatefulWidget {
  const RegistrarEmpleadoDirectoPage({
    super.key,
    this.categoriasDisponibles = const {
      'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a18': 'Plomería y Redes Hidráulicas',
      'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a19': 'Electricidad Residencial',
      'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a20': 'Cerrajería y Seguridad',
    },
  });

  final Map<String, String> categoriasDisponibles;

  @override
  State<RegistrarEmpleadoDirectoPage> createState() =>
      _RegistrarEmpleadoDirectoPageState();
}

class _RegistrarEmpleadoDirectoPageState
    extends State<RegistrarEmpleadoDirectoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _telefonoController = TextEditingController();

  final Set<String> _categoriasSeleccionadas = {};

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<EmpleadoDirectoCubit>().registrar(
      email: _emailController.text,
      password: _passwordController.text,
      nombreCompleto: _nombreController.text,
      telefono: _telefonoController.text,
      categoriaIds: _categoriasSeleccionadas.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Registrar Empleado Directo del Tenant',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.dark,
          ),
        ),
      ),
      body: BlocConsumer<EmpleadoDirectoCubit, EmpleadoDirectoState>(
        listener: (context, state) {
          if (state is EmpleadoDirectoError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: const Key('snackbar_error_empleado_directo'),
                backgroundColor: AppTheme.error,
                content: Text(state.message),
              ),
            );
          }
        },
        builder: (context, state) {
          final cargando = state is EmpleadoDirectoLoading;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBannerInfo(),
                      const SizedBox(height: 20),
                      if (state is EmpleadoDirectoRegistrado) ...[
                        _buildConfirmacionCard(state),
                        const SizedBox(height: 20),
                      ],
                      _buildFormularioCard(cargando),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBannerInfo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(color: AppTheme.dark, width: 2.5),
        boxShadow: const [AppTheme.hardShadowSm],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: AppTheme.dark,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activación Inmediata (Estado VERIFICADO)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.dark,
                  ),
                ),
                Text(
                  'Los empleados directos creados por el administrador del tenant no pasan por la bandeja de revisión KYC y quedan habilitados de inmediato para recibir servicios.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmacionCard(EmpleadoDirectoRegistrado state) {
    final emp = state.empleado;
    return Container(
      key: const Key('card_empleado_directo_creado'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(color: AppTheme.dark, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Empleado Directo Registrado: ${emp.nombreCompleto}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Estado: ${emp.estadoVerificacion} · Nómina directa: ${emp.esEmpleadoDirecto ? "SÍ" : "NO"}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioCard(bool cargando) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowMd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('input_nombre_empleado_directo'),
            controller: _nombreController,
            decoration: const InputDecoration(
              labelText: 'Nombre completo del técnico',
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'El nombre es obligatorio'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('input_email_empleado_directo'),
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico corporativo',
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'El correo es obligatorio'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('input_password_empleado_directo'),
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña inicial (mín. 8 caracteres)',
            ),
            validator: (v) =>
                (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('input_telefono_empleado_directo'),
            controller: _telefonoController,
            decoration: const InputDecoration(
              labelText: 'Teléfono de contacto (opcional)',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Categorías Operativas Asignadas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.dark,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.categoriasDisponibles.entries.map((entry) {
            final seleccionado = _categoriasSeleccionadas.contains(entry.key);
            return Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: Key('chk_categoria_${entry.key}'),
                value: seleccionado,
                title: Text(entry.value),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _categoriasSeleccionadas.add(entry.key);
                    } else {
                      _categoriasSeleccionadas.remove(entry.key);
                    }
                  });
                },
              ),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton(
            key: const Key('btn_registrar_empleado_directo'),
            onPressed: cargando ? null : _enviar,
            child: Text(
              cargando ? 'REGISTRANDO...' : 'CREAR EMPLEADO DIRECTO VERIFICADO',
            ),
          ),
        ],
      ),
    );
  }
}
