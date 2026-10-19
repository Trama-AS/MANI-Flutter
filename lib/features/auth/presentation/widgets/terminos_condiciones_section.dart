import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/features/auth/presentation/widgets/documento_legal_modal.dart';

/// Sección reutilizable de aceptación de Términos y Condiciones y Política de
/// Tratamiento de Datos Personales durante el registro (SCRUM-856 / SCRUM-1036).
///
/// Incluye:
/// - Checkbox obligatorio de consentimiento informado.
/// - Enlaces visibles para abrir el modal con el documento legal completo
///   ([DocumentoLegalModal], SCRUM-1037).
/// - Estado de error visual cuando se intenta enviar el formulario sin aceptar.
class TerminosCondicionesSection extends StatelessWidget {
  const TerminosCondicionesSection({
    super.key,
    required this.aceptaTerminos,
    required this.onChanged,
    this.mostrarError = false,
  });

  final bool aceptaTerminos;
  final ValueChanged<bool> onChanged;
  final bool mostrarError;

  Future<void> _abrirModal(
    BuildContext context,
    TipoDocumentoLegal tipo,
  ) async {
    await DocumentoLegalModal.mostrar(
      context,
      documentoInicial: tipo,
      onAceptar: () => onChanged(true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('seccion_terminos_condiciones'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        border: Border.all(
          color: mostrarError ? AppTheme.error : AppTheme.dark,
          width: mostrarError ? 2.5 : 2,
        ),
        boxShadow: const [AppTheme.hardShadowSm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  key: const Key('checkbox_aceptacion_terminos'),
                  value: aceptaTerminos,
                  activeColor: AppTheme.dark,
                  checkColor: AppTheme.primary,
                  side: BorderSide(
                    color: mostrarError ? AppTheme.error : AppTheme.dark,
                    width: 2,
                  ),
                  onChanged: (val) => onChanged(val ?? false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consentimiento Legal y Protección de Datos (Obligatorio)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'He leído y acepto de manera libre, previa, expresa e informada los Términos y Condiciones (v1.0) y la Política de Tratamiento de Datos Personales conforme a la Ley 1581 de 2012 (Habeas Data).',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _buildDocLinkButton(
                          key: const Key('btn_ver_terminos'),
                          icon: Icons.description_outlined,
                          label: 'Leer Términos y Condiciones (v1.0)',
                          onTap: () => _abrirModal(
                            context,
                            TipoDocumentoLegal.terminosCondiciones,
                          ),
                        ),
                        _buildDocLinkButton(
                          key: const Key('btn_ver_politica_datos'),
                          icon: Icons.privacy_tip_outlined,
                          label: 'Leer Política de Datos (Ley 1581)',
                          onTap: () => _abrirModal(
                            context,
                            TipoDocumentoLegal.politicaDatos,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (mostrarError) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.error,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Debes leer y aceptar los Términos y Condiciones y la Política de Datos Personales para completar el registro.',
                    key: const Key('error_terminos_obligatorios'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocLinkButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.dark, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.dark),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.dark,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
