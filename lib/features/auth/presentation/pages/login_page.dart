import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';

/// Pantalla de inicio de sesión de MANI.
/// Replicada pixel-perfect del prototipo oficial en Figma:
/// - Fondo crema: #FDFBF7
/// - Logo amarillo con M gruesa y hard-shadow
/// - Título MANI con tracking tight
/// - Selector de Empresa / Tenant con borde negro
/// - Selector de rol con 3 pestañas: Soy Cliente, Soy Aliado, Admin
/// - Inputs con bordes negros 2px, fondo blanco y placeholder gris
/// - Botón "INGRESAR A MANI" amarillo con sombra dura de 4px
/// - Enlaces inferiores: "¿Olvidaste tu contraseña?" • "Registrarme"
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AuthCubit>(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = 'cliente'; // 'cliente', 'aliado', 'admin'
  String _selectedTenant = 'Plomería Express CDMX SA';
  bool _showPassword = false;

  final List<String> _tenants = const [
    'Plomería Express CDMX SA',
    'Electricistas Pro Monterrey',
    'Cerrajería Total GDL',
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<AuthCubit>().login(
      _emailController.text,
      _passwordController.text,
    );
  }

  void _showNotification(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: isError ? Colors.white : AppTheme.dark,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          side: const BorderSide(color: AppTheme.dark, width: 2),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _showNotification('¡Bienvenido a MANI!', isError: false);
          // US-02.1.3: el admin del tenant entra directo a su bandeja de
          // verificación. Si la cuenta no es ADMIN_TENANT, el servidor
          // responde 403 y la bandeja lo informa; la pestaña no otorga
          // permisos por sí sola.
          if (_selectedRole == 'admin') {
            context.go('/admin/verificacion-aliados');
          }
        } else if (state is AuthError) {
          _showNotification(state.message);
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header (Logo + Títulos) ───────────────────────
                        _buildLogoHeader(),
                        const SizedBox(height: 24),

                        // ── Selector de Tenant ─────────────────────────────
                        _buildTenantSelector(),
                        const SizedBox(height: 16),

                        // ── Selector de Rol (Tabs) ─────────────────────────
                        _buildRoleTabs(),
                        const SizedBox(height: 18),

                        // ── Inputs ─────────────────────────────────────────
                        _buildInputs(),
                        const SizedBox(height: 24),

                        // ── Botón INGRESAR A MANI ──────────────────────────
                        _buildSubmitButton(isLoading),
                        const SizedBox(height: 20),

                        // ── Enlaces inferiores ─────────────────────────────
                        _buildFooterLinks(),
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

  Widget _buildLogoHeader() {
    return Column(
      children: [
        // Ícono / Logo cuadrado amarillo con 'M'
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(AppTheme.radius2xl),
            border: Border.all(color: AppTheme.dark, width: 3),
            boxShadow: const [AppTheme.hardShadowLg],
          ),
          alignment: Alignment.center,
          child: Text(
            'M',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: AppTheme.dark,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'MANI',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: AppTheme.dark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Plataforma Digital de Servicios',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTenantSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EMPRESA / TENANT',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTheme.dark,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: AppTheme.dark, width: 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTenant,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.dark),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.dark,
              ),
              items: _tenants.map((tenant) {
                return DropdownMenuItem<String>(
                  value: tenant,
                  child: Text(tenant),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedTenant = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleTabs() {
    final roles = [
      {'key': 'cliente', 'label': 'Soy Cliente'},
      {'key': 'aliado', 'label': 'Soy Aliado'},
      {'key': 'admin', 'label': 'Admin'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowMd],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: roles.map((role) {
          final isSelected = _selectedRole == role['key'];
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedRole = role['key']!),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: isSelected ? AppTheme.primary : AppTheme.surface,
                alignment: Alignment.center,
                child: Text(
                  role['label']!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: isSelected ? AppTheme.dark : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Correo electrónico
        Text(
          'CORREO ELECTRÓNICO',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTheme.dark,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.dark,
          ),
          decoration: InputDecoration(
            hintText: 'hola@mani.app',
            hintStyle: GoogleFonts.plusJakartaSans(
              color: AppTheme.textTertiary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2.5),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'El correo es requerido';
            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
              return 'Ingresa un correo válido';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),

        // Contraseña
        Text(
          'CONTRASEÑA',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTheme.dark,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.dark,
          ),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: GoogleFonts.plusJakartaSans(
              color: AppTheme.textTertiary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            suffixIcon: TextButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              child: Text(
                _showPassword ? 'OCULTAR' : 'VER',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              borderSide: const BorderSide(color: AppTheme.dark, width: 2.5),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'La contraseña es requerida';
            if (v.length < 6) return 'Mínimo 6 caracteres';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSubmitButton(bool isLoading) {
    return GestureDetector(
      onTap: isLoading ? null : _handleLogin,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: isLoading ? AppTheme.textTertiary : AppTheme.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(color: AppTheme.dark, width: 2),
          boxShadow: isLoading ? [] : const [AppTheme.hardShadowMd],
        ),
        alignment: Alignment.center,
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
                'INGRESAR A MANI',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppTheme.dark,
                ),
              ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    final isAliado = _selectedRole == 'aliado';

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            // TODO: Pantalla de recuperación
          },
          child: Text(
            '¿Olvidaste tu contraseña?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Divisor "¿NO TIENES CUENTA?"
        Row(
          children: [
            const Expanded(
              child: Divider(color: AppTheme.dark, thickness: 1.5),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '¿NO TIENES CUENTA?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const Expanded(
              child: Divider(color: AppTheme.dark, thickness: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Botón 1: Registrarme como Cliente
        GestureDetector(
          onTap: () => context.go('/register-cliente'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: !isAliado ? Colors.white : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(
                color: AppTheme.dark,
                width: !isAliado ? 2 : 1.5,
              ),
              boxShadow: !isAliado ? const [AppTheme.hardShadowSm] : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.home_outlined, color: AppTheme.dark, size: 18),
                const SizedBox(width: 8),
                Text(
                  'REGISTRARME COMO CLIENTE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Botón 2: Registrarme como Aliado Técnico
        GestureDetector(
          onTap: () => context.go('/register-aliado'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isAliado ? Colors.white : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(
                color: AppTheme.dark,
                width: isAliado ? 2 : 1.5,
              ),
              boxShadow: isAliado ? const [AppTheme.hardShadowSm] : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.handyman_outlined,
                  color: AppTheme.dark,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'REGISTRARME COMO ALIADO TÉCNICO',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Botón 3: Registrar Empresa de Servicios (US-02.1.2)
        GestureDetector(
          onTap: () => context.go('/register-empresa'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(color: AppTheme.dark, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.business_outlined,
                  color: AppTheme.dark,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'REGISTRAR MI EMPRESA DE SERVICIOS',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
