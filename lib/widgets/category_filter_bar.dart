// FILE: lib/widgets/category_filter_bar.dart
import 'package:flutter/material.dart';

class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.selectedKey,
    required this.onChanged,
  });

  final String? selectedKey;
  final ValueChanged<String?> onChanged;

  static const cats = [
    {"key": null, "label": "전체"},
    {"key": "living", "label": "생활/가전"},
    {"key": "kitchen", "label": "주방/요리"},
    {"key": "electronics", "label": "PC/전자기기"},
    {"key": "creator", "label": "촬영/크리에이터"},
    {"key": "camping", "label": "캠핑/레저"},
    {"key": "fashion", "label": "의류/패션 소품"},
    {"key": "hobby", "label": "취미/게임"},
    {"key": "kids", "label": "유아/키즈"},
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = cats[i]['key'] as String?;
          final label = cats[i]['label'] as String;
          final selected = key == selectedKey || (key == null && selectedKey == null);
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onChanged(key),
            selectedColor: cs.primary.withOpacity(.15),
          );
        },
      ),
    );
  }
}
