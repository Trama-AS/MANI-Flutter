import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:mani/features/auth/presentation/validators/cliente_empresa_validators.dart';
import 'package:mani/features/auth/presentation/widgets/terminos_condiciones_section.dart';

/// Registro de cliente empresa (HU-M02-07, RF-08): la empresa que contrata
/// servicios crea su cuenta con NIT y representante legal. Las sedes no se
/// piden aquí: se administran después, con sesión iniciada (M-03).
class RegistroClienteEmpresaPage extends StatelessWidget {
  const RegistroClienteEmpresaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AuthCubit>(),
      child: const RegistroClienteEmpresaView(),
    );
  }
}

/// Vista del formulario; recibe el [AuthCubit] del contexto (las pruebas
/// inyectan uno propio).
class RegistroClienteEmpresaView extends StatefulWidget {
  const RegistroClienteEmpresaView({super.key});

  /// Mismo tenant por defecto que el registro de cliente persona natural.
  static const String defaultTenantId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

  @override
  State<RegistroClienteEmpresaView> createState() =>
      _RegistroClienteEmpresaViewState();
}

class _RegistroClienteEmpresaViewState
    extends State<RegistroClienteEmpresaView> {
  final _formKey = GlobalKey<FormState>();
  final _razonSocialController = TextEditingController();
  final _nitController = TextEditingController();
  final _representanteController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _aceptaTerminos = false;
  bool _mostrarErrorTerminos = false;

  @override
  void dispose() {
    _razonSocialController.dispose();
    _nitController.dispose();
    _representanteController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleRegistro() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_aceptaTerminos) {
      setState(() => _mostrarErrorTerminos = true);
      _showNotification(AuthCubit.mensajeTerminosObligatorios);
      return;
    }

    context.read<AuthCubit>().registerClienteEmpresa(
      email: _emailController.text,
      password: _passwordController.text,
      razonSocial: _razonSocialController.text,
      nit: ClienteEmpresaValidators.normalizarNit(_nitController.text),
      nombreRepresentante: _representanteController.text,
      tenantId: RegistroClienteEmpresaView.defaultTenantId,
      telefono: _telefonoController.text,
      aceptaTerminos: _aceptaTerminos,
    );
  }

  void _mostrarExito() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius2xl),
          side: const BorderSide(color: AppTheme.dark, width: 3),
        ),
        title: Text(
          '¡Cuenta de Empresa Creada!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppTheme.dark,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            'Tu empresa ya puede iniciar sesión. Después podrás registrar sus sedes desde tu perfil.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.dark,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/login');
            },
            child: Text(
              'IR AL INICIO DE SESIÓN',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w900,
                color: AppTheme.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthRegistrationSuccess) {
          _mostrarExito();
        } else if (state is AuthError) {
          _showNotification(state.message);
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.dark,
            title: Text(
              'Registro de Cliente Empresa',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900),
            ),
            leading: IconButton(
              tooltip: 'Iniciar sesión',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/login'),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _seccion(
                          Icons.business_outlined,
                          '1. Datos de la empresa',
                          [
                            _campo(
                              key: const Key('razonSocial'),
                              label: 'RAZÓN SOCIAL',
                              controller: _razonSocialController,
                              hint: 'Ej: Constructora Andina SAS',
                              icon: Icons.apartment_outlined,
                              validator: (v) =>
                                  ClienteEmpresaValidators.obligatorio(
                                    v,
                                    'La razón social es obligatoria',
                                  ),
                            ),
                            _campo(
                              key: const Key('nit'),
                              label: 'NIT',
                              controller: _nitController,
                              hint: '900.123.456-7',
                              icon: Icons.badge_outlined,
                              validator: ClienteEmpresaValidators.nit,
                            ),
                            _campo(
                              key: const Key('nombreRepresentante'),
                              label: 'REPRESENTANTE LEGAL',
                              controller: _representanteController,
                              hint: 'Nombre completo del representante',
                              icon: Icons.person_outline,
                              validator: (v) =>
                                  ClienteEmpresaValidators.obligatorio(
                                    v,
                                    'El representante legal es obligatorio',
                                  ),
                            ),
                            _campo(
                              key: const Key('telefono'),
                              label: 'TELÉFONO DE CONTACTO (OPCIONAL)',
                              controller: _telefonoController,
                              hint: '+57 601 123 4567',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _seccion(
                          Icons.lock_rounded,
                          '2. Credenciales de acceso',
                          [
                            _campo(
                              key: const Key('email'),
                              label: 'CORREO ELECTRÓNICO',
                              controller: _emailController,
                              hint: 'compras@empresa.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: ClienteEmpresaValidators.email,
                            ),
                            _campo(
                              key: const Key('password'),
                              label: 'CONTRASEÑA',
                              controller: _passwordController,
                              hint: '••••••••',
                              icon: Icons.key_outlined,
                              obscure: !_showPassword,
                              validator: ClienteEmpresaValidators.password,
                              suffix: TextButton(
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                child: Text(_showPassword ? 'OCULTAR' : 'VER'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TerminosCondicionesSection(
                          aceptaTerminos: _aceptaTerminos,
                          mostrarError: _mostrarErrorTerminos,
                          onChanged: (val) => setState(() {
                            _aceptaTerminos = val;
                            if (val) _mostrarErrorTerminos = false;
                          }),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            key: const Key('crearCuentaEmpresa'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: AppTheme.dark,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusXl,
                                ),
                                side: const BorderSide(
                                  color: AppTheme.dark,
                                  width: 2,
                                ),
                              ),
                            ),
                            onPressed: isLoading ? null : _handleRegistro,
                            child: isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppTheme.dark,
                                    ),
                                  )
                                : Text(
                                    'CREAR LA CUENTA DE MI EMPRESA',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _seccion(IconData icon, String titulo, List<Widget> campos) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowMd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.dark, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...campos,
        ],
      ),
    );
  }

  Widget _campo({
    required Key key,
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.dark,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: key,
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscure,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: AppTheme.dark, size: 18),
              suffixIcon: suffix,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                borderSide: const BorderSide(color: AppTheme.dark, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
