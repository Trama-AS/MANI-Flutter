import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/features/profile_categories/presentation/bloc/categories_cubit.dart';

/// Pantalla de selección de categorías del aliado (US-03.1.3).
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CategoriesCubit>(),
      child: const CategoriesView(),
    );
  }
}

/// Vista de la pantalla; recibe el cubit del árbol (así la prueban los tests).
class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6EFDA),
      body: SafeArea(
        child: BlocConsumer<CategoriesCubit, CategoriesState>(
          listenWhen: (prev, curr) =>
              (curr.saveSuccess && !prev.saveSuccess) ||
              (curr.saveFailure != null && prev.saveFailure == null),
          listener: (context, state) {
            final messenger = ScaffoldMessenger.of(context);
            if (state.saveSuccess) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Categorías guardadas')),
              );
            } else if (state.saveFailure != null) {
              messenger.showSnackBar(
                SnackBar(content: Text(state.saveFailure!.mensajeUsuario)),
              );
            }
          },
          builder: (context, state) {
            final cubit = context.read<CategoriesCubit>();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1A1A1A),
                            width: 2,
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: Color(0xFF1A1A1A),
                          ),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Mis categorías',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    'Selecciona lo que sabes hacer. Solo verás avisos de trabajos en estas áreas.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B5648),
                    ),
                  ),
                ),
                if (state.isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.loadFailure != null)
                  Expanded(
                    child: _Mensaje(
                      texto: state.loadFailure!.mensajeUsuario,
                      accion: TextButton(
                        key: const ValueKey('btn-reintentar-categorias'),
                        onPressed: cubit.loadCategories,
                        child: const Text('Reintentar'),
                      ),
                    ),
                  )
                else if (state.categories.isEmpty)
                  const Expanded(
                    child: _Mensaje(
                      texto:
                          'Tu organización aún no tiene categorías activas. '
                          'Contacta al administrador.',
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      itemCount: state.categories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final cat = state.categories[index];
                        final isSelected = state.selectedIds.contains(cat.id);
                        return GestureDetector(
                          key: ValueKey('categoria-${cat.id}'),
                          onTap: state.isSaving
                              ? null
                              : () => cubit.toggleCategory(cat.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF5C518)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF1A1A1A),
                                width: 2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      const BoxShadow(
                                        color: Color(0xFF1A1A1A),
                                        offset: Offset(2, 2),
                                        blurRadius: 0,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                            : const Color(0xFFF6EFDA),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFF1A1A1A),
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        cat.emoji,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      cat.label,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: const Color(0xFF1A1A1A),
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Color(0xFF1A1A1A),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (state.showError)
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE4342D),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFFE4342D),
                          offset: Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Color(0xFFE4342D),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Selecciona al menos una categoría para continuar.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE4342D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6EFDA),
                    border: Border(
                      top: BorderSide(color: Color(0xFF1A1A1A), width: 2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${state.selectedIds.length} categoría(s) seleccionada(s)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B5648),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          key: const ValueKey('btn-guardar-categorias'),
                          onPressed:
                              state.isLoading ||
                                  state.isSaving ||
                                  state.loadFailure != null
                              ? null
                              : cubit.save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE4342D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(
                                color: Color(0xFF1A1A1A),
                                width: 2,
                              ),
                            ),
                            elevation: 0,
                          ),
                          child: state.isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'GUARDAR',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5B5648),
              ),
            ),
            if (accion != null) ...[const SizedBox(height: 12), accion!],
          ],
        ),
      ),
    );
  }
}
