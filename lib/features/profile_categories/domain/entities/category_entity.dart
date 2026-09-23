import 'package:equatable/equatable.dart';

/// Entidad de dominio que representa una categoría de servicio.
class CategoryEntity extends Equatable {
  final String id;
  final String label;
  final String emoji;

  const CategoryEntity({
    required this.id,
    required this.label,
    required this.emoji,
  });

  @override
  List<Object?> get props => [id, label, emoji];
}
