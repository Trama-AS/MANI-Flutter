import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';

import '../../domain/entities/motivo_rechazo.dart';
import '../../domain/entities/solicitud_entity.dart';

/// Resultado del diálogo: el motivo es opcional.
typedef ConfirmacionRechazo = ({MotivoRechazo? motivo});

/// Confirma el rechazo y pide un motivo opcional. Devuelve `null` si el
/// aliado cancela.
Future<ConfirmacionRechazo?> confirmarRechazo(
  BuildContext context,
  SolicitudEntity solicitud,
) => showDialog<ConfirmacionRechazo>(
  context: context,
  builder: (_) => _DialogoRechazo(solicitud: solicitud),
);

class _DialogoRechazo extends StatefulWidget {
  const _DialogoRechazo({required this.solicitud});

  final SolicitudEntity solicitud;

  @override
  State<_DialogoRechazo> createState() => _DialogoRechazoState();
}

class _DialogoRechazoState extends State<_DialogoRechazo> {
  MotivoRechazo? _motivo;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius2xl),
        side: const BorderSide(color: AppTheme.dark, width: 3),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      title: Text(
        '¿Rechazar ${widget.solicitud.categoria}?',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No volverás a verla. Seguirá disponible para otros aliados, '
              'así el cliente no se queda sin servicio.',
            ),
            const SizedBox(height: 16),
            const Text(
              '¿Por qué? (opcional)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in MotivoRechazo.values)
                  ChoiceChip(
                    key: ValueKey('motivo-${m.codigo}'),
                    label: Text(
                      m.etiqueta,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: _motivo == m,
                    onSelected: (sel) =>
                        setState(() => _motivo = sel ? m : null),
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.dark, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            ManiButton(
              key: const ValueKey('dlg-cancelar-rechazo'),
              etiqueta: 'Volver',
              variante: ManiButtonVariante.secundario,
              onPressed: () => Navigator.pop(context),
            ),
            ManiButton(
              key: const ValueKey('dlg-confirmar-rechazo'),
              etiqueta: 'Rechazar',
              icono: Icons.close_rounded,
              variante: ManiButtonVariante.peligro,
              onPressed: () => Navigator.pop<ConfirmacionRechazo>(context, (
                motivo: _motivo,
              )),
            ),
          ],
        ),
      ],
    );
  }
}
