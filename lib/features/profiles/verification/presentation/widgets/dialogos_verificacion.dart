import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';

import '../../domain/entities/decision_verificacion.dart';
import '../../domain/entities/solicitud_aliado.dart';

/// Pide confirmar la aprobación. Devuelve `true` si el administrador confirma.
Future<bool> confirmarAprobacion(
  BuildContext context,
  SolicitudAliado aliado,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DialogoMani(
      icono: Icons.verified_rounded,
      colorIcono: AppTheme.success,
      titulo: '¿Aprobar a ${aliado.nombre}?',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Al aprobarlo:'),
          const SizedBox(height: 10),
          const _Punto(
            'Podrá recibir solicitudes de servicio de tus clientes.',
          ),
          const _Punto('Sus documentos quedarán marcados como verificados.'),
          const _Punto('Le notificaremos el resultado automáticamente.'),
          const SizedBox(height: 10),
          Text(
            'Confirma que revisaste ${aliado.documentos.length == 1 ? 'su documento' : 'sus ${aliado.documentos.length} documentos'}.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      acciones: [
        ManiButton(
          key: const ValueKey('dlg-cancelar'),
          etiqueta: 'Cancelar',
          variante: ManiButtonVariante.secundario,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        ManiButton(
          key: const ValueKey('dlg-confirmar-aprobar'),
          etiqueta: 'Sí, aprobar',
          icono: Icons.check_rounded,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Pide el motivo del rechazo. Devuelve el motivo o `null` si se cancela.
Future<String?> pedirMotivoRechazo(
  BuildContext context,
  SolicitudAliado aliado,
) => showDialog<String>(
  context: context,
  builder: (_) => _DialogoRechazo(aliado: aliado),
);

class _DialogoRechazo extends StatefulWidget {
  const _DialogoRechazo({required this.aliado});

  final SolicitudAliado aliado;

  /// Motivos frecuentes: un toque los agrega al texto, que sigue siendo editable.
  static const motivosRapidos = [
    'Documento ilegible',
    'Documento vencido',
    'Los datos no coinciden con el documento',
    'Falta un documento obligatorio',
  ];

  @override
  State<_DialogoRechazo> createState() => _DialogoRechazoState();
}

class _DialogoRechazoState extends State<_DialogoRechazo> {
  final _motivo = TextEditingController();
  bool _intentado = false;

  int get _largo => _motivo.text.trim().length;
  bool get _valido =>
      _largo >= DecisionVerificacion.motivoMinimo &&
      _largo <= DecisionVerificacion.motivoMaximo;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _agregarMotivo(String texto) {
    final actual = _motivo.text.trim();
    if (actual.contains(texto)) return;
    _motivo.text = actual.isEmpty ? '$texto.' : '$actual $texto.';
    _motivo.selection = TextSelection.collapsed(offset: _motivo.text.length);
    setState(() {});
  }

  void _enviar() {
    setState(() => _intentado = true);
    if (_valido) Navigator.pop(context, _motivo.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final mostrarError = _intentado && !_valido;
    return _DialogoMani(
      icono: Icons.block_rounded,
      colorIcono: AppTheme.error,
      titulo: 'Rechazar a ${widget.aliado.nombre}',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'El aliado recibirá este motivo. Sé claro para que sepa qué corregir.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _DialogoRechazo.motivosRapidos)
                ActionChip(
                  label: Text(
                    m,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => _agregarMotivo(m),
                  backgroundColor: AppTheme.background,
                  side: const BorderSide(color: AppTheme.dark, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('campo-motivo-rechazo'),
            controller: _motivo,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: DecisionVerificacion.motivoMaximo,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Ej: La foto de la cédula está borrosa, vuelve a cargarla.',
              filled: true,
              fillColor: AppTheme.surface,
              errorText: mostrarError
                  ? 'Escribe al menos ${DecisionVerificacion.motivoMinimo} caracteres.'
                  : null,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                borderSide: const BorderSide(color: AppTheme.dark, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                borderSide: const BorderSide(color: AppTheme.dark, width: 2.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                borderSide: const BorderSide(color: AppTheme.error, width: 2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                borderSide: const BorderSide(color: AppTheme.error, width: 2.5),
              ),
            ),
          ),
        ],
      ),
      acciones: [
        ManiButton(
          key: const ValueKey('dlg-cancelar'),
          etiqueta: 'Cancelar',
          variante: ManiButtonVariante.secundario,
          onPressed: () => Navigator.pop(context),
        ),
        ManiButton(
          key: const ValueKey('dlg-confirmar-rechazar'),
          etiqueta: 'Rechazar aliado',
          icono: Icons.close_rounded,
          variante: ManiButtonVariante.peligro,
          onPressed: _enviar,
        ),
      ],
    );
  }
}

class _DialogoMani extends StatelessWidget {
  const _DialogoMani({
    required this.icono,
    required this.colorIcono,
    required this.titulo,
    required this.contenido,
    required this.acciones,
  });

  final IconData icono;
  final Color colorIcono;
  final String titulo;
  final Widget contenido;
  final List<Widget> acciones;

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
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 2),
            ),
            child: Icon(icono, color: colorIcono),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.dark,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(child: contenido),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: acciones,
        ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(texto)),
      ],
    ),
  );
}
