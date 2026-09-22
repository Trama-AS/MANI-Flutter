import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final Set<String> _selectedIds = {};
  bool _attemptedSave = false;

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _save() {
    setState(() {
      _attemptedSave = true;
    });

    if (_selectedIds.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Categorías guardadas')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showError = _attemptedSave && _selectedIds.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF6EFDA),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
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
                      border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 18, color: Color(0xFF1A1A1A)),
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

            // Subtitle
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Selecciona lo que sabes hacer. Solo verás avisos de trabajos en estas áreas.',
                style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFF5B5648)),
              ),
            ),

            // Category list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                itemCount: mockCategories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final cat = mockCategories[index];
                  final isSelected = _selectedIds.contains(cat.id);

                  return GestureDetector(
                    onTap: () => _toggle(cat.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF5C518) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                        boxShadow: isSelected
                            ? [const BoxShadow(color: Color(0xFF1A1A1A), offset: Offset(2, 2), blurRadius: 0)]
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
                                  color: isSelected ? Colors.white : const Color(0xFFF6EFDA),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                                ),
                                alignment: Alignment.center,
                                child: Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                cat.label,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
                              ),
                            ],
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Color(0xFF1A1A1A))
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Error banner
            if (showError)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4342D), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0xFFE4342D), offset: Offset(2, 2), blurRadius: 0)],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Color(0xFFE4342D)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecciona al menos una categoría para continuar.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFE4342D)),
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
              decoration: const BoxDecoration(
                color: Color(0xFFF6EFDA),
                border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedIds.length} categoría(s) seleccionada(s)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5B5648)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE4342D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFF1A1A1A), width: 2),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'GUARDAR',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}