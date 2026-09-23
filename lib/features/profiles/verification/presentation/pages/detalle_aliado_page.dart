import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../widgets/detalle_aliado_panel.dart';

/// Detalle de un aliado en pantallas angostas. Requiere que el
/// `BandejaVerificacionCubit` de la bandeja esté disponible en el contexto.
class DetalleAliadoPage extends StatelessWidget {
  const DetalleAliadoPage({super.key, required this.aliadoId});

  final String aliadoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        foregroundColor: AppTheme.dark,
        shape: const Border(bottom: BorderSide(color: AppTheme.dark, width: 2)),
        title: const Text(
          'Perfil del aliado',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: DetalleAliadoPanel(
        aliadoId: aliadoId,
        onResuelto: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
