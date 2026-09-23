import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';

import '../../domain/entities/categoria_servicio.dart';
import '../../domain/entities/flujo_operativo.dart';
import '../../domain/entities/nueva_categoria.dart';
import '../../domain/failures/categoria_failure.dart';
import '../bloc/categorias_cubit.dart';
import 'flujo_operativo_estilo.dart';

/// Abre el formulario "Nueva categoría": diálogo en escritorio, hoja inferior
/// en móvil. Devuelve `true` si se creó la categoría.
Future<bool> mostrarFormularioCategoria(BuildContext context) async {
  final cubit = context.read<CategoriasCubit>();
  final contenido = BlocProvider.value(
    value: cubit,
    child: const FormularioCategoria(),
  );
  final bool? creada;
  if (MediaQuery.sizeOf(context).width >= 720) {
    creada = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius2xl),
          side: const BorderSide(color: AppTheme.dark, width: 3),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
          child: contenido,
        ),
      ),
    );
  } else {
    creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radius2xl),
        ),
        side: BorderSide(color: AppTheme.dark, width: 2),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          child: contenido,
        ),
      ),
    );
  }
  return creada ?? false;
}

class FormularioCategoria extends StatefulWidget {
  const FormularioCategoria({super.key});

  /// Nombres frecuentes; solo se sugieren los que el tenant aún no tiene.
  static const sugerencias = [
    'Plomería',
    'Electricidad',
    'Cerrajería',
    'Pintura',
    'Carpintería',
    'Aire acondicionado',
    'Jardinería',
    'Limpieza',
  ];

  @override
  State<FormularioCategoria> createState() => _FormularioCategoriaState();
}

class _FormularioCategoriaState extends State<FormularioCategoria> {
  final _nombre = TextEditingController();
  FlujoOperativo? _flujo;
  bool _activa = true;
  bool _nombreTocado = false;

  /// Error devuelto por el servidor en el último intento.
  CategoriaFailure? _errorEnvio;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  CategoriaServicio? _duplicada(List<CategoriaServicio> existentes) =>
      NuevaCategoria.buscarDuplicada(_nombre.text, existentes);

  String? _errorNombre(List<CategoriaServicio> existentes) {
    final duplicada = _duplicada(existentes);
    if (duplicada != null) {
      return 'Ya tienes la categoría "${duplicada.nombre}" en tu catálogo.';
    }
    if (_errorEnvio?.tipo == CategoriaErrorTipo.nombreDuplicado) {
      return _errorEnvio!.mensajeUsuario;
    }
    if (_nombreTocado && NuevaCategoria.validarNombre(_nombre.text) != null) {
      return 'Usa entre ${NuevaCategoria.nombreMinimo} y '
          '${NuevaCategoria.nombreMaximo} caracteres, con al menos una letra.';
    }
    return null;
  }

  void _usarSugerencia(String nombre) {
    _nombre.value = TextEditingValue(
      text: nombre,
      selection: TextSelection.collapsed(offset: nombre.length),
    );
    setState(() {
      _nombreTocado = true;
      _errorEnvio = null;
    });
  }

  Future<void> _crear() async {
    setState(() => _nombreTocado = true);
    final falla = await context.read<CategoriasCubit>().crear(
      nombre: _nombre.text,
      flujo: _flujo,
      activa: _activa,
    );
    if (!mounted) {
      return;
    }
    if (falla == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errorEnvio = falla);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CategoriasCubit, CategoriasState>(
      buildWhen: (a, b) =>
          a.guardando != b.guardando || a.categorias != b.categorias,
      builder: (context, state) {
        final existentes = state.categorias;
        final errorNombre = _errorNombre(existentes);
        final nombreValido =
            NuevaCategoria.validarNombre(_nombre.text) == null &&
            _duplicada(existentes) == null;
        final puedeCrear = nombreValido && _flujo != null && !state.guardando;
        final errorGeneral = switch (_errorEnvio?.tipo) {
          null || CategoriaErrorTipo.nombreDuplicado => null,
          _ => _errorEnvio!.mensajeUsuario,
        };
        final clavesExistentes = existentes.map((c) => c.claveNombre).toSet();
        final sugerencias = FormularioCategoria.sugerencias
            .where((s) => !clavesExistentes.contains(normalizarClaveNombre(s)))
            .take(6)
            .toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Encabezado(onCerrar: () => Navigator.of(context).pop(false)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Paso(numero: 1, titulo: 'Nombre de la categoría'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('campo-nombre-categoria'),
                      controller: _nombre,
                      autofocus: true,
                      maxLength: NuevaCategoria.nombreMaximo,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      enabled: !state.guardando,
                      onChanged: (_) => setState(() => _errorEnvio = null),
                      // Al sobrescribir onEditingComplete hay que cerrar el
                      // teclado a mano (el comportamiento por defecto se pierde).
                      onEditingComplete: () {
                        setState(() => _nombreTocado = true);
                        FocusScope.of(context).unfocus();
                      },
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      decoration: _decoracion(
                        hint: 'Ej: Plomería',
                        error: errorNombre,
                      ),
                    ),
                    if (sugerencias.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Sugerencias',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in sugerencias)
                            ActionChip(
                              key: ValueKey('sugerencia-$s'),
                              label: Text(
                                s,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: state.guardando
                                  ? null
                                  : () => _usarSugerencia(s),
                              backgroundColor: AppTheme.surface,
                              side: const BorderSide(
                                color: AppTheme.dark,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const _Paso(
                      numero: 2,
                      titulo: '¿Cómo opera este servicio?',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Define qué pasa cuando un cliente solicita un servicio de esta categoría.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final f in FlujoOperativo.values) ...[
                      _OpcionFlujo(
                        flujo: f,
                        seleccionado: _flujo == f,
                        onTap: state.guardando
                            ? null
                            : () => setState(() {
                                _flujo = f;
                                _errorEnvio = null;
                              }),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    const _Paso(numero: 3, titulo: 'Visibilidad'),
                    const SizedBox(height: 6),
                    // Material propio: el ListTile pinta ahí su fondo y el
                    // efecto de toque (un Container con color los ocultaría).
                    Material(
                      color: AppTheme.surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        side: const BorderSide(color: AppTheme.dark, width: 2),
                      ),
                      child: SwitchListTile(
                        key: const ValueKey('switch-visible'),
                        value: _activa,
                        onChanged: state.guardando
                            ? null
                            : (v) => setState(() => _activa = v),
                        activeThumbColor: AppTheme.dark,
                        activeTrackColor: AppTheme.primary,
                        title: const Text(
                          'Visible para clientes de inmediato',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          _activa
                              ? 'Aparecerá en el catálogo apenas la crees.'
                              : 'Quedará oculta hasta que la actives.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _VistaPrevia(
                      nombre: normalizarNombre(_nombre.text),
                      flujo: _flujo,
                      activa: _activa,
                    ),
                    if (errorGeneral != null) ...[
                      const SizedBox(height: 16),
                      _ErrorEnvio(mensaje: errorGeneral),
                    ],
                  ],
                ),
              ),
            ),
            _Acciones(
              puedeCrear: puedeCrear,
              guardando: state.guardando,
              pista: switch ((nombreValido, _flujo)) {
                _ when state.guardando || puedeCrear => null,
                (false, null) => 'Escribe un nombre y elige cómo opera.',
                (false, _) => 'Escribe un nombre válido para continuar.',
                (true, null) => 'Elige cómo opera la categoría para continuar.',
                _ => null,
              },
              onCancelar: () => Navigator.of(context).pop(false),
              onCrear: _crear,
            ),
          ],
        );
      },
    );
  }

  InputDecoration _decoracion({required String hint, String? error}) {
    OutlineInputBorder borde(Color color, double ancho) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      borderSide: BorderSide(color: color, width: ancho),
    );
    return InputDecoration(
      hintText: hint,
      helperText: 'Entre 3 y 60 caracteres. Es lo que verán tus clientes.',
      errorText: error,
      errorMaxLines: 2,
      filled: true,
      fillColor: AppTheme.surface,
      prefixIcon: const Icon(Icons.category_outlined, color: AppTheme.dark),
      enabledBorder: borde(AppTheme.dark, 2),
      focusedBorder: borde(AppTheme.dark, 2.5),
      disabledBorder: borde(AppTheme.borderLight, 2),
      errorBorder: borde(AppTheme.error, 2),
      focusedErrorBorder: borde(AppTheme.error, 2.5),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.onCerrar});

  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 2),
            ),
            child: const Icon(Icons.add_business_rounded, color: AppTheme.dark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nueva categoría',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Organiza el catálogo que ven tus clientes.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onCerrar,
            icon: const Icon(Icons.close_rounded, color: AppTheme.dark),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.titulo});

  final int numero;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.dark,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$numero',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta seleccionable de un flujo operativo (comportamiento de radio).
class _OpcionFlujo extends StatelessWidget {
  const _OpcionFlujo({
    required this.flujo,
    required this.seleccionado,
    required this.onTap,
  });

  final FlujoOperativo flujo;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(AppTheme.radiusXl);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: seleccionado,
      button: true,
      label: '${flujo.etiqueta}. ${flujo.descripcion}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: seleccionado ? flujo.fondo : AppTheme.surface,
          borderRadius: radio,
          border: Border.all(
            color: AppTheme.dark,
            width: seleccionado ? 2.5 : 1.5,
          ),
          boxShadow: [if (seleccionado) AppTheme.hardShadowSm],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('flujo-${flujo.codigo}'),
            borderRadius: radio,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: seleccionado ? AppTheme.surface : flujo.fondo,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.dark, width: 1.5),
                    ),
                    child: Icon(flujo.icono, color: flujo.acento, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          flujo.etiqueta,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          flujo.descripcion,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          flujo.ejemplo,
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    seleccionado
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: AppTheme.dark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Así la verán tus clientes": refuerza el efecto de cada elección.
class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({
    required this.nombre,
    required this.flujo,
    required this.activa,
  });

  final String nombre;
  final FlujoOperativo? flujo;
  final bool activa;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('vista-previa-categoria'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ASÍ LA VERÁN TUS CLIENTES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (!activa)
            const Row(
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Oculta: tus clientes no la verán todavía.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.dark, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.home_repair_service_rounded,
                    color: AppTheme.dark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre.isEmpty ? 'Nombre de la categoría' : nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: nombre.isEmpty
                                ? AppTheme.textTertiary
                                : AppTheme.dark,
                          ),
                        ),
                        Text(
                          flujo?.textoCliente ?? 'Elige cómo opera el servicio',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textTertiary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorEnvio extends StatelessWidget {
  const _ErrorEnvio({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('error-envio-categoria'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.error, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.puedeCrear,
    required this.guardando,
    required this.onCancelar,
    required this.onCrear,
    this.pista,
  });

  final bool puedeCrear;
  final bool guardando;
  final VoidCallback onCancelar;
  final VoidCallback onCrear;

  /// Qué falta para habilitar "Crear categoría".
  final String? pista;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pista != null) ...[
              Text(
                pista!,
                key: const ValueKey('pista-formulario-categoria'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            _botones(),
          ],
        ),
      ),
    );
  }

  Widget _botones() {
    return Row(
      children: [
        Expanded(
          child: ManiButton(
            key: const ValueKey('btn-cancelar-categoria'),
            etiqueta: 'Cancelar',
            variante: ManiButtonVariante.secundario,
            expandir: true,
            onPressed: guardando ? null : onCancelar,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ManiButton(
            key: const ValueKey('btn-crear-categoria'),
            etiqueta: guardando ? 'Creando…' : 'Crear categoría',
            icono: Icons.check_rounded,
            expandir: true,
            cargando: guardando,
            onPressed: puedeCrear ? onCrear : null,
          ),
        ),
      ],
    );
  }
}
